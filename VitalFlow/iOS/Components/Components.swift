import SwiftUI
import UIKit
import VitalFlowCore

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Cards & materials

struct VFCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.12 : 0.6), .clear],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 12, y: 6)
            }
    }
}

extension View {
    /// Liquid Glass on iOS 26+, translucent material on earlier versions.
    @ViewBuilder
    func vfGlass<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }

    /// App background: subtle brand gradient wash over the system background.
    func vfBackground() -> some View {
        background {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                LinearGradient(colors: [Brand.deepBlue.opacity(0.16), Brand.emerald.opacity(0.08), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Labels

struct SectionHeader: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).foregroundStyle(Brand.emerald) }
            Text(title).font(.headline)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Demo data — not your real health data", systemImage: "theatermasks.fill")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Brand.amber.gradient, in: Capsule())
            .accessibilityLabel(Text("Demo mode is on. Values shown are synthetic and not your health data."))
    }
}

struct ConfidenceBadge: View {
    let confidence: Confidence?
    var body: some View {
        if let c = confidence {
            let text: LocalizedStringKey = c == .high ? "High confidence" : c == .medium ? "Medium confidence" : "Low confidence"
            Text(text)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}

struct NotEnoughDataView: View {
    var missing: [DataRequirement] = []
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not enough data").font(compact ? .subheadline.weight(.semibold) : .headline)
            if !compact, let first = missing.first {
                Text(Self.hint(first)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func hint(_ r: DataRequirement) -> LocalizedStringKey {
        switch r {
        case .hrvToday, .sleepLastNight: return "Wear Apple Watch to sleep tonight to get this score."
        case .hrvBaseline, .restingHeartRateBaseline, .sleepHistory: return "VitalFlow needs at least 4 days of data to learn your baseline."
        case .restingHeartRateToday: return "Resting heart rate for today isn't available yet."
        case .heartRateToday: return "Not enough heart rate readings at rest yet today."
        case .trainingHistory: return "Log workouts for two weeks to see training balance."
        case .recoveryScore: return "Requires today's recovery score."
        }
    }
}

struct ExperimentalNote: View {
    var body: some View {
        Label("Experimental wellness estimate — not a medical measurement or diagnosis.", systemImage: "info.circle")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// Large score with ring; shows "Not enough data" instead of a number when missing.
struct ScoreGauge: View {
    let title: LocalizedStringKey
    let result: ScoreResult
    var color: Color? = nil
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12
    @State private var appear = false

    var body: some View {
        let score = result.score
        let tint = color ?? Brand.scoreColor(score)
        VStack(spacing: 8) {
            ZStack {
                ScoreRing(progress: appear ? Double(score ?? 0) / 100 : 0, color: tint, lineWidth: lineWidth)
                VStack(spacing: 0) {
                    if let score {
                        Text(score, format: .number)
                            .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                            .monospacedDigit()
                    } else {
                        Text("—").font(.system(size: size * 0.28, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: size, height: size)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            if score == nil { Text("Not enough data").font(.caption2).foregroundStyle(.secondary) }
        }
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.1)) { appear = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(score.map { Text(verbatim: "\($0) / 100") } ?? Text("Not enough data"))
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String?
    let unit: LocalizedStringKey
    let systemImage: String
    var tint: Color = Brand.emerald

    var body: some View {
        VFCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage).font(.caption.weight(.medium)).foregroundStyle(tint)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: value ?? "—").font(.title2.weight(.semibold).monospacedDigit())
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting

enum Fmt {
    static func int(_ v: Double?) -> String? { v.map { Int($0.rounded()).formatted() } }
    static func one(_ v: Double?) -> String? { v.map { $0.formatted(.number.precision(.fractionLength(1))) } }
    static func duration(_ seconds: TimeInterval?) -> String? {
        guard let s = seconds else { return nil }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: s)
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}
