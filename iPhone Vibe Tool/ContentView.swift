//
//  ContentView.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL

    @StateObject private var store = BiometricDataStore()
    @StateObject private var synth = BiometricSynthEngine(profile: .sample)

    private let brandBlue = Color(red: 0.33, green: 0.60, blue: 0.98)
    private let brandWarm = Color(red: 0.95, green: 0.70, blue: 0.45)

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        heroSection
                        signalSection
                        playerSection
                        soundMapSection
                        healthSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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

    private var backgroundLayer: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            Circle()
                .fill(brandBlue.opacity(0.10))
                .frame(width: 320, height: 320)
                .offset(x: 150, y: -250)

            Circle()
                .fill(brandWarm.opacity(0.10))
                .frame(width: 280, height: 280)
                .offset(x: -160, y: 300)

            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 220, height: 220)
                .offset(x: 120, y: 160)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sympathetic Vibration")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.primary)

                    Text("让身体状态，轻轻推动今天的声场。")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 12)

                sourcePill
            }

            Text(store.statusText)
                .font(.headline)
                .foregroundStyle(Color.primary)

            Text(store.detailText)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineSpacing(3)

            HStack(spacing: 12) {
                heroStat(title: "Tempo", value: store.profile.tempoText)
                heroStat(title: "Key", value: store.profile.key)
                heroStat(title: "Texture", value: store.profile.texture)
            }

            if let errorText = store.errorText {
                Label(errorText, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(22)
        .glassCard(cornerRadius: 30)
    }

    private var sourcePill: some View {
        Text(store.sourceLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(store.isUsingLiveData ? brandBlue : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(store.isUsingLiveData ? brandBlue.opacity(0.12) : Color.white.opacity(0.55))
            )
    }

    private var signalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Signals")

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(store.profile.metrics) { metric in
                    SignalCard(metric: metric)
                }
            }
        }
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Listening")

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Today’s field")
                        .font(.headline)
                        .foregroundStyle(Color.primary)

                    Spacer()

                    HStack(spacing: 8) {
                        propertyPill("鼓组 \(store.profile.grooveLabel)")
                        propertyPill("铺底 \(store.profile.padLabel)")
                    }
                }

                WaveformStrip(levels: store.profile.waveformLevels, isPlaying: synth.isPlaying, tint: brandBlue)
                    .frame(height: 58)

                Text(store.profile.playbackNote)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineSpacing(3)

                HStack(spacing: 12) {
                    Button {
                        synth.togglePlayback()
                    } label: {
                        Label(synth.isPlaying ? "暂停声场" : "播放声场", systemImage: synth.isPlaying ? "pause.fill" : "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(fill: brandBlue))

                    Button {
                        Task {
                            await store.refresh()
                        }
                    } label: {
                        Group {
                            if store.isLoading {
                                ProgressView()
                                    .tint(brandBlue)
                            } else {
                                Label("同步健康", systemImage: "arrow.clockwise")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: brandBlue))
                    .disabled(store.isLoading)
                }

                if let errorText = synth.errorText {
                    Label(errorText, systemImage: "speaker.slash")
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
            }
            .padding(22)
            .glassCard(cornerRadius: 28)
        }
    }

    private var soundMapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Sound Map")

            VStack(spacing: 0) {
                MappingRow(source: "心率", result: "推动 BPM 和鼓点推进。")
                Divider().padding(.leading, 68)
                MappingRow(source: "步数", result: "增加切分与高频律动。")
                Divider().padding(.leading, 68)
                MappingRow(source: "睡眠", result: "延长铺底并让和声更稳定。")
                Divider().padding(.leading, 68)
                MappingRow(source: "HRV", result: "改变颗粒感与整体张力。")
            }
            .glassCard(cornerRadius: 26)
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Apple 健康")

            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.guidance, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(brandBlue.opacity(0.95))
                            .frame(width: 6, height: 6)
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
                .foregroundStyle(brandBlue)
            }
            .padding(22)
            .glassCard(cornerRadius: 26)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
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
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func propertyPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.55))
            )
    }
}

private struct SignalCard: View {
    let metric: BodyMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: metric.icon)
                    .font(.headline)
                    .foregroundStyle(metric.tint)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(metric.tint.opacity(0.12))
                    )

                Spacer()
            }

            Text(metric.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.secondary)

            Text(metric.value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text(metric.detail)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassCard(cornerRadius: 24)
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
                .frame(width: 56, alignment: .leading)

            Text(result)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineSpacing(2)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct WaveformStrip: View {
    let levels: [CGFloat]
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(isPlaying ? tint : Color.secondary.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: currentHeight(base: value, index: index))
                    .animation(.easeInOut(duration: 0.65).delay(Double(index) * 0.02), value: isPlaying)
            }
        }
    }

    private func currentHeight(base: CGFloat, index: Int) -> CGFloat {
        if isPlaying {
            return 14 + (base * 40)
        }

        return index.isMultiple(of: 2) ? 12 : 18
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.68 : 0.56))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )
        )
    }
}

#Preview {
    ContentView()
}
