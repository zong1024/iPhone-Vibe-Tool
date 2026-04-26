//
//  ContentView.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    private let profile = BiometricsProfile.sample

    @StateObject private var synth = BiometricSynthEngine(profile: .sample)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    metricsSection
                    playerSection
                    mappingSection
                    footerNote
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("生物节律合成器")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            synth.stop()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Biometric Synth")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)

                    Text("把当天的身体状态转成一段可听的低保真节律。")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 12)

                statusBadge
            }

            Divider()

            HStack(spacing: 24) {
                summaryItem(title: "节拍", value: profile.tempoText)
                summaryItem(title: "调式", value: profile.key)
                summaryItem(title: "质感", value: profile.texture)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var statusBadge: some View {
        Text(synth.isPlaying ? "播放中" : "未播放")
            .font(.caption.weight(.semibold))
            .foregroundStyle(synth.isPlaying ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(synth.isPlaying ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12))
            )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("今日身体数据")

            VStack(spacing: 12) {
                ForEach(profile.metrics) { metric in
                    MetricRow(metric: metric)
                }
            }
        }
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("声音输出")

            VStack(alignment: .leading, spacing: 16) {
                Text("当前是一个简化版示例音轨：根据心率驱动节拍，根据压力提升底噪，根据睡眠恢复度拉长铺底。")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)

                WaveformStrip(isPlaying: synth.isPlaying)
                    .frame(height: 56)

                HStack(spacing: 12) {
                    controlChip(title: "鼓点 \(profile.tempoText)")
                    controlChip(title: "底噪 \(profile.noiseLabel)")
                    controlChip(title: "铺底 \(profile.padLabel)")
                }

                Button {
                    synth.togglePlayback()
                } label: {
                    HStack {
                        Image(systemName: synth.isPlaying ? "pause.fill" : "play.fill")
                        Text(synth.isPlaying ? "暂停声音" : "播放今日节律")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.10, green: 0.44, blue: 0.39))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                if let errorText = synth.errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
            }
            .padding(20)
            .background(cardBackground)
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("映射关系")

            VStack(spacing: 10) {
                MappingRow(source: "心率", result: "节拍更紧，鼓点更密")
                MappingRow(source: "步数", result: "高频打击更活跃")
                MappingRow(source: "睡眠恢复", result: "铺底更长、更稳")
                MappingRow(source: "压力负荷", result: "颗粒底噪更明显")
            }
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("说明")

            Text("现在展示的是示例数据和本地生成的基础音色。下一步如果接入 HealthKit，就可以把心率、步数和睡眠数据实时映射到声音参数。")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineSpacing(3)
                .padding(16)
                .background(cardBackground)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Color.primary)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.primary)
        }
    }

    private func controlChip(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .systemBackground))
            .shadow(color: Color.black.opacity(0.04), radius: 14, y: 6)
    }
}

private struct MetricRow: View {
    let metric: BodyMetric

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: metric.icon)
                .font(.headline)
                .foregroundStyle(metric.tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(metric.tint.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metric.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)

                    Spacer()

                    Text(metric.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }

                Text(metric.detail)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }
}

private struct MappingRow: View {
    let source: String
    let result: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(source)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 64, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondary)
                .padding(.top, 3)

            Text(result)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }
}

private struct WaveformStrip: View {
    let isPlaying: Bool

    private let bars: [CGFloat] = [0.18, 0.34, 0.52, 0.26, 0.48, 0.72, 0.39, 0.61, 0.29, 0.57, 0.41, 0.66]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(isPlaying ? Color(red: 0.10, green: 0.44, blue: 0.39) : Color.gray.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: currentHeight(base: value, index: index))
                    .animation(.easeInOut(duration: 0.8).delay(Double(index) * 0.02), value: isPlaying)
            }
        }
        .padding(.vertical, 2)
    }

    private func currentHeight(base: CGFloat, index: Int) -> CGFloat {
        if isPlaying {
            return 14 + (base * 44)
        }

        return index.isMultiple(of: 2) ? 12 : 20
    }
}

struct BodyMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
}

struct BiometricsProfile {
    let tempo: Double
    let tempoText: String
    let key: String
    let texture: String
    let noiseLevel: Double
    let padDepth: Double
    let metrics: [BodyMetric]

    var noiseLabel: String {
        noiseLevel > 0.22 ? "偏强" : "偏轻"
    }

    var padLabel: String {
        padDepth > 0.70 ? "拉长" : "适中"
    }

    static let sample = BiometricsProfile(
        tempo: 88,
        tempoText: "88 BPM",
        key: "D 小调",
        texture: "磁带颗粒",
        noiseLevel: 0.26,
        padDepth: 0.78,
        metrics: [
            BodyMetric(
                title: "心率",
                value: "96 次/分",
                detail: "偏快，节拍会更紧一些。",
                icon: "heart.fill",
                tint: .pink
            ),
            BodyMetric(
                title: "步数",
                value: "8420",
                detail: "活动量不错，打击声会更活跃。",
                icon: "figure.walk",
                tint: .green
            ),
            BodyMetric(
                title: "睡眠恢复",
                value: "71%",
                detail: "恢复中，铺底会更长更稳。",
                icon: "bed.double.fill",
                tint: .blue
            ),
            BodyMetric(
                title: "压力负荷",
                value: "较高",
                detail: "会抬高底噪和颗粒感。",
                icon: "waveform.path.ecg",
                tint: .orange
            )
        ]
    )
}

#Preview {
    ContentView()
}
