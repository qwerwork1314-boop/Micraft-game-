import SwiftUI
import VitalFlowCore

struct Suggestion: Identifiable {
    let id: String
    let icon: String
    let text: LocalizedStringKey
}

/// Rule-based, encouraging suggestions. Never prescriptive, never shame-based.
enum Suggestions {
    static func make(_ a: DailyAssessment, goals: GoalSet) -> [Suggestion] {
        var out: [Suggestion] = []
        if let r = a.recovery.score {
            if r < 34 {
                out.append(.init(id: "rest", icon: "leaf", text: "Your body may appreciate an easier day: gentle movement, good food and an early night."))
            } else if r >= 67 {
                out.append(.init(id: "push", icon: "bolt", text: "You look well recovered. A good day for the workout you enjoy most."))
            }
        }
        if let n = a.metrics.sleep, n.asleep < 0.85 * goals.target(for: .sleepHours) * 3600 {
            out.append(.init(id: "sleep", icon: "moon.stars", text: "Last night was shorter than your goal. A consistent wind-down routine can help tonight."))
        }
        if let s = a.stress.result.score, s >= 60 {
            out.append(.init(id: "breathe", icon: "wind", text: "Stress has been elevated. Try a few minutes of slow breathing or a short walk outside."))
        }
        if (a.metrics.daylightMinutes ?? 0) < 20 {
            out.append(.init(id: "daylight", icon: "sun.max", text: "Some daylight, especially in the morning, supports your sleep rhythm."))
        }
        if (a.metrics.waterML ?? 0) < goals.target(for: .waterML) * 0.5, Calendar.current.component(.hour, from: Date()) >= 14 {
            out.append(.init(id: "water", icon: "drop", text: "A glass of water is an easy win for your garden today."))
        }
        if a.balance == .overreaching {
            out.append(.init(id: "load", icon: "figure.cooldown", text: "Today's load is high relative to recovery. Stretching and rest will help you bounce back."))
        }
        if out.isEmpty {
            out.append(.init(id: "steady", icon: "checkmark.seal", text: "Everything looks steady. Keep doing what's working for you."))
        }
        return out
    }

    static func headline(_ a: DailyAssessment) -> LocalizedStringKey {
        guard let r = a.recovery.score else { return "Keep wearing your watch to unlock insights." }
        switch r {
        case 67...: return "Well recovered"
        case 34..<67: return "Moderately recovered"
        default: return "Take it easy today"
        }
    }

    static func readinessTitle(_ l: TrainingReadinessLevel) -> LocalizedStringKey {
        switch l {
        case .prime: return "Ready to push"
        case .moderate: return "Moderate training"
        case .easy: return "Keep it light"
        case .rest: return "Rest and recover"
        }
    }

    static func balanceTitle(_ b: ActivityRecoveryBalance) -> LocalizedStringKey {
        switch b {
        case .roomToPush: return "Room to push"
        case .balanced: return "Activity and recovery balanced"
        case .overreaching: return "Load is ahead of recovery"
        case .restDay: return "Good rest day"
        }
    }

    static func componentName(_ key: String) -> LocalizedStringKey {
        switch key {
        case "hrv": return "Heart rate variability"
        case "restingHeartRate": return "Resting heart rate"
        case "sleep": return "Sleep quality"
        case "respiratoryRate": return "Respiratory rate"
        case "wristTemperature": return "Wrist temperature"
        case "duration": return "Duration"
        case "efficiency": return "Efficiency"
        case "restorative": return "Deep + REM share"
        case "interruptions": return "Interruptions"
        case "consistency": return "Consistency"
        case "recovery": return "Recovery"
        case "loadBalance": return "Load balance (7d / 28d)"
        case "validHours": return "Hours analysed"
        case "morningCharge": return "Morning charge"
        default: return LocalizedStringKey(key)
        }
    }
}

enum ScoreKind: String, Identifiable {
    case recovery, battery, stress, readiness, sleep
    var id: String { rawValue }
}

struct ScoreDetailView: View {
    let kind: ScoreKind
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let a = model.assessment {
                    let r = result(a)
                    Section {
                        HStack {
                            Spacer()
                            ScoreGauge(title: title, result: r, size: 140, lineWidth: 14)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        if r.score == nil { NotEnoughDataView(missing: r.missing) }
                        ConfidenceBadge(confidence: r.confidence)
                    }
                    if !r.components.isEmpty {
                        Section("What went into it") {
                            ForEach(r.components) { c in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(Suggestions.componentName(c.key)).font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text(verbatim: "\(Int((c.weight * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 8) {
                                        if let v = c.value { Text(verbatim: Fmt.one(v) ?? "").font(.caption.monospacedDigit()) }
                                        if let b = c.baseline {
                                            Text("baseline").font(.caption2).foregroundStyle(.secondary)
                                            Text(verbatim: Fmt.one(b) ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if kind == .recovery {
                                            Image(systemName: c.effect >= 0.3 ? "arrow.up.circle.fill" : c.effect <= -0.3 ? "arrow.down.circle.fill" : "minus.circle")
                                                .foregroundStyle(c.effect >= 0.3 ? Brand.emerald : c.effect <= -0.3 ? Brand.amber : .secondary)
                                        }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    Section {
                        Button {
                            dismiss()
                            model.askCoach(coachQuestion)
                        } label: {
                            Label("Ask Coach about this", systemImage: "sparkles")
                        }
                    }
                    Section("How it works") {
                        Text(explanation).font(.footnote)
                        ExperimentalNote()
                    }
                }
            }
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    var title: LocalizedStringKey {
        switch kind {
        case .recovery: return "Recovery"
        case .battery: return "Body Battery"
        case .stress: return "Stress"
        case .readiness: return "Training readiness"
        case .sleep: return "Sleep score"
        }
    }

    var coachQuestion: String {
        switch kind {
        case .recovery: return String(localized: "Explain my recovery score today.")
        case .battery: return String(localized: "Explain my Body Battery today.")
        case .stress: return String(localized: "Explain my stress today.")
        case .readiness: return String(localized: "Explain my training readiness today.")
        case .sleep: return String(localized: "Explain my sleep score from last night.")
        }
    }

    func result(_ a: DailyAssessment) -> ScoreResult {
        switch kind {
        case .recovery: return a.recovery
        case .battery: return a.bodyBattery.result
        case .stress: return a.stress.result
        case .readiness: return a.readiness.result
        case .sleep: return a.sleepScore
        }
    }

    var explanation: LocalizedStringKey {
        switch kind {
        case .recovery: return "Compares last night's HRV and resting heart rate with your own 28-day baseline, combined with sleep quality and, when available, respiratory rate and wrist temperature. Needs at least 4 days of history."
        case .battery: return "Starts from a morning charge based on recovery and sleep, then drains with time awake, activity and elevated stress, and recharges a little during calm periods."
        case .stress: return "Estimated from heart rate at rest compared with your resting baseline during hours without workouts or much walking, plus daytime HRV when available."
        case .readiness: return "Combines recovery (65%) with the ratio of your last 7 days of training load to the last 28 days (35%)."
        case .sleep: return "Weighted from sleep duration versus your need, efficiency, deep and REM share, interruptions and timing consistency."
        }
    }
}
