//
//  BiometricSynthEngine.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import AVFoundation
import Combine
import Foundation

final class BiometricSynthEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorText: String?

    private let engine = AVAudioEngine()
    private let stateLock = NSLock()

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false
    private var renderState: RenderState

    private var currentFrame: Int64 = 0
    private var lastStep = -1

    private var padPhase = 0.0
    private var padDetunePhase = 0.0
    private var bassPhase = 0.0
    private var kickPhase = 0.0
    private var snareTonePhase = 0.0
    private var wobblePhase = 0.0

    private var kickEnvelope = 0.0
    private var snareEnvelope = 0.0
    private var hatEnvelope = 0.0
    private var bassEnvelope = 0.0

    private var hatNoiseMemory = 0.0
    private var noiseSeed: UInt64 = 0x1234ABCD

    init(profile: BiometricsProfile) {
        renderState = RenderState(profile: profile)
    }

    func togglePlayback() {
        isPlaying ? stop() : start()
    }

    func updateProfile(_ profile: BiometricsProfile) {
        stateLock.lock()
        renderState = RenderState(profile: profile)
        stateLock.unlock()
    }

    func start() {
        if isPlaying {
            return
        }

        do {
            try configureSession()
            try configureEngineIfNeeded()
            try engine.start()
            isPlaying = true
            errorText = nil
        } catch {
            errorText = "声音启动失败：\(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        engine.pause()
        isPlaying = false
        kickEnvelope = 0
        snareEnvelope = 0
        hatEnvelope = 0
        bassEnvelope = 0
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func configureEngineIfNeeded() throws {
        if isConfigured {
            return
        }

        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44_100

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else {
                return noErr
            }

            let state = self.snapshotState()
            let stepLength = max(1, Int(sampleRate * 60.0 / state.tempo / 4.0))
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0 ..< Int(frameCount) {
                let currentStep = Int((self.currentFrame / Int64(stepLength)) % 16)

                if currentStep != self.lastStep {
                    self.lastStep = currentStep
                    self.trigger(step: currentStep, state: state)
                }

                let pad = self.nextPadSample(sampleRate: sampleRate, state: state)
                let bass = self.nextBassSample(sampleRate: sampleRate, state: state)
                let kick = self.nextKickSample(sampleRate: sampleRate)
                let snare = self.nextSnareSample(sampleRate: sampleRate, state: state)
                let hat = self.nextHatSample(state: state)
                let roomNoise = self.nextNoiseBed(state: state)

                let sampleValue = self.clamped(pad + bass + kick + snare + hat + roomNoise)

                for buffer in bufferList {
                    let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = Float(sampleValue)
                }

                self.currentFrame += 1
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.95
        engine.prepare()
        isConfigured = true
    }

    private func snapshotState() -> RenderState {
        stateLock.lock()
        let snapshot = renderState
        stateLock.unlock()
        return snapshot
    }

    private func trigger(step: Int, state: RenderState) {
        if state.kickPattern[step] {
            kickEnvelope = 1.0
            kickPhase = 0
        }

        if state.snarePattern[step] {
            snareEnvelope = max(snareEnvelope, 1.0)
            snareTonePhase = 0
        }

        if state.hatPattern[step] {
            hatEnvelope = max(hatEnvelope, 0.68 + state.activityLevel * 0.3)
        }

        if state.bassPattern[step] {
            bassEnvelope = 1.0
            bassPhase = 0
        }
    }

    private func nextPadSample(sampleRate: Double, state: RenderState) -> Double {
        let wobbleStep = (2.0 * Double.pi * 0.18) / sampleRate
        wobblePhase += wobbleStep

        if wobblePhase > 2.0 * Double.pi {
            wobblePhase -= 2.0 * Double.pi
        }

        let wobble = sin(wobblePhase) * (0.8 + state.recoveryScore * 0.6)
        let primaryFrequency = state.baseFrequency + wobble
        let secondaryFrequency = state.baseFrequency * 1.5

        padPhase += (2.0 * Double.pi * primaryFrequency) / sampleRate
        padDetunePhase += (2.0 * Double.pi * secondaryFrequency) / sampleRate

        if padPhase > 2.0 * Double.pi {
            padPhase -= 2.0 * Double.pi
        }

        if padDetunePhase > 2.0 * Double.pi {
            padDetunePhase -= 2.0 * Double.pi
        }

        let triangle = asin(sin(padPhase)) * (2.0 / Double.pi)
        let pad = (triangle * 0.058) + (sin(padDetunePhase) * 0.032)
        return pad * (0.62 + state.padDepth * 0.52)
    }

    private func nextBassSample(sampleRate: Double, state: RenderState) -> Double {
        guard bassEnvelope > 0.0008 else {
            return 0
        }

        let bassFrequency = max(42, state.baseFrequency * 0.5)
        bassPhase += (2.0 * Double.pi * bassFrequency) / sampleRate
        if bassPhase > 2.0 * Double.pi {
            bassPhase -= 2.0 * Double.pi
        }

        let sample = sin(bassPhase) * bassEnvelope * 0.22
        bassEnvelope *= 0.9986 - (state.activityLevel * 0.0005)
        return sample
    }

    private func nextKickSample(sampleRate: Double) -> Double {
        guard kickEnvelope > 0.0008 else {
            return 0
        }

        let pitch = 44 + (kickEnvelope * 36)
        kickPhase += (2.0 * Double.pi * pitch) / sampleRate
        if kickPhase > 2.0 * Double.pi {
            kickPhase -= 2.0 * Double.pi
        }

        let sample = sin(kickPhase) * kickEnvelope * 0.92
        kickEnvelope *= 0.9942
        return sample
    }

    private func nextSnareSample(sampleRate: Double, state: RenderState) -> Double {
        guard snareEnvelope > 0.0008 else {
            return 0
        }

        snareTonePhase += (2.0 * Double.pi * 178.0) / sampleRate
        if snareTonePhase > 2.0 * Double.pi {
            snareTonePhase -= 2.0 * Double.pi
        }

        let noise = nextWhiteNoise()
        let tonal = sin(snareTonePhase) * 0.22
        let sample = (noise * 0.54 + tonal) * snareEnvelope * (0.34 + state.stressLevel * 0.4)

        snareEnvelope *= 0.986
        return sample
    }

    private func nextHatSample(state: RenderState) -> Double {
        guard hatEnvelope > 0.0008 else {
            return 0
        }

        let white = nextWhiteNoise()
        let highPassed = white - (hatNoiseMemory * 0.78)
        hatNoiseMemory = white

        let sample = highPassed * hatEnvelope * (0.08 + state.activityLevel * 0.05)
        hatEnvelope *= 0.974 - (state.stressLevel * 0.004)
        return sample
    }

    private func nextNoiseBed(state: RenderState) -> Double {
        let texture = nextWhiteNoise()
        return texture * state.noiseLevel * 0.012
    }

    private func nextWhiteNoise() -> Double {
        noiseSeed = 6364136223846793005 &* noiseSeed &+ 1
        let value = Double((noiseSeed >> 11) & 0xFFFF) / Double(0xFFFF)
        return (value * 2.0) - 1.0
    }

    private func clamped(_ sample: Double) -> Double {
        let shaped = tanh(sample * 1.55)
        return min(max(shaped, -0.95), 0.95)
    }
}

private struct RenderState {
    let tempo: Double
    let noiseLevel: Double
    let padDepth: Double
    let activityLevel: Double
    let stressLevel: Double
    let recoveryScore: Double
    let baseFrequency: Double
    let kickPattern: [Bool]
    let snarePattern: [Bool]
    let hatPattern: [Bool]
    let bassPattern: [Bool]

    init(profile: BiometricsProfile) {
        tempo = profile.tempo
        noiseLevel = profile.noiseLevel
        padDepth = profile.padDepth
        activityLevel = profile.activityLevel
        stressLevel = profile.stressLevel
        recoveryScore = profile.recoveryScore
        baseFrequency = Self.baseFrequency(for: profile.key)

        var kick = Array(repeating: false, count: 16)
        var snare = Array(repeating: false, count: 16)
        var hat = Array(repeating: false, count: 16)
        var bass = Array(repeating: false, count: 16)

        [0, 8].forEach { kick[$0] = true }
        [4, 12].forEach { snare[$0] = true }
        [0, 6, 10, 14].forEach { bass[$0] = true }

        for step in stride(from: 0, to: 16, by: 2) {
            hat[step] = true
        }

        if activityLevel > 0.42 {
            [3, 7, 11, 15].forEach { hat[$0] = true }
        }

        if activityLevel > 0.68 {
            [1, 5, 9, 13].forEach { hat[$0] = true }
            kick[10] = true
        }

        if stressLevel > 0.62 {
            kick[14] = true
            snare[15] = true
        }

        if recoveryScore > 0.7 {
            bass[2] = true
            bass[12] = true
        }

        kickPattern = kick
        snarePattern = snare
        hatPattern = hat
        bassPattern = bass
    }

    private static func baseFrequency(for key: String) -> Double {
        switch key {
        case "F 大调":
            return 174.61
        case "A 小调":
            return 220.0
        default:
            return 146.83
        }
    }
}
