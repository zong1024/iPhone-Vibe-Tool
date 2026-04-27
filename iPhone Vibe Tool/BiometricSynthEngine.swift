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
    @Published private(set) var visualizerLevels = Array(repeating: CGFloat(0.18), count: 12)

    private let engine = AVAudioEngine()
    private let stateLock = NSLock()

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false
    private var renderState: RenderState
    private var currentScene: LiveScene
    private var meterCancellable: AnyCancellable?
    private var meterSnapshot = MeterSnapshot.idle

    private var currentFrame: Int64 = 0
    private var lastStep = -1
    private var lastSceneSecond = -1

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
        currentScene = renderState.scene(forSecond: 0)
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
            resetTransport()
            try engine.start()
            startMeterUpdatesIfNeeded()
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
        stateLock.lock()
        meterSnapshot = .idle
        stateLock.unlock()
        visualizerLevels = Array(repeating: 0.18, count: 12)
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
            let samplesPerSecond = max(Int64(1), Int64(sampleRate.rounded()))
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            var peak = 0.0

            for frame in 0 ..< Int(frameCount) {
                let sceneSecond = Int(self.currentFrame / samplesPerSecond)
                let scene = self.scene(forSecond: sceneSecond, state: state)
                let currentStep = Int((self.currentFrame / Int64(stepLength)) % 16)

                if currentStep != self.lastStep {
                    self.lastStep = currentStep
                    self.trigger(step: currentStep, state: state, scene: scene)
                }

                let pad = self.nextPadSample(sampleRate: sampleRate, state: state, scene: scene)
                let bass = self.nextBassSample(sampleRate: sampleRate, state: state, scene: scene)
                let kick = self.nextKickSample(sampleRate: sampleRate, scene: scene)
                let snare = self.nextSnareSample(sampleRate: sampleRate, state: state, scene: scene)
                let hat = self.nextHatSample(state: state, scene: scene)
                let roomNoise = self.nextNoiseBed(state: state, scene: scene)

                let sampleValue = self.clamped(pad + bass + kick + snare + hat + roomNoise)
                peak = max(peak, abs(sampleValue))

                for buffer in bufferList {
                    let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = Float(sampleValue)
                }

                self.currentFrame += 1
            }

            self.updateMeterSnapshot(stepLength: stepLength, peak: peak)
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

    private func scene(forSecond second: Int, state: RenderState) -> LiveScene {
        if second != lastSceneSecond {
            lastSceneSecond = second
            currentScene = state.scene(forSecond: second)
        }

        return currentScene
    }

    private func trigger(step: Int, state: RenderState, scene: LiveScene) {
        if scene.kickPattern[step] {
            kickEnvelope = 1.0
            kickPhase = 0
        }

        if scene.snarePattern[step] {
            snareEnvelope = max(snareEnvelope, 1.0)
            snareTonePhase = 0
        }

        if scene.hatPattern[step] {
            hatEnvelope = max(hatEnvelope, 0.58 + scene.motion * 0.42)
        }

        if scene.bassPattern[step] {
            bassEnvelope = 1.0
            bassPhase = 0
        }
    }

    private func nextPadSample(sampleRate: Double, state: RenderState, scene: LiveScene) -> Double {
        let wobbleStep = (2.0 * Double.pi * scene.wobbleRate) / sampleRate
        wobblePhase += wobbleStep

        if wobblePhase > 2.0 * Double.pi {
            wobblePhase -= 2.0 * Double.pi
        }

        let wobble = sin(wobblePhase) * scene.padMotion
        let primaryFrequency = state.baseFrequency + wobble
        let secondaryFrequency = state.baseFrequency * scene.padHarmonic

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
        return pad * scene.padGain * (0.62 + state.padDepth * 0.52)
    }

    private func nextBassSample(sampleRate: Double, state: RenderState, scene: LiveScene) -> Double {
        guard bassEnvelope > 0.0008 else {
            return 0
        }

        let bassFrequency = max(42, state.baseFrequency * scene.bassRatio + scene.bassOffset)
        bassPhase += (2.0 * Double.pi * bassFrequency) / sampleRate
        if bassPhase > 2.0 * Double.pi {
            bassPhase -= 2.0 * Double.pi
        }

        let sample = sin(bassPhase) * bassEnvelope * scene.bassGain
        bassEnvelope *= 0.9978 - (scene.motion * 0.0008)
        return sample
    }

    private func nextKickSample(sampleRate: Double, scene: LiveScene) -> Double {
        guard kickEnvelope > 0.0008 else {
            return 0
        }

        let pitch = scene.kickPitch + (kickEnvelope * 34)
        kickPhase += (2.0 * Double.pi * pitch) / sampleRate
        if kickPhase > 2.0 * Double.pi {
            kickPhase -= 2.0 * Double.pi
        }

        let sample = sin(kickPhase) * kickEnvelope * scene.kickGain
        kickEnvelope *= 0.9942
        return sample
    }

    private func nextSnareSample(sampleRate: Double, state: RenderState, scene: LiveScene) -> Double {
        guard snareEnvelope > 0.0008 else {
            return 0
        }

        snareTonePhase += (2.0 * Double.pi * scene.snarePitch) / sampleRate
        if snareTonePhase > 2.0 * Double.pi {
            snareTonePhase -= 2.0 * Double.pi
        }

        let noise = nextWhiteNoise()
        let tonal = sin(snareTonePhase) * 0.22
        let sample = (noise * scene.snareNoiseMix + tonal) * snareEnvelope * scene.snareGain * (0.34 + state.stressLevel * 0.4)

        snareEnvelope *= 0.986
        return sample
    }

    private func nextHatSample(state: RenderState, scene: LiveScene) -> Double {
        guard hatEnvelope > 0.0008 else {
            return 0
        }

        let white = nextWhiteNoise()
        let highPassed = white - (hatNoiseMemory * 0.78)
        hatNoiseMemory = white

        let sample = highPassed * hatEnvelope * scene.hatGain * scene.hatBrightness
        hatEnvelope *= 0.972 - (state.stressLevel * 0.004)
        return sample
    }

    private func nextNoiseBed(state: RenderState, scene: LiveScene) -> Double {
        let texture = nextWhiteNoise()
        return texture * state.noiseLevel * scene.noiseGain
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

    private func resetTransport() {
        let state = snapshotState()
        currentFrame = 0
        lastStep = -1
        lastSceneSecond = -1
        currentScene = state.scene(forSecond: 0)
        kickEnvelope = 0
        snareEnvelope = 0
        hatEnvelope = 0
        bassEnvelope = 0
        padPhase = 0
        padDetunePhase = 0
        bassPhase = 0
        kickPhase = 0
        snareTonePhase = 0
        wobblePhase = 0
        hatNoiseMemory = 0
    }

    private func startMeterUpdatesIfNeeded() {
        guard meterCancellable == nil else {
            return
        }

        meterCancellable = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.publishVisualizer()
            }
    }

    private func updateMeterSnapshot(stepLength: Int, peak: Double) {
        let barLength = max(1, stepLength * 4)
        let phase = Double(currentFrame % Int64(barLength)) / Double(barLength)
        let transient = max(
            peak * 1.35,
            kickEnvelope * 0.9,
            snareEnvelope * 0.72,
            bassEnvelope * 0.5,
            hatEnvelope * 0.38
        )

        stateLock.lock()
        meterSnapshot = MeterSnapshot(
            isPlaying: isPlaying,
            pulse: min(max(transient, 0), 1),
            phase: phase,
            activeStep: max(lastStep, 0),
            template: currentScene.visualProfile
        )
        stateLock.unlock()
    }

    private func publishVisualizer() {
        stateLock.lock()
        let snapshot = meterSnapshot
        stateLock.unlock()

        let nextLevels: [CGFloat]
        if snapshot.isPlaying {
            nextLevels = snapshot.template.enumerated().map { index, base in
                let orbit = sin((snapshot.phase * Double.pi * 2.0) + (Double(index) * 0.55)) * 0.09
                let shimmer = cos((snapshot.phase * Double.pi * 4.0) + (Double(index) * 0.31)) * 0.05
                let accent = index == snapshot.activeStep % snapshot.template.count ? snapshot.pulse * 0.26 : 0
                let echo = index == (snapshot.activeStep + 5) % snapshot.template.count ? snapshot.pulse * 0.12 : 0
                let level = Self.clampVisualizer(Double(base) + orbit + shimmer + accent + echo)
                return CGFloat(level)
            }
        } else {
            nextLevels = Array(repeating: 0.18, count: 12)
        }

        visualizerLevels = nextLevels
    }

    private static func clampVisualizer(_ value: Double) -> Double {
        min(max(value, 0.14), 0.98)
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
    let seed: UInt64
    let dayMoments: [DayMoment]

    init(profile: BiometricsProfile) {
        tempo = profile.tempo
        noiseLevel = profile.noiseLevel
        padDepth = profile.padDepth
        activityLevel = profile.activityLevel
        stressLevel = profile.stressLevel
        recoveryScore = profile.recoveryScore
        baseFrequency = Self.baseFrequency(for: profile.key)
        seed = Self.makeSeed(profile: profile)
        dayMoments = Self.makeDayMoments(
            activityLevel: activityLevel,
            stressLevel: stressLevel,
            recoveryScore: recoveryScore,
            seed: seed
        )
    }

    func scene(forSecond second: Int) -> LiveScene {
        let moment = dayMoments[second % dayMoments.count]
        let density = Self.clamp((activityLevel * 0.34) + (moment.motion * 0.48) + 0.18)
        let tension = Self.clamp((stressLevel * 0.46) + (moment.tension * 0.42) + 0.12)
        let softness = Self.clamp((recoveryScore * 0.46) + (moment.warmth * 0.40) + 0.14)
        let sceneSeed = seed &+ UInt64(second &* 97)

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

        if density > 0.42 || Self.random01(sceneSeed, salt: 1) > 0.64 {
            kick[10] = true
        }

        if tension > 0.56 || Self.random01(sceneSeed, salt: 2) > 0.72 {
            kick[14] = true
        }

        if density > 0.58 && Self.random01(sceneSeed, salt: 3) > 0.34 {
            kick[3] = true
        }

        if density > 0.72 && Self.random01(sceneSeed, salt: 4) > 0.42 {
            kick[15] = true
        }

        if tension > 0.62 || Self.random01(sceneSeed, salt: 5) > 0.68 {
            snare[15] = true
        }

        if density > 0.6 && Self.random01(sceneSeed, salt: 6) > 0.52 {
            snare[7] = true
        }

        if softness > 0.62 && Self.random01(sceneSeed, salt: 7) > 0.5 {
            bass[2] = true
            bass[12] = true
        }

        if density > 0.7 && Self.random01(sceneSeed, salt: 8) > 0.5 {
            bass[5] = true
        }

        for step in 1..<16 where !step.isMultiple(of: 2) {
            let chance = 0.08 + (density * 0.42) + (moment.motion * 0.14)
            if Self.random01(sceneSeed, salt: UInt64(10 + step)) < chance {
                hat[step] = true
            }
        }

        let visualProfile = [
            0.24 + density * 0.18,
            0.34 + tension * 0.22,
            0.28 + softness * 0.18,
            0.40 + moment.motion * 0.22,
            0.30 + tension * 0.20,
            0.48 + density * 0.24,
            0.34 + softness * 0.22,
            0.54 + tension * 0.20,
            0.28 + moment.motion * 0.20,
            0.46 + softness * 0.24,
            0.32 + density * 0.18,
            0.58 + tension * 0.18
        ]
        .map { CGFloat(Self.clamp($0)) }

        return LiveScene(
            kickPattern: kick,
            snarePattern: snare,
            hatPattern: hat,
            bassPattern: bass,
            kickGain: 0.72 + (density * 0.24),
            snareGain: 0.44 + (tension * 0.18),
            hatGain: 0.08 + (density * 0.06),
            bassGain: 0.17 + (softness * 0.08),
            padGain: 0.82 + (softness * 0.34),
            noiseGain: 0.007 + (tension * 0.008),
            wobbleRate: 0.11 + (softness * 0.16),
            padMotion: 0.4 + (softness * 1.05),
            padHarmonic: 1.35 + (moment.warmth * 0.32),
            bassRatio: 0.42 + (moment.motion * 0.12),
            bassOffset: density * 6.0,
            kickPitch: 42 + (tension * 9),
            snarePitch: 164 + (tension * 32),
            snareNoiseMix: 0.46 + (tension * 0.16),
            hatBrightness: 0.88 + (density * 0.38),
            motion: moment.motion,
            visualProfile: visualProfile
        )
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

    private static func makeSeed(profile: BiometricsProfile) -> UInt64 {
        UInt64((profile.tempo * 100).rounded()) ^
            UInt64((profile.activityLevel * 10_000).rounded()) &* 31 ^
            UInt64((profile.stressLevel * 10_000).rounded()) &* 131 ^
            UInt64((profile.recoveryScore * 10_000).rounded()) &* 911
    }

    private static func makeDayMoments(
        activityLevel: Double,
        stressLevel: Double,
        recoveryScore: Double,
        seed: UInt64
    ) -> [DayMoment] {
        (0..<96).map { index in
            let time = Double(index) / 96.0
            let circadianRise = (sin((time - 0.18) * .pi * 2) + 1) / 2
            let circadianRest = (cos((time - 0.74) * .pi * 2) + 1) / 2
            let jitter = (random01(seed, salt: UInt64(index)) - 0.5) * 0.18

            let motion = clamp(0.18 + activityLevel * 0.44 + circadianRise * 0.22 - circadianRest * 0.08 + jitter)
            let tension = clamp(0.12 + stressLevel * 0.52 + (1 - recoveryScore) * 0.14 + circadianRise * 0.06 + jitter * 0.8)
            let warmth = clamp(0.16 + recoveryScore * 0.48 + circadianRest * 0.18 - tension * 0.08 - jitter * 0.6)

            return DayMoment(
                motion: motion,
                tension: tension,
                warmth: warmth
            )
        }
    }

    private static func random01(_ seed: UInt64, salt: UInt64) -> Double {
        let mixed = seed &+ (salt &* 0x9E3779B97F4A7C15)
        let hashed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        let final = (hashed ^ (hashed >> 27)) &* 0x94D049BB133111EB
        let value = final ^ (final >> 31)
        return Double(value & 0xFFFF) / Double(0xFFFF)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct DayMoment {
    let motion: Double
    let tension: Double
    let warmth: Double
}

private struct LiveScene {
    let kickPattern: [Bool]
    let snarePattern: [Bool]
    let hatPattern: [Bool]
    let bassPattern: [Bool]
    let kickGain: Double
    let snareGain: Double
    let hatGain: Double
    let bassGain: Double
    let padGain: Double
    let noiseGain: Double
    let wobbleRate: Double
    let padMotion: Double
    let padHarmonic: Double
    let bassRatio: Double
    let bassOffset: Double
    let kickPitch: Double
    let snarePitch: Double
    let snareNoiseMix: Double
    let hatBrightness: Double
    let motion: Double
    let visualProfile: [CGFloat]
}

private struct MeterSnapshot {
    let isPlaying: Bool
    let pulse: Double
    let phase: Double
    let activeStep: Int
    let template: [CGFloat]

    static let idle = MeterSnapshot(
        isPlaying: false,
        pulse: 0,
        phase: 0,
        activeStep: 0,
        template: Array(repeating: 0.18, count: 12)
    )
}
