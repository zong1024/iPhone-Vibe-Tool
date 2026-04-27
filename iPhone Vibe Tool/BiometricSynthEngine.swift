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
    private var leadPhase = 0.0
    private var leadDetunePhase = 0.0
    private var sweepPhase = 0.0

    private var kickEnvelope = 0.0
    private var snareEnvelope = 0.0
    private var clapEnvelope = 0.0
    private var hatEnvelope = 0.0
    private var bassEnvelope = 0.0
    private var leadEnvelope = 0.0
    private var currentLeadFrequency = 220.0

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
        clapEnvelope = 0
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
                let clap = self.nextClapSample(scene: scene)
                let hat = self.nextHatSample(state: state, scene: scene)
                let lead = self.nextLeadSample(sampleRate: sampleRate, scene: scene)
                let sweep = self.nextSweepSample(sampleRate: sampleRate, scene: scene)
                let roomNoise = self.nextNoiseBed(state: state, scene: scene)

                let sampleValue = self.clamped(pad + bass + kick + snare + clap + hat + lead + sweep + roomNoise)
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

        if scene.clapPattern[step] {
            clapEnvelope = max(clapEnvelope, 1.0)
        }

        if scene.hatPattern[step] {
            hatEnvelope = max(hatEnvelope, 0.58 + scene.motion * 0.42)
        }

        if scene.bassPattern[step] {
            bassEnvelope = 1.0
            bassPhase = 0
        }

        if scene.leadPattern[step] {
            currentLeadFrequency = scene.leadFrequencies[step]
            leadEnvelope = max(leadEnvelope, scene.leadAttack)
        }
    }

    private func nextPadSample(sampleRate: Double, state: RenderState, scene: LiveScene) -> Double {
        let wobbleStep = (2.0 * Double.pi * scene.wobbleRate) / sampleRate
        wobblePhase += wobbleStep

        if wobblePhase > 2.0 * Double.pi {
            wobblePhase -= 2.0 * Double.pi
        }

        let wobble = sin(wobblePhase) * scene.padMotion
        let primaryFrequency = scene.rootFrequency + wobble
        let secondaryFrequency = scene.rootFrequency * scene.padHarmonic

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
        let ducking = 1.0 - ((kickEnvelope * scene.sidechainDepth) + (clapEnvelope * 0.12))
        return pad * scene.padGain * (0.62 + state.padDepth * 0.52) * max(0.42, ducking)
    }

    private func nextBassSample(sampleRate: Double, state: RenderState, scene: LiveScene) -> Double {
        guard bassEnvelope > 0.0008 else {
            return 0
        }

        let bassFrequency = max(42, scene.rootFrequency * scene.bassRatio + scene.bassOffset)
        bassPhase += (2.0 * Double.pi * bassFrequency) / sampleRate
        if bassPhase > 2.0 * Double.pi {
            bassPhase -= 2.0 * Double.pi
        }

        let sine = sin(bassPhase)
        let harmonic = sin(bassPhase * 2.0) * scene.bassHarmonic
        let sample = tanh((sine + harmonic) * scene.bassDrive) * bassEnvelope * scene.bassGain
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

        let body = sin(kickPhase)
        let click = nextWhiteNoise() * kickEnvelope * scene.kickClick
        let sample = tanh((body * scene.kickDrive) + click) * kickEnvelope * scene.kickGain
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

    private func nextClapSample(scene: LiveScene) -> Double {
        guard clapEnvelope > 0.0008 else {
            return 0
        }

        let burst = nextWhiteNoise()
        let body = sin(snareTonePhase * 1.65) * 0.18
        let flutter = sin(snareTonePhase * 3.4) * 0.08
        let sample = tanh((burst * 0.72) + body + flutter) * clapEnvelope * scene.clapGain

        clapEnvelope *= scene.clapDecay
        return sample
    }

    private func nextHatSample(state: RenderState, scene: LiveScene) -> Double {
        guard hatEnvelope > 0.0008 else {
            return 0
        }

        let white = nextWhiteNoise()
        let highPassed = white - (hatNoiseMemory * 0.78)
        hatNoiseMemory = white

        let accented = highPassed + (nextWhiteNoise() * 0.14)
        let sample = accented * hatEnvelope * scene.hatGain * scene.hatBrightness
        hatEnvelope *= scene.hatDecay - (state.stressLevel * 0.003)
        return sample
    }

    private func nextLeadSample(sampleRate: Double, scene: LiveScene) -> Double {
        guard leadEnvelope > 0.0008 else {
            return 0
        }

        leadPhase += (2.0 * Double.pi * currentLeadFrequency) / sampleRate
        leadDetunePhase += (2.0 * Double.pi * (currentLeadFrequency * 1.004)) / sampleRate

        if leadPhase > 2.0 * Double.pi {
            leadPhase -= 2.0 * Double.pi
        }

        if leadDetunePhase > 2.0 * Double.pi {
            leadDetunePhase -= 2.0 * Double.pi
        }

        let bright = sin(leadPhase)
        let detuned = asin(sin(leadDetunePhase)) * (2.0 / Double.pi)
        let lead = tanh((bright * 0.92) + (detuned * 0.44)) * leadEnvelope * scene.leadGain

        leadEnvelope *= scene.leadDecay
        return lead
    }

    private func nextSweepSample(sampleRate: Double, scene: LiveScene) -> Double {
        guard scene.sweepGain > 0.0008 else {
            return 0
        }

        sweepPhase += (2.0 * Double.pi * scene.sweepRate) / sampleRate
        if sweepPhase > 2.0 * Double.pi {
            sweepPhase -= 2.0 * Double.pi
        }

        let mod = (sin(sweepPhase) + 1) * 0.5
        let noise = nextWhiteNoise()
        return noise * scene.sweepGain * (0.28 + mod * 0.72)
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
        clapEnvelope = 0
        hatEnvelope = 0
        bassEnvelope = 0
        leadEnvelope = 0
        padPhase = 0
        padDetunePhase = 0
        bassPhase = 0
        kickPhase = 0
        snareTonePhase = 0
        wobblePhase = 0
        leadPhase = 0
        leadDetunePhase = 0
        sweepPhase = 0
        currentLeadFrequency = state.baseFrequency * 1.5
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
            clapEnvelope * 0.66,
            bassEnvelope * 0.5,
            leadEnvelope * 0.44,
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
    let mode: MusicalMode
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
        mode = Self.mode(for: profile.key)
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
        let barIndex = max(0, Int((Double(second) * tempo) / 240.0))
        let phraseBar = barIndex % 16
        let section = SongSection(phraseBar: phraseBar)
        let chord = Self.chord(for: mode, baseFrequency: baseFrequency, barIndex: barIndex)
        let density = Self.clamp((activityLevel * 0.34) + (moment.motion * 0.48) + 0.18)
        let tension = Self.clamp((stressLevel * 0.46) + (moment.tension * 0.42) + 0.12)
        let softness = Self.clamp((recoveryScore * 0.46) + (moment.warmth * 0.40) + 0.14)
        let sectionEnergy = section.energyBias
        let energy = Self.clamp((density * 0.52) + (tension * 0.28) + ((1 - softness) * 0.08) + sectionEnergy)
        let sceneSeed = seed &+ UInt64(second &* 97)

        var kick = Array(repeating: false, count: 16)
        var snare = Array(repeating: false, count: 16)
        var clap = Array(repeating: false, count: 16)
        var hat = Array(repeating: false, count: 16)
        var bass = Array(repeating: false, count: 16)
        var lead = Array(repeating: false, count: 16)
        var leadFrequencies = Array(repeating: chord.rootFrequency * 2.0, count: 16)

        [0, 8].forEach { kick[$0] = true }
        [4, 12].forEach { snare[$0] = true }
        [4, 12].forEach { clap[$0] = true }
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

        if energy > 0.64 && Self.random01(sceneSeed, salt: 9) > 0.44 {
            kick[6] = true
        }

        if tension > 0.62 || Self.random01(sceneSeed, salt: 5) > 0.68 {
            snare[15] = true
        }

        if density > 0.6 && Self.random01(sceneSeed, salt: 6) > 0.52 {
            snare[7] = true
        }

        if energy > 0.52 && Self.random01(sceneSeed, salt: 17) > 0.58 {
            clap[11] = true
        }

        if tension > 0.58 && Self.random01(sceneSeed, salt: 18) > 0.5 {
            clap[15] = true
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

        let leadTemplate = section.leadTemplate
        for step in leadTemplate {
            lead[step] = true
            let noteIndex = (step + phraseBar + Int(sceneSeed % 3)) % chord.leadPalette.count
            leadFrequencies[step] = chord.leadPalette[noteIndex]
        }

        switch section {
        case .intro:
            [10, 14].forEach { hat[$0] = false }
            clap = Array(repeating: false, count: 16)
            lead = Array(repeating: false, count: 16)
        case .groove:
            break
        case .lift:
            [3, 7, 11, 15].forEach { hat[$0] = true }
            if Self.random01(sceneSeed, salt: 25) > 0.34 {
                lead[15] = true
                leadFrequencies[15] = chord.leadPalette.last ?? (chord.rootFrequency * 2.0)
            }
        case .drop:
            [1, 5, 9, 13].forEach { hat[$0] = true }
            if Self.random01(sceneSeed, salt: 26) > 0.42 {
                kick[2] = true
                kick[11] = true
            }
        case .breakdown:
            kick[8] = false
            kick[10] = false
            hat = Array(repeating: false, count: 16)
            [6, 14].forEach { hat[$0] = true }
            bass[6] = false
            clap[11] = false
        case .finale:
            [1, 3, 5, 7, 9, 11, 13, 15].forEach { hat[$0] = true }
            if Self.random01(sceneSeed, salt: 27) > 0.3 {
                kick[2] = true
                snare[6] = true
                clap[14] = true
            }
        }

        let visualProfile = [
            0.24 + density * 0.18,
            0.34 + tension * 0.22,
            0.28 + softness * 0.18,
            0.40 + moment.motion * 0.22 + section.visualLift * 0.06,
            0.30 + tension * 0.20,
            0.48 + density * 0.24,
            0.34 + softness * 0.22,
            0.54 + tension * 0.20 + section.visualLift * 0.08,
            0.28 + moment.motion * 0.20,
            0.46 + softness * 0.24,
            0.32 + density * 0.18,
            0.58 + tension * 0.18 + section.visualLift * 0.1
        ]
        .map { CGFloat(Self.clamp($0)) }

        return LiveScene(
            section: section,
            rootFrequency: chord.rootFrequency,
            kickPattern: kick,
            snarePattern: snare,
            clapPattern: clap,
            hatPattern: hat,
            bassPattern: bass,
            leadPattern: lead,
            leadFrequencies: leadFrequencies,
            kickGain: 0.78 + (energy * 0.28),
            snareGain: 0.48 + (tension * 0.22),
            clapGain: 0.24 + (energy * 0.14),
            hatGain: 0.10 + (density * 0.07),
            bassGain: 0.21 + (softness * 0.09),
            padGain: 0.76 + (softness * 0.28) + section.padBias,
            noiseGain: 0.007 + (tension * 0.008),
            wobbleRate: 0.11 + (softness * 0.16),
            padMotion: 0.32 + (softness * 0.92) + section.motionBias,
            padHarmonic: chord.padHarmonic,
            bassRatio: 0.42 + (moment.motion * 0.12),
            bassOffset: density * 6.0,
            bassDrive: 1.4 + (energy * 0.95),
            bassHarmonic: 0.16 + (energy * 0.18),
            kickPitch: 42 + (tension * 9),
            kickDrive: 1.42 + (energy * 0.46),
            kickClick: 0.045 + (energy * 0.05),
            snarePitch: 164 + (tension * 32),
            snareNoiseMix: 0.46 + (tension * 0.16),
            clapDecay: 0.938 - (energy * 0.012),
            hatBrightness: 0.88 + (density * 0.38),
            hatDecay: 0.976 - (energy * 0.01),
            sidechainDepth: 0.18 + (energy * 0.22),
            leadGain: section.leadGain + (energy * 0.12),
            leadDecay: section.leadDecay,
            leadAttack: section.leadAttack,
            sweepGain: section.sweepGain + (tension * 0.018),
            sweepRate: section.sweepRate,
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

    private static func mode(for key: String) -> MusicalMode {
        switch key {
        case "F 大调":
            return .major
        default:
            return .minor
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

    private static func chord(for mode: MusicalMode, baseFrequency: Double, barIndex: Int) -> ChordSpec {
        let progression: [Int]
        switch mode {
        case .major:
            progression = [0, 9, 5, 7]
        case .minor:
            progression = [0, 8, 3, 10]
        }

        let rootSemitone = progression[barIndex % progression.count]
        let rootFrequency = baseFrequency * pow(2.0, Double(rootSemitone) / 12.0)
        let leadSteps: [Int]
        switch mode {
        case .major:
            leadSteps = [0, 4, 7, 9, 12, 16]
        case .minor:
            leadSteps = [0, 3, 7, 10, 12, 15]
        }

        let leadPalette = leadSteps.map { rootFrequency * pow(2.0, Double($0) / 12.0) }
        let padHarmonic = mode == .major ? 1.50 : 1.42

        return ChordSpec(
            rootFrequency: rootFrequency,
            padHarmonic: padHarmonic,
            leadPalette: leadPalette
        )
    }
}

private struct DayMoment {
    let motion: Double
    let tension: Double
    let warmth: Double
}

private enum MusicalMode {
    case major
    case minor
}

private enum SongSection {
    case intro
    case groove
    case lift
    case drop
    case breakdown
    case finale

    init(phraseBar: Int) {
        switch phraseBar {
        case 0 ... 1:
            self = .intro
        case 2 ... 5:
            self = .groove
        case 6 ... 7:
            self = .lift
        case 8 ... 11:
            self = .drop
        case 12 ... 13:
            self = .breakdown
        default:
            self = .finale
        }
    }

    var energyBias: Double {
        switch self {
        case .intro:
            return -0.12
        case .groove:
            return 0.02
        case .lift:
            return 0.1
        case .drop:
            return 0.22
        case .breakdown:
            return -0.08
        case .finale:
            return 0.26
        }
    }

    var padBias: Double {
        switch self {
        case .intro, .breakdown:
            return 0.14
        case .lift:
            return 0.08
        case .drop, .finale:
            return -0.02
        case .groove:
            return 0
        }
    }

    var motionBias: Double {
        switch self {
        case .intro:
            return -0.04
        case .lift:
            return 0.08
        case .drop, .finale:
            return 0.12
        default:
            return 0
        }
    }

    var visualLift: Double {
        switch self {
        case .intro:
            return 0.04
        case .groove:
            return 0.1
        case .lift:
            return 0.2
        case .drop:
            return 0.3
        case .breakdown:
            return 0.08
        case .finale:
            return 0.34
        }
    }

    var leadTemplate: [Int] {
        switch self {
        case .intro:
            return []
        case .groove:
            return [2, 6, 10, 14]
        case .lift:
            return [1, 5, 9, 12, 15]
        case .drop:
            return [1, 3, 6, 9, 11, 14]
        case .breakdown:
            return [4, 8, 12]
        case .finale:
            return [1, 3, 5, 8, 10, 13, 15]
        }
    }

    var leadGain: Double {
        switch self {
        case .intro:
            return 0
        case .groove:
            return 0.16
        case .lift:
            return 0.22
        case .drop:
            return 0.26
        case .breakdown:
            return 0.18
        case .finale:
            return 0.3
        }
    }

    var leadDecay: Double {
        switch self {
        case .intro:
            return 0.94
        case .groove:
            return 0.968
        case .lift:
            return 0.974
        case .drop:
            return 0.978
        case .breakdown:
            return 0.97
        case .finale:
            return 0.979
        }
    }

    var leadAttack: Double {
        switch self {
        case .intro:
            return 0
        case .groove:
            return 0.72
        case .lift:
            return 0.82
        case .drop:
            return 0.9
        case .breakdown:
            return 0.78
        case .finale:
            return 0.94
        }
    }

    var sweepGain: Double {
        switch self {
        case .lift:
            return 0.02
        case .drop:
            return 0.008
        case .finale:
            return 0.015
        default:
            return 0
        }
    }

    var sweepRate: Double {
        switch self {
        case .lift:
            return 0.32
        case .drop:
            return 0.18
        case .finale:
            return 0.28
        default:
            return 0.12
        }
    }
}

private struct ChordSpec {
    let rootFrequency: Double
    let padHarmonic: Double
    let leadPalette: [Double]
}

private struct LiveScene {
    let section: SongSection
    let rootFrequency: Double
    let kickPattern: [Bool]
    let snarePattern: [Bool]
    let clapPattern: [Bool]
    let hatPattern: [Bool]
    let bassPattern: [Bool]
    let leadPattern: [Bool]
    let leadFrequencies: [Double]
    let kickGain: Double
    let snareGain: Double
    let clapGain: Double
    let hatGain: Double
    let bassGain: Double
    let padGain: Double
    let noiseGain: Double
    let wobbleRate: Double
    let padMotion: Double
    let padHarmonic: Double
    let bassRatio: Double
    let bassOffset: Double
    let bassDrive: Double
    let bassHarmonic: Double
    let kickPitch: Double
    let kickDrive: Double
    let kickClick: Double
    let snarePitch: Double
    let snareNoiseMix: Double
    let clapDecay: Double
    let hatBrightness: Double
    let hatDecay: Double
    let sidechainDepth: Double
    let leadGain: Double
    let leadDecay: Double
    let leadAttack: Double
    let sweepGain: Double
    let sweepRate: Double
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
