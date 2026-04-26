//
//  ContentView.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.openURL) private var openURL

    @StateObject private var store = BiometricDataStore()
    @StateObject private var synth = BiometricSynthEngine(profile: .sample)

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    heroSection
                    metricsSection
                    playerSection
                    mappingSection
                    helpSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("共振")
            .navigationBarTitleDisplayMode(.large)
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("身体数据，变成今天的节律。")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)

                    Text(store.statusText)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 16)

                sourcePill
            }

            HStack(spacing: 14) {
                heroStat(title: "节拍", value: store.profile.tempoText)
                heroStat(title: "调式", value: store.profile.key)
                heroStat(title: "纹理", value: store.profile.texture)
            }

            Divider()

            Text(store.detailText)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineSpacing(3)

            if let errorText = store.errorText {
                Label(errorText, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(22)
        .background(panelBackground)
    }

    private var sourcePill: some View {
        Text(store.sourceLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(store.isUsingLiveData ? Color.blue : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(store.isUsingLiveData ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.10))
            )
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("身体数据")

            VStack(spacing: 10) {
                ForEach(store.profile.metrics) { metric in
                    MetricRow(metric: metric)
                }
            }
        }
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("声音输出")

            VStack(alignment: .leading, spacing: 18) {
                WaveformStrip(levels: store.profile.waveformLevels, isPlaying: synth.isPlaying)
                    .frame(height: 56)

                Text(store.profile.playbackNote)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(3)

                HStack(spacing: 8) {
                    parameterPill("鼓组 \(store.profile.grooveLabel)")
                    parameterPill("底噪 \(store.profile.noiseLabel)")
                    parameterPill("铺底 \(store.profile.padLabel)")
                }

                HStack(spacing: 12) {
                    Button {
                        synth.togglePlayback()
                    } label: {
                        Label(synth.isPlaying ? "暂停" : "播放", systemImage: synth.isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())

                    Button {
                        Task {
                            await store.refresh()
                        }
                    } label: {
                        Group {
                            if store.isLoading {
                                ProgressView()
                            } else {
                                Text("刷新")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(store.isLoading)
                }

                if let errorText = synth.errorText {
                    Label(errorText, systemImage: "speaker.slash")
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
            }
            .padding(20)
            .background(panelBackground)
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("映射逻辑")

            VStack(spacing: 0) {
                MappingRow(source: "心率", result: "决定 BPM 和低鼓推进。")
                Divider().padding(.leading, 58)
                MappingRow(source: "步数", result: "决定切分密度和 hi-hat 活跃度。")
                Divider().padding(.leading, 58)
                MappingRow(source: "睡眠", result: "决定铺底长度与和声稳定度。")
                Divider().padding(.leading, 58)
                MappingRow(source: "HRV", result: "决定噪声感和整体张力。")
            }
            .background(panelBackground)
        }
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Apple 健康读取说明")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.guidance, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Color.secondary)
                            .padding(.top, 7)

                        Text(item)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineSpacing(3)
                    }
                }

                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            }
            .padding(20)
            .background(panelBackground)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.primary)
    }

    private func heroStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parameterPill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .systemBackground))
    }
}

private struct MetricRow: View {
    let metric: BodyMetric

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: metric.icon)
                .font(.headline)
                .foregroundStyle(metric.tint)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(metric.tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
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
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                .frame(width: 44, alignment: .leading)

            Text(result)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct WaveformStrip: View {
    let levels: [CGFloat]
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(isPlaying ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .frame(height: currentHeight(base: value, index: index))
                    .animation(.easeInOut(duration: 0.65).delay(Double(index) * 0.018), value: isPlaying)
            }
        }
    }

    private func currentHeight(base: CGFloat, index: Int) -> CGFloat {
        if isPlaying {
            return 14 + (base * 38)
        }

        return index.isMultiple(of: 2) ? 12 : 18
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.16 : 0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

#Preview {
    ContentView()
}
