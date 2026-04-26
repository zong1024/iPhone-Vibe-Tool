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
    private let profile: BiometricsProfile

    private var sourceNode: AVAudioSourceNode?
    private var isConfigured = false

    private var currentFrame: Int64 = 0
    private var tonePhase = 0.0
    private var subPhase = 0.0
    private var kickPhase = 0.0
    private var pulseFramesRemaining = 0

    init(profile: BiometricsProfile) {
        self.profile = profile
    }

    func togglePlayback() {
        isPlaying ? stop() : start()
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
        pulseFramesRemaining = 0
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
        let pulseLength = max(1, Int(sampleRate * 0.08))
        let beatLength = max(1, Int(sampleRate * 60.0 / profile.tempo))

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else {
                return noErr
            }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0 ..< Int(frameCount) {
                if Int(self.currentFrame % Int64(beatLength)) == 0 {
                    self.pulseFramesRemaining = pulseLength
                    self.kickPhase = 0
                }

                let drone = self.nextDroneSample(sampleRate: sampleRate)
                let kick = self.nextKickSample(sampleRate: sampleRate)
                let noise = self.nextNoiseSample()
                let sampleValue = self.clamped(drone + kick + noise)

                for buffer in ablPointer {
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
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        isConfigured = true
    }

    private func nextDroneSample(sampleRate: Double) -> Double {
        let baseFrequency = 220.0
        let subFrequency = 110.0

        let toneStep = (2.0 * Double.pi * baseFrequency) / sampleRate
        let subStep = (2.0 * Double.pi * subFrequency) / sampleRate

        tonePhase += toneStep
        subPhase += subStep

        if tonePhase > 2.0 * Double.pi {
            tonePhase -= 2.0 * Double.pi
        }

        if subPhase > 2.0 * Double.pi {
            subPhase -= 2.0 * Double.pi
        }

        let tone = sin(tonePhase) * 0.07
        let sub = sin(subPhase) * 0.035
        return tone + sub
    }

    private func nextKickSample(sampleRate: Double) -> Double {
        guard pulseFramesRemaining > 0 else {
            return 0
        }

        let elapsed = Double(max(0, pulseFramesRemaining))
        let envelope = elapsed / 3_600.0
        let kickStep = (2.0 * Double.pi * 58.0) / sampleRate
        kickPhase += kickStep
        pulseFramesRemaining -= 1

        return sin(kickPhase) * envelope * 0.9
    }

    private func nextNoiseSample() -> Double {
        let rawNoise = Double.random(in: -1 ... 1)
        return rawNoise * profile.noiseLevel * 0.018
    }

    private func clamped(_ sample: Double) -> Double {
        let shaped = tanh(sample * 1.6)
        return min(max(shaped, -0.95), 0.95)
    }
}
