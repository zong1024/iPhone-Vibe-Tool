//
//  BiometricDataStore.swift
//  iPhone Vibe Tool
//
//  Created by Codex on 2026/4/27.
//

import HealthKit
import SwiftUI

@MainActor
final class BiometricDataStore: ObservableObject {
    @Published private(set) var profile: BiometricsProfile = .sample
    @Published private(set) var sourceLabel = "演示数据"
    @Published private(set) var statusText = "正在使用示例数据。"
    @Published private(set) var detailText = "App 已经可以发声，但如果要真正根据身体状态生成节奏，还需要从 Apple 健康读取数据。"
    @Published private(set) var errorText: String?
    @Published private(set) var isLoading = false

    var isUsingLiveData: Bool {
        sourceLabel == "Apple 健康"
    }

    private var hasLoaded = false
    private let healthKitManager = HealthKitManager()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let result = await healthKitManager.loadSnapshot()

        switch result {
        case .success(let snapshot):
            profile = .live(snapshot)
            sourceLabel = "Apple 健康"
            statusText = "已同步今天的数据，更新时间 \(timeFormatter.string(from: .now))。"
            detailText = profile.insightText
            errorText = nil
        case .fallback(let message):
            profile = .sample
            sourceLabel = "演示数据"
            statusText = "当前未拿到真实健康数据。"
            detailText = "这套节奏先用演示数据驱动。你在真机上授权 HealthKit 后，再点“刷新数据”就会切到当天的身体状态。"
            errorText = message
        }
    }
}

enum HealthLoadResult {
    case success(HealthSnapshot)
    case fallback(String)
}

struct HealthSnapshot {
    let heartRate: Double
    let stepCount: Double
    let sleepHours: Double
    let hrv: Double
}

final class HealthKitManager {
    private let store = HKHealthStore()

    func loadSnapshot() async -> HealthLoadResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .fallback("当前设备不支持 HealthKit，已切回演示数据。")
        }

        do {
            let readTypes = try requiredReadTypes()
            let authorized = try await requestAuthorization(readTypes: readTypes)

            guard authorized else {
                return .fallback("HealthKit 授权没有完成，已切回演示数据。")
            }

            async let heartRate = averageHeartRateToday()
            async let stepCount = stepCountToday()
            async let sleepHours = lastNightSleepHours()
            async let hrv = averageHRVToday()

            let snapshot = try await HealthSnapshot(
                heartRate: heartRate,
                stepCount: stepCount,
                sleepHours: sleepHours,
                hrv: hrv
            )

            guard snapshot.stepCount > 0 || snapshot.sleepHours > 0 || snapshot.heartRate > 0 || snapshot.hrv > 0 else {
                return .fallback("已获得 HealthKit 权限，但今天还没有可用样本。")
            }

            return .success(snapshot)
        } catch {
            return .fallback("读取 Apple 健康失败：\(error.localizedDescription)")
        }
    }

    private func requiredReadTypes() throws -> Set<HKObjectType> {
        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount),
            let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            throw HealthKitManagerError.unsupportedTypes
        }

        return [heartRate, stepCount, hrv, sleep]
    }

    private func requestAuthorization(readTypes: Set<HKObjectType>) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func averageHeartRateToday() async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitManagerError.unsupportedTypes
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now,
            options: .strictStartDate
        )

        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.averageQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func stepCountToday() async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitManagerError.unsupportedTypes
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func averageHRVToday() async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitManagerError.unsupportedTypes
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: .now),
            end: .now,
            options: .strictStartDate
        )

        let unit = HKUnit.secondUnit(with: .milli)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.averageQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            store.execute(query)
        }
    }

    private func lastNightSleepHours() async throws -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitManagerError.unsupportedTypes
        }

        let start = Calendar.current.date(byAdding: .hour, value: -30, to: .now) ?? .now.addingTimeInterval(-108000)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: results as? [HKCategorySample] ?? [])
            }

            store.execute(query)
        }

        let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now.addingTimeInterval(-86400)

        let totalSeconds = samples.reduce(0.0) { partial, sample in
            guard Self.isAsleep(sample) else {
                return partial
            }

            let start = max(sample.startDate, cutoff)
            let end = min(sample.endDate, .now)

            guard end > start else {
                return partial
            }

            return partial + end.timeIntervalSince(start)
        }

        return totalSeconds / 3600
    }

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
            return false
        }

        switch value {
        case .asleep,
             .asleepCore,
             .asleepDeep,
             .asleepREM,
             .asleepUnspecified:
            return true
        default:
            return false
        }
    }
}

enum HealthKitManagerError: LocalizedError {
    case unsupportedTypes

    var errorDescription: String? {
        switch self {
        case .unsupportedTypes:
            return "系统不支持这组健康数据类型。"
        }
    }
}

struct BodyMetric: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
}

struct BiometricsProfile: Equatable {
    let tempo: Double
    let tempoText: String
    let key: String
    let texture: String
    let noiseLevel: Double
    let padDepth: Double
    let activityLevel: Double
    let stressLevel: Double
    let recoveryScore: Double
    let metrics: [BodyMetric]
    let insightText: String
    let playbackNote: String

    var noiseLabel: String {
        switch noiseLevel {
        case ..<0.18:
            "轻"
        case ..<0.3:
            "适中"
        default:
            "偏强"
        }
    }

    var padLabel: String {
        switch padDepth {
        case ..<0.45:
            "短"
        case ..<0.7:
            "适中"
        default:
            "拉长"
        }
    }

    var grooveLabel: String {
        if activityLevel > 0.72 {
            return "碎拍"
        }

        if stressLevel > 0.62 {
            return "前压"
        }

        return "稳拍"
    }

    var waveformLevels: [CGFloat] {
        let base = max(0.12, min(1.0, activityLevel * 0.55 + 0.24))
        let stress = CGFloat(stressLevel)
        let recovery = CGFloat(recoveryScore)

        return [
            0.18,
            base * 0.42,
            0.30 + stress * 0.30,
            0.24 + recovery * 0.18,
            0.36 + stress * 0.18,
            0.48 + CGFloat(activityLevel) * 0.22,
            0.28 + recovery * 0.22,
            0.56 + stress * 0.18,
            0.24 + CGFloat(activityLevel) * 0.18,
            0.52 + recovery * 0.20,
            0.34 + stress * 0.16,
            0.62
        ]
    }

    static let sample = BiometricsProfile(
        tempo: 92,
        tempoText: "92 BPM",
        key: "D 小调",
        texture: "磁带颗粒",
        noiseLevel: 0.24,
        padDepth: 0.68,
        activityLevel: 0.56,
        stressLevel: 0.49,
        recoveryScore: 0.58,
        metrics: [
            BodyMetric(
                title: "心率",
                value: "96 次/分",
                detail: "示例值偏快，低鼓会更紧一些。",
                icon: "heart.fill",
                tint: .pink
            ),
            BodyMetric(
                title: "步数",
                value: "8420",
                detail: "活动量不错，hi-hat 会更活跃。",
                icon: "figure.walk",
                tint: .green
            ),
            BodyMetric(
                title: "睡眠",
                value: "7.1 小时",
                detail: "恢复中，铺底会更长更稳。",
                icon: "bed.double.fill",
                tint: .blue
            ),
            BodyMetric(
                title: "HRV",
                value: "34 ms",
                detail: "压力略高，会带出一些颗粒底噪。",
                icon: "waveform.path.ecg",
                tint: .orange
            )
        ],
        insightText: "演示数据下，App 会合成一段偏稳的 Lo-Fi 节奏。真机授权后，它会改成今天的实际心率、步数、睡眠和 HRV。",
        playbackNote: "现在的声音会按 16 步节拍循环，并根据步数和 HRV 调整鼓组密度、底噪和铺底长度。"
    )

    static func live(_ snapshot: HealthSnapshot) -> BiometricsProfile {
        let normalizedHeartRate = normalize(snapshot.heartRate, lower: 55, upper: 125)
        let activityLevel = normalize(snapshot.stepCount, lower: 1500, upper: 13000)
        let sleepScore = normalize(snapshot.sleepHours, lower: 4.5, upper: 8.5)
        let hrvScore = normalize(snapshot.hrv, lower: 20, upper: 70)
        let stressLevel = 1 - hrvScore * 0.72 - sleepScore * 0.18 + normalizedHeartRate * 0.16
        let clampedStress = clamp(stressLevel)
        let recoveryScore = clamp((sleepScore * 0.58) + (hrvScore * 0.42))
        let tempo = 78 + (normalizedHeartRate * 22) + (activityLevel * 18)
        let noiseLevel = 0.08 + (clampedStress * 0.28)
        let padDepth = 0.28 + (recoveryScore * 0.58)

        let key: String
        if recoveryScore > 0.72 {
            key = "F 大调"
        } else if clampedStress > 0.66 {
            key = "A 小调"
        } else {
            key = "D 小调"
        }

        let texture: String
        if clampedStress > 0.7 {
            texture = "颗粒粗粝"
        } else if activityLevel > 0.72 {
            texture = "磁带摆动"
        } else {
            texture = "柔和噪声"
        }

        let insightText = "这段节律来自今天的真实数据：\(Int(snapshot.stepCount)) 步、平均心率 \(Int(snapshot.heartRate.rounded())) 次/分、近 24 小时睡眠 \(String(format: "%.1f", snapshot.sleepHours)) 小时、HRV \(Int(snapshot.hrv.rounded())) ms。"
        let playbackNote = "心率会推高 BPM，步数会增加切分节奏，睡眠会延长铺底，HRV 偏低时底噪会更明显。"

        return BiometricsProfile(
            tempo: tempo,
            tempoText: "\(Int(tempo.rounded())) BPM",
            key: key,
            texture: texture,
            noiseLevel: noiseLevel,
            padDepth: padDepth,
            activityLevel: activityLevel,
            stressLevel: clampedStress,
            recoveryScore: recoveryScore,
            metrics: [
                BodyMetric(
                    title: "心率",
                    value: "\(Int(snapshot.heartRate.rounded())) 次/分",
                    detail: normalizedHeartRate > 0.62 ? "节拍会被明显推快。" : "节拍会保持偏稳的推进。",
                    icon: "heart.fill",
                    tint: .pink
                ),
                BodyMetric(
                    title: "步数",
                    value: "\(Int(snapshot.stepCount.rounded()))",
                    detail: activityLevel > 0.65 ? "步数高，切分和 hi-hat 会更密。" : "活动量适中，鼓组会更克制。",
                    icon: "figure.walk",
                    tint: .green
                ),
                BodyMetric(
                    title: "睡眠",
                    value: String(format: "%.1f 小时", snapshot.sleepHours),
                    detail: recoveryScore > 0.65 ? "恢复不错，铺底会更圆润。" : "恢复一般，铺底会短一些。",
                    icon: "bed.double.fill",
                    tint: .blue
                ),
                BodyMetric(
                    title: "HRV",
                    value: "\(Int(snapshot.hrv.rounded())) ms",
                    detail: clampedStress > 0.62 ? "HRV 偏低，底噪会更粗糙。" : "HRV 还不错，纹理会更松弛。",
                    icon: "waveform.path.ecg",
                    tint: .orange
                )
            ],
            insightText: insightText,
            playbackNote: playbackNote
        )
    }

    private static func normalize(_ value: Double, lower: Double, upper: Double) -> Double {
        guard upper > lower else {
            return 0
        }

        return clamp((value - lower) / (upper - lower))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
