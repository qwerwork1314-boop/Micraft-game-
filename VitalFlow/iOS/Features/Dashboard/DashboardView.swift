import SwiftUI
import Charts
import SwiftData
import VitalFlowCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var showSettings = false
    @State private var detail: ScoreKind?
    @State private var showConnection = false
    @State private var launcher: LauncherMode?

    enum LauncherMode: String, Identifiable {
        case browse, heartCheck
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isDemo { DemoBanner() }
                    if !model.healthAvailable && !model.isDemo { unavailableCard }
                    if model.healthAvailable && !model.isDemo && model.bundle != nil && !model.hasRecentHealthData {
                        noDataCard
                    }
                    if let a = model.assessment {
                        AIBriefingCard()
                        hero(a)
                        readinessCard(a)
                        HStack(spacing: 12) {
                            heartCard(a)
                            sleepCard(a)
                        }
                        ActivityRingsCard(metrics: a.metrics, goals: model.settings.goals)
                        HydrationCard(water: a.metrics.waterML ?? 0, goal: model.settings.goals.target(for: .waterML))
                        StressChartCard(report: a.stress)
                        BatteryChartCard(report: a.bodyBattery)
                        SuggestionsCard(suggestions: Suggestions.make(a, goals: model.settings.goals))
                        ExperimentalNote().padding(.top, 4)
                        Text(String(format: String(localized: "Updated %@"), Fmt.time(a.generatedAt)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        ProgressView().padding(60)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh(); model.persistDailyScores(context: context) }
            .vfBackground()
            .navigationTitle(Text(Date.now, format: .dateTime.weekday(.wide).day().month()))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { launcher = .browse } label: { Image(systemName: "figure.run.circle") }
                        .accessibilityLabel(Text("Workout & heart rate"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $detail) { kind in ScoreDetailView(kind: kind) }
            .sheet(isPresented: $showConnection) { NavigationStack { HealthConnectionView() } }
            .sheet(item: $launcher) { mode in WorkoutLauncherView(startHeartCheckImmediately: mode == .heartCheck) }
            .task { model.persistDailyScores(context: context) }
        }
    }

    private var noDataCard: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("No Health data found", systemImage: "heart.slash").font(.headline)
                Text("VitalFlow can't see any Health data from the last 7 days yet. Check the connection to find out why.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button { showConnection = true } label: {
                        Label("Check Health connection", systemImage: "stethoscope")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.emerald)
                    Button("Use demo data") { model.setDemoMode(true) }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
        }
    }

    private var unavailableCard: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Health data unavailable", systemImage: "heart.slash").font(.headline)
                Text("This device doesn't support HealthKit. You can explore VitalFlow with demo data in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func hero(_ a: DailyAssessment) -> some View {
        VFCard(padding: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    Button { Haptics.tap(); detail = .recovery } label: {
                        ScoreGauge(title: "Recovery", result: a.recovery, size: 150, lineWidth: 16)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 12)
                    VStack(spacing: 14) {
                        Button { Haptics.tap(); detail = .battery } label: {
                            ScoreGauge(title: "Body Battery", result: a.bodyBattery.result, color: Brand.ocean, size: 72, lineWidth: 8)
                        }.buttonStyle(.plain)
                        Button { Haptics.tap(); detail = .stress } label: {
                            ScoreGauge(title: "Stress", result: a.stress.result, color: Brand.stressColor(a.stress.result.score), size: 72, lineWidth: 8)
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    ConfidenceBadge(confidence: a.recovery.confidence)
                    Spacer()
                    Text(Suggestions.headline(a)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func readinessCard(_ a: DailyAssessment) -> some View {
        Button { Haptics.tap(); detail = .readiness } label: {
            VFCard {
                HStack(spacing: 14) {
                    Image(systemName: "figure.run.circle.fill").font(.largeTitle).foregroundStyle(Brand.flow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training readiness").font(.caption).foregroundStyle(.secondary)
                        if let level = a.readiness.level {
                            Text(Suggestions.readinessTitle(level)).font(.headline)
                        } else {
                            NotEnoughDataView(missing: a.readiness.result.missing, compact: true)
                        }
                        if let b = a.balance {
                            Text(Suggestions.balanceTitle(b)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let s = a.readiness.result.score {
                        Text(s, format: .number).font(.title.weight(.semibold).monospacedDigit()).foregroundStyle(Brand.scoreColor(s))
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func heartCard(_ a: DailyAssessment) -> some View {
        VFCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Heart", systemImage: "heart.fill").font(.caption.weight(.medium)).foregroundStyle(Brand.coral)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: Fmt.int(a.latestHeartRate) ?? "—").font(.title.weight(.semibold).monospacedDigit())
                    Text("bpm").font(.caption).foregroundStyle(.secondary)
                }
                Text("Latest").font(.caption2).foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 3) {
                    Text("Resting").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: Fmt.int(a.metrics.restingHeartRate) ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
                }
                HStack(spacing: 3) {
                    Text("HRV").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: (Fmt.int(a.metrics.hrv).map { "\($0) ms" }) ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
                }
                Button {
                    Haptics.tap()
                    launcher = .heartCheck
                } label: {
                    Label("Measure", systemImage: "waveform.path.ecg").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Brand.coral)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func sleepCard(_ a: DailyAssessment) -> some View {
        VFCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sleep", systemImage: "moon.zzz.fill").font(.caption.weight(.medium)).foregroundStyle(Brand.ocean)
                Text(verbatim: Fmt.duration(a.metrics.sleep?.asleep) ?? "—").font(.title.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("Last night").font(.caption2).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Score").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: a.sleepScore.score.map(String.init) ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
                }
                HStack {
                    Text("Wake-ups").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: a.metrics.sleep.map { String($0.interruptions) } ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Activity rings

struct ActivityRingsCard: View {
    let metrics: DailyMetrics
    let goals: GoalSet

    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Activity", systemImage: "flame.fill")
                HStack(spacing: 20) {
                    ZStack {
                        ScoreRing(progress: goals.progress(.activeEnergy, metrics: metrics), color: Brand.coral, lineWidth: 12)
                            .frame(width: 112, height: 112)
                        ScoreRing(progress: goals.progress(.exerciseMinutes, metrics: metrics), color: Brand.emerald, lineWidth: 12)
                            .frame(width: 84, height: 84)
                        ScoreRing(progress: goals.progress(.steps, metrics: metrics), color: Brand.ocean, lineWidth: 12)
                            .frame(width: 56, height: 56)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        row("Move", metrics.activeEnergy, goals.target(for: .activeEnergy), "kcal", Brand.coral)
                        row("Exercise", metrics.exerciseMinutes, goals.target(for: .exerciseMinutes), "min", Brand.emerald)
                        row("Steps", metrics.steps, goals.target(for: .steps), "", Brand.ocean)
                    }
                }
                HStack(spacing: 16) {
                    Label { Text(verbatim: Fmt.int((metrics.activeEnergy ?? 0) + (metrics.basalEnergy ?? 0)) ?? "—") + Text(" ") + Text("kcal total") }
                        icon: { Image(systemName: "bolt.heart") }
                    Label { Text(verbatim: Fmt.one(metrics.distance.map { $0 / 1000 }) ?? "—") + Text(" km") }
                        icon: { Image(systemName: "point.topleft.down.to.point.bottomright.curvepath") }
                    Label { Text(verbatim: Fmt.int(metrics.daylightMinutes) ?? "—") + Text(" ") + Text("min daylight") }
                        icon: { Image(systemName: "sun.max") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ v: Double?, _ goal: Double, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(color)
            Text(verbatim: "\(Fmt.int(v) ?? "—") / \(Fmt.int(goal) ?? "") \(unit)").font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hydration

struct HydrationCard: View {
    @Environment(AppModel.self) private var model
    let water: Double
    let goal: Double
    @State private var saving = false

    var body: some View {
        VFCard {
            HStack(spacing: 16) {
                ZStack {
                    ScoreRing(progress: water / max(goal, 1), color: Brand.ocean, lineWidth: 8)
                    Image(systemName: "drop.fill").foregroundStyle(Brand.ocean).font(.title3)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hydration").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "\(Fmt.int(water) ?? "0") / \(Fmt.int(goal) ?? "") ml").font(.headline.monospacedDigit())
                }
                Spacer()
                Button {
                    saving = true
                    Haptics.success()
                    Task { await model.logWater(250); saving = false }
                } label: {
                    Label("250 ml", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .vfGlass(in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(saving)
                .accessibilityLabel(Text("Log 250 millilitres of water"))
            }
        }
    }
}

// MARK: - Charts

struct StressChartCard: View {
    let report: StressReport
    @State private var selected: Date?

    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Stress today", systemImage: "waveform.path.ecg")
                if report.hourly.isEmpty {
                    NotEnoughDataView(missing: report.result.missing)
                } else {
                    Chart(report.hourly, id: \.hourStart) { h in
                        BarMark(x: .value("Hour", h.hourStart, unit: .hour), y: .value("Stress", h.level))
                            .foregroundStyle(Brand.stressColor(h.level).gradient)
                            .cornerRadius(4)
                            .opacity(selected == nil || Calendar.current.isDate(h.hourStart, equalTo: selected!, toGranularity: .hour) ? 1 : 0.4)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXSelection(value: $selected)
                    .frame(height: 140)
                    if let s = selected, let h = report.hourly.first(where: { Calendar.current.isDate($0.hourStart, equalTo: s, toGranularity: .hour) }) {
                        Text(verbatim: "\(Fmt.time(h.hourStart)) · \(h.level)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct BatteryChartCard: View {
    let report: BodyBatteryReport

    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Body Battery", systemImage: "battery.75percent")
                if report.timeline.count < 2 {
                    NotEnoughDataView(missing: report.result.missing)
                } else {
                    Chart(report.timeline, id: \.time) { p in
                        AreaMark(x: .value("Time", p.time), y: .value("Level", p.level))
                            .foregroundStyle(LinearGradient(colors: [Brand.ocean.opacity(0.35), Brand.emerald.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", p.time), y: .value("Level", p.level))
                            .foregroundStyle(Brand.ocean)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                }
            }
        }
    }
}

// MARK: - Suggestions

struct SuggestionsCard: View {
    let suggestions: [Suggestion]
    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "For you today", systemImage: "sparkles")
                ForEach(suggestions) { s in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: s.icon).foregroundStyle(Brand.emerald).frame(width: 24)
                        Text(s.text).font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - AI briefing

struct AIBriefingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.aiAvailable && (model.aiBriefing != nil || model.aiBriefingLoading) {
            VFCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("AI briefing", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.flow)
                        Spacer()
                        Text("On-device · Apple Intelligence").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let text = model.aiBriefing {
                        Text(text).font(.subheadline).transition(.opacity)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Writing your briefing…").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Haptics.tap()
                        model.askCoach(String(localized: "What should I focus on today?"))
                    } label: {
                        Label("Ask Coach", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.emerald)
                }
            }
        }
    }
}
