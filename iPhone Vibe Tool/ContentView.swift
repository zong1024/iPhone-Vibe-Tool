//
//  ContentView.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = BiometricDataStore()
    @StateObject private var synth = BiometricSynthEngine(profile: .sample)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    metricsSection
                    playerSection
                    mappingSection
                    footerSection
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("生物节律合成器")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await store.loadIfNeeded()
            synth.updateProfile(store.profile)
        }
        .onChange(of: store.profile) { _, newProfile in
            synth.updateProfile(newProfile)
        }
        .onDisappear {
            synth.stop()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日身体节律")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)

                    Text(store.statusText)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 12)

                sourceBadge
            }

            Divider()

            HStack(spacing: 24) {
                summaryItem(title: "节拍", value: store.profile.tempoText)
                summaryItem(title: "调式", value: store.profile.key)
                summaryItem(title: "纹理", value: store.profile.texture)
            }

            if let errorText = store.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var sourceBadge: some View {
        Text(store.sourceLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(store.isUsingLiveData ? Color.green : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(store.isUsingLiveData ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12))
            )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("今日身体数据")

            VStack(spacing: 12) {
                ForEach(store.profile.metrics) { metric in
                    MetricRow(metric: metric)
                }
            }
        }
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("声音输出")

            VStack(alignment: .leading, spacing: 16) {
                Text(store.profile.playbackNote)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)

                WaveformStrip(levels: store.profile.waveformLevels, isPlaying: synth.isPlaying)
                    .frame(height: 60)

                HStack(spacing: 12) {
                    controlChip(title: "鼓组 \(store.profile.grooveLabel)")
                    controlChip(title: "底噪 \(store.profile.noiseLabel)")
                    controlChip(title: "铺底 \(store.profile.padLabel)")
                }

                HStack(spacing: 12) {
                    Button {
                        synth.togglePlayback()
                    } label: {
                        HStack {
                            Image(systemName: synth.isPlaying ? "pause.fill" : "play.fill")
                            Text(synth.isPlaying ? "暂停合成器" : "播放今日节律")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.10, green: 0.44, blue: 0.39))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await store.refresh()
                        }
                    } label: {
                        Group {
                            if store.isLoading {
                                ProgressView()
                                    .tint(Color(red: 0.10, green: 0.44, blue: 0.39))
                            } else {
                                Text("刷新数据")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.10, green: 0.44, blue: 0.39))
                        .frame(width: 112)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.10, green: 0.44, blue: 0.39).opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading)
                }

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
                MappingRow(source: "心率", result: "推高 BPM，并让低鼓更密。")
                MappingRow(source: "步数", result: "增加 hi-hat 和切分节奏。")
                MappingRow(source: "睡眠", result: "决定铺底长度和和声稳定度。")
                MappingRow(source: "HRV", result: "控制颗粒底噪与张力。")
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("说明")

            VStack(alignment: .leading, spacing: 8) {
                Text(store.detailText)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(3)

                Text("提示：HealthKit 需要在真机上授权后才能读取心率、步数、睡眠和 HRV。模拟器一般只会显示演示数据。")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .lineSpacing(3)
            }
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
    let levels: [CGFloat]
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(isPlaying ? Color(red: 0.10, green: 0.44, blue: 0.39) : Color.gray.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .frame(height: currentHeight(base: value, index: index))
                    .animation(.easeInOut(duration: 0.7).delay(Double(index) * 0.018), value: isPlaying)
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

#Preview {
    ContentView()
}
