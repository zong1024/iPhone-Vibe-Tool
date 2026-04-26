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
    @Published private(set) var sourceLabel = "待同步"
    @Published private(set) var statusText = "等待今天的身体信号。"
    @Published private(set) var detailText = "连接 Apple 健康后，节拍、纹理和铺底会根据你的身体状态自然变化。"
    @Published private(set) var errorText: String?
    @Published private(set) var isLoading = false
    @Published private(set) var guidance: [String] = [
        "第一次进入时允许读取心率、步数、睡眠和 HRV。",
        "如果没有佩戴 Apple Watch，心率和 HRV 可能会暂时缺失。",
        "健康 App 里已有样本后，再次同步会更完整。"
    ]

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
            statusText = "已同步今天的身体信号，更新于 \(timeFormatter.string(from: .now))。"
            detailText = profile.insightText
            errorText = snapshot.missingDataNote
            guidance = [
                "心率和 HRV 往往来自 Apple Watch，未佩戴时可能会缺失。",
                "睡眠通常需要睡眠追踪或 Apple Watch 数据才更完整。",
                "轻点“同步健康”可以在新样本写入后重新生成声场。"
            ]
        case .fallback(let state):
            profile = .sample
            sourceLabel = "待同步"
            statusText = state.title
            detailText = state.detail
            errorText = state.errorText
            guidance = state.guidance
        }
    }
}

enum HealthLoadResult {
    case success(HealthSnapshot)
    case fallback(HealthFallbackState)
}

struct HealthFallbackState {
    let title: String
    let detail: String
    let errorText: String?
    let guidance: [String]
}

struct HealthSnapshot {
    let heartRate: Double?
    let stepCount: Double?
    let sleepHours: Double?
    let hrv: Double?

    var hasAnyData: Bool {
        heartRate != nil || stepCount != nil || sleepHours != nil || hrv != nil
    }

    var missingDataNote: String? {
        let missing = missingMetrics
        guard !missing.isEmpty else {
            return nil
        }

        return "以下数据暂时缺失：\(missing.joined(separator: "、"))。声场已根据目前可用的数据生成。"
    }

    var missingMetrics: [String] {
        var names: [String] = []

        if heartRate == nil {
            names.append("心率")
        }

        if stepCount == nil {
            names.append("步数")
        }

        if sleepHours == nil {
            names.append("睡眠")
        }

        if hrv == nil {
            names.append("HRV")
        }

        return names
    }
}

final class HealthKitManager {
    private let store = HKHealthStore()
    private let calendar = Calendar.current

    func loadSnapshot() async -> HealthLoadResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .fallback(
                HealthFallbackState(
                    title: "当前设备不支持 Apple 健康。",
                    detail: "这台设备暂时无法提供健康数据，因此先使用默认声场。",
                    errorText: "HealthKit 当前不可用。",
                    guidance: [
                        "请在支持 Apple 健康的 iPhone 上使用。",
                        "如果是受限设备，检查系统是否禁止了健康数据。",
                        "恢复可用后，再次同步即可。"
                    ]
                )
            )
        }

        do {
            let readTypes = try requiredReadTypes()
            let authorized = try await requestAuthorization(readTypes: readTypes)

            guard authorized else {
                return .fallback(
                    HealthFallbackState(
                        title: "健康权限尚未完成授权。",
                        detail: "允许读取健康数据后，App 会把今天的身体状态直接转成声场。",
                        errorText: "没有完成 HealthKit 授权。",
                        guidance: [
                            "重新点一次“同步健康”触发授权。",
                            "如果系统不再弹窗，请到 健康 App -> 资料 -> App 与服务 里开启本 App。",
                            "至少允许步数或心率后，就能开始生成个性化声场。"
                        ]
                    )
                )
            }

            async let heartRate = mostUsefulHeartRate()
            async let stepCount = stepCountToday()
            async let sleepHours = recentSleepHours()
            async let hrv = recentAverageHRV()

            let snapshot = await HealthSnapshot(
                heartRate: heartRate,
                stepCount: stepCount,
                sleepHours: sleepHours,
                hrv: hrv
            )

            guard snapshot.hasAnyData else {
                return .fallback(
                    HealthFallbackState(
                        title: "已连上 Apple 健康，但还没有读到可用样本。",
                        detail: "健康数据库里暂时还没有今天可用的样本，声场会先保持默认状态。",
                        errorText: "未获取到心率、步数、睡眠或 HRV 样本。",
                        guidance: [
                            "步数通常最容易拿到，稍微活动后再同步一次。",
                            "心率、HRV 和睡眠更依赖 Apple Watch 或其他健康来源。",
                            "如果你刚刚授权，等几秒后再试一次。"
                        ]
                    )
                )
            }

            return .success(snapshot)
        } catch let error as HKError {
            return .fallback(fallbackState(for: error))
        } catch {
            return .fallback(
                HealthFallbackState(
                    title: "读取 Apple 健康时出了点问题。",
                    detail: "我先保留默认声场，避免页面完全中断。",
                    errorText: "读取 Apple 健康失败：\(error.localizedDescription)",
                    guidance: [
                        "确认手机已解锁后再同步。",
                        "在健康 App 中检查这个 App 的读取权限。",
                        "如果问题持续，把这里的报错文字发给我，我继续对着修。"
                    ]
                )
            )
        }
    }

    private func requiredReadTypes() throws -> Set<HKObjectType> {
        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let restingHeartRate = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount),
            let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            throw HealthKitManagerError.unsupportedTypes
        }

        return [heartRate, restingHeartRate, stepCount, hrv, sleep]
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

    private func mostUsefulHeartRate() async -> Double? {
        if let liveHeartRate = await averageHeartRate(inLastHours: 12) {
            return liveHeartRate
        }

        if let restingHeartRate = await averageQuantityValue(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: calendar.date(byAdding: .day, value: -7, to: .now),
            end: .now,
            options: .discreteAverage
        ) {
            return restingHeartRate
        }

        return await mostRecentQuantityValue(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: calendar.date(byAdding: .day, value: -3, to: .now),
            end: .now
        )
    }

    private func averageHeartRate(inLastHours hours: Int) async -> Double? {
        await averageQuantityValue(
            identifier: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: calendar.date(byAdding: .hour, value: -hours, to: .now),
            end: .now,
            options: .discreteAverage
        )
    }

    private func stepCountToday() async -> Double? {
        await averageQuantityValue(
            identifier: .stepCount,
            unit: .count(),
            start: calendar.startOfDay(for: .now),
            end: .now,
            options: .cumulativeSum
        )
    }

    private func recentAverageHRV() async -> Double? {
        await averageQuantityValue(
            identifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            start: calendar.date(byAdding: .day, value: -7, to: .now),
            end: .now,
            options: .discreteAverage
        )
    }

    private func recentSleepHours() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let start = calendar.date(byAdding: .day, value: -3, to: .now) ?? .now.addingTimeInterval(-259200)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sort]
                ) { _, results, error in
                    if let hkError = Self.normalize(error) {
                        if hkError.code == .errorNoData {
                            continuation.resume(returning: [])
                        } else {
                            continuation.resume(throwing: hkError)
                        }
                        return
                    }

                    continuation.resume(returning: results as? [HKCategorySample] ?? [])
                }

                store.execute(query)
            }

            let cutoff = calendar.date(byAdding: .hour, value: -36, to: .now) ?? .now.addingTimeInterval(-129600)
            let totalSeconds = samples.reduce(0.0) { partial, sample in
                guard Self.isAsleep(sample) else {
                    return partial
                }

                let startDate = max(sample.startDate, cutoff)
                let endDate = min(sample.endDate, .now)

                guard endDate > startDate else {
                    return partial
                }

                return partial + endDate.timeIntervalSince(startDate)
            }

            guard totalSeconds > 0 else {
                return nil
            }

            return totalSeconds / 3600
        } catch {
            return nil
        }
    }

    private func averageQuantityValue(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date?,
        end: Date,
        options: HKStatisticsOptions
    ) async -> Double? {
        guard
            let start,
            let type = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: type,
                    quantitySamplePredicate: predicate,
                    options: options
                ) { _, result, error in
                    if let hkError = Self.normalize(error) {
                        if hkError.code == .errorNoData {
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(throwing: hkError)
                        }
                        return
                    }

                    let quantity: HKQuantity?
                    if options.contains(.cumulativeSum) {
                        quantity = result?.sumQuantity()
                    } else {
                        quantity = result?.averageQuantity()
                    }

                    continuation.resume(returning: quantity?.doubleValue(for: unit))
                }

                store.execute(query)
            }
        } catch {
            return nil
        }
    }

    private func mostRecentQuantityValue(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date?,
        end: Date
    ) async -> Double? {
        guard
            let start,
            let type = HKObjectType.quantityType(forIdentifier: identifier)
        else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [sort]
                ) { _, results, error in
                    if let hkError = Self.normalize(error) {
                        if hkError.code == .errorNoData {
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(throwing: hkError)
                        }
                        return
                    }

                    let sample = results?.first as? HKQuantitySample
                    continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
                }

                store.execute(query)
            }
        } catch {
            return nil
        }
    }

    private func fallbackState(for error: HKError) -> HealthFallbackState {
        switch error.code {
        case .errorDatabaseInaccessible:
            return HealthFallbackState(
                title: "手机锁屏时无法读取健康数据。",
                detail: "Apple 官方文档说明，设备锁定时 HealthKit 数据库会暂时不可访问。",
                errorText: "健康数据库当前不可访问，请解锁手机后重试。",
                guidance: [
                    "先解锁手机，再回到 App 点“同步健康”。",
                    "保持 App 在前台重新读取一次。",
                    "如果是刚安装的新 App，先完成一次权限授权。"
                ]
            )
        case .errorHealthDataRestricted:
            return HealthFallbackState(
                title: "这台设备限制了 Apple 健康访问。",
                detail: "可能是企业设备策略或系统限制导致，健康同步暂时不可用。",
                errorText: "HealthKit 被系统限制。",
                guidance: [
                    "检查是否是公司设备或受管设备。",
                    "到 设置 -> 屏幕使用时间 或 MDM 限制中确认健康权限。",
                    "若无法解除限制，App 会继续使用默认声场。"
                ]
            )
        case .errorHealthDataUnavailable:
            return HealthFallbackState(
                title: "当前环境拿不到 Apple 健康。",
                detail: "Apple 文档说明，不支持 HealthKit 的设备会直接返回不可用。",
                errorText: "HealthKit 在当前设备不可用。",
                guidance: [
                    "请在支持 Apple 健康的 iPhone 上使用。",
                    "iPad 或受限环境里可能无法同步。",
                    "切到真机后重新授权。"
                ]
            )
        case .errorUserCanceled:
            return HealthFallbackState(
                title: "你取消了健康权限授权。",
                detail: "在权限重新开启前，App 会先保持默认声场。",
                errorText: "HealthKit 授权已取消。",
                guidance: [
                    "点“同步健康”再触发一次授权。",
                    "或到 健康 App -> 资料 -> App 与服务 手动开启权限。",
                    "至少允许步数后，这页就能开始用真实数据。"
                ]
            )
        default:
            return HealthFallbackState(
                title: "读取 Apple 健康时出了点问题。",
                detail: "先保留默认声场，避免页面完全不可用。",
                errorText: "HealthKit 错误：\(error.localizedDescription)",
                guidance: [
                    "确认手机已解锁。",
                    "确认健康 App 里已经存在样本。",
                    "如果仍失败，把这条错误发给我，我继续修。"
                ]
            )
        }
    }

    private static func normalize(_ error: Error?) -> HKError? {
        guard let error else {
            return nil
        }

        return error as? HKError
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
        tempo: 88,
        tempoText: "88 BPM",
        key: "D 小调",
        texture: "柔和颗粒",
        noiseLevel: 0.16,
        padDepth: 0.62,
        activityLevel: 0.56,
        stressLevel: 0.44,
        recoveryScore: 0.58,
        metrics: [
            BodyMetric(
                title: "心率",
                value: "96 次/分",
                detail: "当前节拍略快，鼓点会更紧一些。",
                icon: "heart.fill",
                tint: .pink
            ),
            BodyMetric(
                title: "步数",
                value: "8420",
                detail: "活动量不错，切分会更活跃。",
                icon: "figure.walk",
                tint: .green
            ),
            BodyMetric(
                title: "睡眠",
                value: "7.1 小时",
                detail: "恢复中，铺底会更平稳。",
                icon: "bed.double.fill",
                tint: .indigo
            ),
            BodyMetric(
                title: "HRV",
                value: "34 ms",
                detail: "略有压力，底噪会轻微抬高。",
                icon: "waveform.path.ecg",
                tint: .orange
            )
        ],
        insightText: "在健康数据完成同步前，App 会先用一组温和的默认声场开始播放。",
        playbackNote: "节拍以 16 步循环推进，并根据活动量、恢复度和 HRV 调整鼓组密度与纹理。"
    )

    static func live(_ snapshot: HealthSnapshot) -> BiometricsProfile {
        let heartRate = snapshot.heartRate ?? 74
        let stepCount = snapshot.stepCount ?? 4200
        let sleepHours = snapshot.sleepHours ?? 6.6
        let hrv = snapshot.hrv ?? 38

        let normalizedHeartRate = normalize(heartRate, lower: 55, upper: 125)
        let activityLevel = normalize(stepCount, lower: 1500, upper: 13000)
        let sleepScore = normalize(sleepHours, lower: 4.5, upper: 8.5)
        let hrvScore = normalize(hrv, lower: 20, upper: 70)
        let stressLevel = 1 - hrvScore * 0.72 - sleepScore * 0.18 + normalizedHeartRate * 0.16
        let clampedStress = clamp(stressLevel)
        let recoveryScore = clamp((sleepScore * 0.58) + (hrvScore * 0.42))
        let tempo = 78 + (normalizedHeartRate * 22) + (activityLevel * 18)
        let noiseLevel = 0.08 + (clampedStress * 0.24)
        let padDepth = 0.32 + (recoveryScore * 0.52)

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
            texture = "紧绷颗粒"
        } else if activityLevel > 0.72 {
            texture = "轻摆磁带"
        } else {
            texture = "柔和空气感"
        }

        let insightText = [
            snapshot.stepCount.map { "步数 \(Int($0.rounded()))" },
            snapshot.heartRate.map { "心率 \(Int($0.rounded())) 次/分" },
            snapshot.sleepHours.map { "睡眠 \(String(format: "%.1f", $0)) 小时" },
            snapshot.hrv.map { "HRV \(Int($0.rounded())) ms" }
        ]
        .compactMap { $0 }
        .joined(separator: "，")

        let summaryText = insightText.isEmpty ? "已连接 Apple 健康。" : "当前节律来自真实数据：\(insightText)。"

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
                    value: snapshot.heartRate.map { "\(Int($0.rounded())) 次/分" } ?? "未获取",
                    detail: snapshot.heartRate == nil ? "没有读到心率，先用默认节拍估算。" : (normalizedHeartRate > 0.62 ? "节拍会被明显推快。" : "节拍会保持偏稳推进。"),
                    icon: "heart.fill",
                    tint: .pink
                ),
                BodyMetric(
                    title: "步数",
                    value: snapshot.stepCount.map { "\(Int($0.rounded()))" } ?? "未获取",
                    detail: snapshot.stepCount == nil ? "没有读到步数，鼓组密度保持中性。" : (activityLevel > 0.65 ? "切分和 hi-hat 会更密。" : "鼓组会更克制一些。"),
                    icon: "figure.walk",
                    tint: .green
                ),
                BodyMetric(
                    title: "睡眠",
                    value: snapshot.sleepHours.map { String(format: "%.1f 小时", $0) } ?? "未获取",
                    detail: snapshot.sleepHours == nil ? "睡眠缺失时，铺底按中性恢复度处理。" : (recoveryScore > 0.65 ? "铺底会更圆润更长。" : "铺底会更短一些。"),
                    icon: "bed.double.fill",
                    tint: .indigo
                ),
                BodyMetric(
                    title: "HRV",
                    value: snapshot.hrv.map { "\(Int($0.rounded())) ms" } ?? "未获取",
                    detail: snapshot.hrv == nil ? "没拿到 HRV，底噪会保持适中。" : (clampedStress > 0.62 ? "底噪会更明显。" : "纹理会更松弛。"),
                    icon: "waveform.path.ecg",
                    tint: .orange
                )
            ],
            insightText: summaryText,
            playbackNote: "心率推高 BPM，步数增加切分，睡眠决定铺底长度，HRV 偏低时纹理会更紧。"
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
