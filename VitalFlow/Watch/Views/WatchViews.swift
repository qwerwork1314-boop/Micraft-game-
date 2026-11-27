import SwiftUI
import VitalFlowCore

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.state != .idle {
            LiveWorkoutView()
        } else {
            NavigationStack {
                TabView {
                    SummaryPage()
                    HeartPage()
                    ActivityPage()
                    HydrationPage()
                    WorkoutPickerPage()
                }
                .tabViewStyle(.verticalPage)
            }
        }
    }
}

struct WatchGauge: View {
    let title: LocalizedStringKey
    let value: Int?
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                ScoreRing(progress: Double(value ?? 0) / 100, color: color, lineWidth: 6)
                Text(verbatim: value.map(String.init) ?? "—").font(.system(.title3, design: .rounded).weight(.semibold))
            }
            .frame(width: 54, height: 54)
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(value.map { Text(verbatim: "\($0)") } ?? Text("Not enough data"))
    }
}

struct SummaryPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        let s = model.snapshot
        VStack(spacing: 8) {
            if s.isDemo { Text("Demo data").font(.caption2.weight(.semibold)).foregroundStyle(Brand.amber) }
            HStack(spacing: 6) {
                WatchGauge(title: "Recovery", value: s.recovery, color: Brand.scoreColor(s.recovery))
                WatchGauge(title: "Battery", value: s.bodyBattery, color: Brand.ocean)
                WatchGauge(title: "Stress", value: s.stress, color: Brand.stressColor(s.stress))
            }
            if s.recovery == nil {
                Text("Not enough data").font(.footnote)
                Text("Open VitalFlow on iPhone to sync.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if s.generatedAt > .distantPast {
                Text(String(format: String(localized: "Updated %@"), s.generatedAt.formatted(date: .omitted, time: .shortened)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(Brand.night.opacity(0.6), for: .tabView)
        .navigationTitle(Text("VitalFlow"))
    }
}

struct HeartPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Heart rate", systemImage: "heart.fill").foregroundStyle(Brand.coral).font(.footnote)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: model.latestHR.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("bpm").font(.footnote).foregroundStyle(.secondary)
            }
            if let d = model.latestHRDate {
                Text(d, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Resting").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: model.snapshot.restingHR.map { "\($0) bpm" } ?? "—").font(.footnote.monospacedDigit())
            }
        }
        .containerBackground(Brand.coral.opacity(0.25).gradient, for: .tabView)
    }
}

struct ActivityPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity").font(.footnote).foregroundStyle(Brand.emerald)
            bar("Move", model.activeEnergy, Double(s.energyGoal), "kcal", Brand.coral)
            bar("Exercise", model.exerciseMinutes, Double(s.exerciseGoal), "min", Brand.emerald)
            bar("Steps", model.steps, Double(s.stepGoal), "", Brand.ocean)
        }
        .containerBackground(Brand.emerald.opacity(0.2).gradient, for: .tabView)
    }

    func bar(_ t: LocalizedStringKey, _ v: Double?, _ goal: Double, _ unit: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(t).font(.caption2)
                Spacer()
                Text(verbatim: "\(Int(v ?? 0))/\(Int(goal)) \(unit)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, (v ?? 0) / max(goal, 1))).tint(c)
        }
    }
}

struct HydrationPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ScoreRing(progress: model.waterML / Double(max(model.snapshot.waterGoal, 1)), color: Brand.ocean, lineWidth: 8)
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill").foregroundStyle(Brand.ocean)
                    Text(verbatim: "\(Int(model.waterML))").font(.title3.weight(.semibold).monospacedDigit())
                    Text("ml").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, height: 90)
            HStack {
                Button("+250") { Task { await model.logWater(250) } }
                Button("+500") { Task { await model.logWater(500) } }
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.ocean)
        }
        .containerBackground(Brand.ocean.opacity(0.2).gradient, for: .tabView)
    }
}

struct WorkoutPickerPage: View {
    @Environment(WorkoutManager.self) private var workout
    let options: [(WorkoutActivity, LocalizedStringKey, String)] = [
        (.running, "Run", "figure.run"), (.walking, "Walk", "figure.walk"), (.cycling, "Cycle", "figure.outdoor.cycle"),
        (.strength, "Strength", "dumbbell"), (.hiit, "HIIT", "flame"), (.yoga, "Yoga", "figure.yoga"),
    ]
    var body: some View {
        List {
            ForEach(options, id: \.0) { o in
                Button {
                    Task { await workout.start(o.0) }
                } label: {
                    Label(o.1, systemImage: o.2)
                }
            }
            if let e = workout.lastError { Text(e).font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle(Text("Workout"))
        .containerBackground(Brand.deepBlue.opacity(0.4).gradient, for: .tabView)
    }
}

struct LiveWorkoutView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 4) {
                if let s = workout.startDate {
                    Text(s, style: .timer).font(.system(.title2, design: .rounded).weight(.semibold)).foregroundStyle(Brand.emerald)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Image(systemName: "heart.fill").foregroundStyle(Brand.coral)
                    Text(verbatim: workout.heartRate.map { String(Int($0)) } ?? "—").font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("bpm").font(.footnote).foregroundStyle(.secondary)
                }
                Text(verbatim: "\(Int(workout.activeEnergy)) kcal · \(String(format: "%.2f", workout.distance / 1000)) km")
                    .font(.footnote.monospacedDigit())
                HStack {
                    Button { workout.togglePause() } label: {
                        Image(systemName: workout.state == .paused ? "play.fill" : "pause.fill")
                    }
                    .tint(Brand.amber)
                    Button(role: .destructive) { Task { await workout.end() } } label: { Image(systemName: "stop.fill") }
                        .disabled(workout.state == .saving)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
    }
}
