//
//  ContentView.swift
//  iPhone Vibe Tool
//
//  Created by 宗睿 on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    @State private var isPlaying = true

    private let profile = SynthProfile.sample
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            background

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard
                    metricsSection
                    synthSection
                    mappingSection
                    resonanceSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.16),
                    Color(red: 0.08, green: 0.14, blue: 0.23),
                    Color(red: 0.18, green: 0.11, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 30)
                .offset(x: 130, y: -260)

            Circle()
                .fill(Color.orange.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 24)
                .offset(x: -140, y: 220)
        }
        .ignoresSafeArea()
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Biometric Synth")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(Color.white)

                    Text("生物节律合成器")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.78))

                    Text("Your phone becomes a resonance box for your body, turning fatigue, pulse, and recovery into a midnight Lo-Fi score.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isPlaying.toggle()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.mint, Color.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color.cyan.opacity(0.45), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                CapsuleTag(title: isPlaying ? "Live Session" : "Paused", tint: .mint)
                CapsuleTag(title: "Recovery Bias 68%", tint: .orange)
                CapsuleTag(title: "Lo-Fi Output", tint: .pink)
            }

            LoFiWaveformView(isPlaying: isPlaying)
                .frame(height: 92)

            HStack {
                statLine(value: profile.tempo, label: "tempo")
                Spacer()
                statLine(value: profile.key, label: "key")
                Spacer()
                statLine(value: profile.texture, label: "texture")
            }
        }
        .padding(22)
        .background(cardBackground)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Body Signals")

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(profile.metrics) { metric in
                    MetricCard(metric: metric)
                }
            }
        }
    }

    private var synthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Today's Mix")

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("April 27 Session")
                            .font(.headline)
                            .foregroundStyle(Color.white)

                        Text("Fatigue stayed elevated after noon, so the engine pulled the groove downward into a softer, dustier pocket.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("Lo-Fi")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.92))
                        )
                }

                HStack(spacing: 12) {
                    MixDial(title: "Drift", value: "42%")
                    MixDial(title: "Warmth", value: "81%")
                    MixDial(title: "Focus", value: "53%")
                }

                VStack(spacing: 10) {
                    InsightRow(label: "Pulse acceleration", detail: "Pushes kick pattern into tighter 1/8 note motion")
                    InsightRow(label: "Lower HRV", detail: "Adds granular hiss and narrows stereo width")
                    InsightRow(label: "Deep sleep rebound", detail: "Lets pads bloom longer with slower filter sweep")
                }
            }
            .padding(20)
            .background(cardBackground)
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Body -> Sound Map")

            VStack(spacing: 12) {
                MappingRow(source: "Heart Rate", target: "Tempo", result: "96 BPM when pulse spikes")
                MappingRow(source: "Steps", target: "Groove Density", result: "More motion, busier hats")
                MappingRow(source: "Sleep Depth", target: "Pad Length", result: "Recovered days get longer tails")
                MappingRow(source: "Stress Load", target: "Noise Texture", result: "Pressure adds grit and tape dust")
            }
            .padding(18)
            .background(cardBackground)
        }
    }

    private var resonanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Resonance Note")

            Text("Your phone stops acting like a black hole for attention and starts listening back. The soundtrack is not chosen for you; it is coaxed out of you.")
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineSpacing(4)
                .padding(20)
                .background(cardBackground)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(2)
            .foregroundStyle(Color.white.opacity(0.64))
    }

    private func statLine(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.54))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct CapsuleTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(tint.opacity(0.45), lineWidth: 1)
                    )
            )
    }
}

private struct MetricCard: View {
    let metric: HealthMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: metric.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(metric.tint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(metric.tint.opacity(0.18))
                    )

                Spacer()

                Text(metric.trend)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.white)

                Text(metric.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.78))

                Text(metric.impact)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct MixDial: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 8)

                Circle()
                    .trim(from: 0.0, to: 0.72)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 86, height: 86)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InsightRow: View {
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.mint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

private struct MappingRow: View {
    let source: String
    let target: String
    let result: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text("Input")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(target)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text(result)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
    }
}

private struct LoFiWaveformView: View {
    let isPlaying: Bool

    private let bars: [CGFloat] = [0.34, 0.56, 0.42, 0.8, 0.62, 0.48, 0.9, 0.52, 0.68, 0.4, 0.72, 0.58, 0.84, 0.38, 0.66]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.9), Color.mint.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(for: value, index: index))
                    .animation(
                        .easeInOut(duration: 0.9).delay(Double(index) * 0.03),
                        value: isPlaying
                    )
            }
        }
        .padding(.vertical, 8)
    }

    private func barHeight(for value: CGFloat, index: Int) -> CGFloat {
        let playingHeight = 20 + (value * 56)
        let pausedHeight = index.isMultiple(of: 3) ? 34 : 18
        return isPlaying ? playingHeight : pausedHeight
    }
}

private struct HealthMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let trend: String
    let impact: String
    let icon: String
    let tint: Color
}

private struct SynthProfile {
    let tempo: String
    let key: String
    let texture: String
    let metrics: [HealthMetric]

    static let sample = SynthProfile(
        tempo: "88 BPM",
        key: "D Minor",
        texture: "Dusty Tape",
        metrics: [
            HealthMetric(
                title: "Heart Rate",
                value: "96 bpm",
                trend: "Restless",
                impact: "Faster pulse tightens the groove.",
                icon: "heart.fill",
                tint: .pink
            ),
            HealthMetric(
                title: "Steps",
                value: "8,420",
                trend: "Active",
                impact: "Movement adds brighter hats.",
                icon: "figure.walk",
                tint: .mint
            ),
            HealthMetric(
                title: "Sleep Depth",
                value: "71%",
                trend: "Recovering",
                impact: "Deeper rest lengthens pad tails.",
                icon: "bed.double.fill",
                tint: .cyan
            ),
            HealthMetric(
                title: "Stress Load",
                value: "High",
                trend: "Textured",
                impact: "Pressure introduces grain and hiss.",
                icon: "waveform.path.ecg",
                tint: .orange
            )
        ]
    )
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
