import SwiftUI
import Charts
import VitalFlowCore

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .day: "Day"; case .week: "Week"; case .month: "Month"; case .year: "Year" }
    }
    var days: Int {
        switch self { case .day: 1; case .week: 7; case .month: 30; case .year: 365 }
    }
}

struct SleepView: View {
    @Environment(AppModel.self) private var model
    @State private var period: ReportPeriod = .day

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isDemo { DemoBanner() }
                    Picker("Period", selection: $period) {
                        ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: period) { Haptics.selection() }

                    if period == .day {
                        dayReport
                    } else {
                        SleepTrendReport(period: period, history: model.history)
                    }
                    ExperimentalNote()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .vfBackground()
            .navigationTitle(Text("Sleep"))
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder private var dayReport: some View {
        if let a = model.assessment, let n = a.metrics.sleep {
            VFCard(padding: 20) {
                HStack(spacing: 20) {
                    ScoreGauge(title: "Sleep score", result: a.sleepScore, color: Brand.ocean, size: 110, lineWidth: 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: Fmt.duration(n.asleep) ?? "—").font(.largeTitle.weight(.semibold).monospacedDigit())
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(verbatim: "\(Fmt.time(n.start)) – \(Fmt.time(n.end))").font(.subheadline).foregroundStyle(.secondary)
                        ConfidenceBadge(confidence: a.sleepScore.confidence)
                    }
                }
            }
            SleepTimelineCard(night: n)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Efficiency", value: Fmt.int(n.efficiency * 100), unit: "%", systemImage: "gauge.with.dots.needle.67percent", tint: Brand.ocean)
                MetricTile(title: "Wake-ups", value: String(n.interruptions), unit: "", systemImage: "eye", tint: Brand.amber)
                MetricTile(title: "Consistency", value: a.sleepConsistency.score.map(String.init), unit: "/100", systemImage: "calendar", tint: Brand.emerald)
                MetricTile(title: "Awake", value: Fmt.duration(n.awake), unit: "", systemImage: "moon.haze", tint: .secondary)
                MetricTile(title: "Sleeping HR", value: Fmt.int(Math.mean(model.bundle?.lastNightHeartRate.map(\.value) ?? [])), unit: "bpm", systemImage: "heart", tint: Brand.coral)
                MetricTile(title: "Respiratory rate", value: Fmt.one(a.metrics.respiratoryRate), unit: "br/min", systemImage: "lungs", tint: Brand.ocean)
            }
            if let hr = model.bundle?.lastNightHeartRate, hr.count >= 3 {
                VFCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Heart rate during sleep", systemImage: "heart.text.square")
                        Chart(hr) { s in
                            LineMark(x: .value("Time", s.start), y: .value("bpm", s.value))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Brand.coral)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 110)
                    }
                }
            }
            if n.napDuration > 0 {
                VFCard {
                    Label { Text("Nap") + Text(verbatim: " · \(Fmt.duration(n.napDuration) ?? "")") } icon: { Image(systemName: "sun.haze") }
                }
            }
            SleepSuggestionsCard(night: n, consistency: a.sleepConsistency.score, need: model.settings.sleepNeedHours)
        } else {
            VFCard {
                VStack(alignment: .leading, spacing: 8) {
                    NotEnoughDataView(missing: [.sleepLastNight])
                    Text("Sleep stages require Apple Watch with sleep tracking enabled (Sleep Focus in the Health app).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SleepTimelineCard: View {
    let night: SleepNight

    static func name(_ s: SleepStage) -> String {
        switch s {
        case .awake: String(localized: "Awake")
        case .rem: String(localized: "REM")
        case .core: String(localized: "Core")
        case .deep: String(localized: "Deep")
        case .asleepUnspecified: String(localized: "Asleep")
        case .inBed: String(localized: "In bed")
        }
    }

    static func color(_ s: SleepStage) -> Color {
        switch s {
        case .awake: Brand.amber
        case .rem: Color(red: 0.45, green: 0.75, blue: 1.0)
        case .core: Brand.ocean
        case .deep: Brand.deepBlue
        case .asleepUnspecified: Brand.emerald
        case .inBed: .gray
        }
    }

    var stages: [SleepStage] {
        night.hasStageData ? [.awake, .rem, .core, .deep] : [.awake, .asleepUnspecified]
    }

    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sleep stages", systemImage: "chart.bar.xaxis")
                Chart(night.segments.filter { $0.stage != .inBed }, id: \.start) { seg in
                    RectangleMark(xStart: .value("Start", seg.start), xEnd: .value("End", seg.end),
                                  y: .value("Stage", Self.name(seg.stage)))
                        .foregroundStyle(Self.color(seg.stage))
                        .cornerRadius(3)
                }
                .chartYScale(domain: stages.map(Self.name))
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 170)
                .accessibilityLabel(Text("Sleep stage timeline"))

                if night.hasStageData {
                    HStack {
                        stageTotal(.deep, night.deep)
                        stageTotal(.rem, night.rem)
                        stageTotal(.core, night.core)
                        stageTotal(.awake, night.awake)
                    }
                }
            }
        }
    }

    func stageTotal(_ s: SleepStage, _ t: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(Self.color(s)).frame(width: 8, height: 8)
                Text(verbatim: Self.name(s)).font(.caption2).foregroundStyle(.secondary)
            }
            Text(verbatim: Fmt.duration(t) ?? "—").font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SleepTrendReport: View {
    let period: ReportPeriod
    let history: [DailyMetrics]

    struct Point: Identifiable { let id: Date; let hours: Double; let deep: Double; let rem: Double }

    var points: [Point] {
        let cal = Calendar.current
        let recent = history.suffix(period.days)
        if period == .year {
            // Monthly averages for readability.
            let groups = Dictionary(grouping: recent.filter { $0.sleep != nil }) { m -> Date in
                cal.dateInterval(of: .month, for: m.day.startDate(in: cal))?.start ?? m.day.startDate(in: cal)
            }
            return groups.map { k, v in
                Point(id: k, hours: Math.mean(v.compactMap { $0.sleep?.asleep }).map { $0 / 3600 } ?? 0,
                      deep: Math.mean(v.compactMap { $0.sleep?.deep }).map { $0 / 3600 } ?? 0,
                      rem: Math.mean(v.compactMap { $0.sleep?.rem }).map { $0 / 3600 } ?? 0)
            }.sorted { $0.id < $1.id }
        }
        return recent.compactMap { m in
            m.sleep.map { Point(id: m.day.startDate(in: cal), hours: $0.asleep / 3600, deep: $0.deep / 3600, rem: $0.rem / 3600) }
        }
    }

    var body: some View {
        let pts = points
        let nights = history.suffix(period.days).compactMap(\.sleep)
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Time asleep", systemImage: "bed.double")
                if pts.isEmpty {
                    NotEnoughDataView(missing: [.sleepHistory])
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Average").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: Fmt.duration(Math.mean(nights.map(\.asleep))) ?? "—").font(.title2.weight(.semibold).monospacedDigit())
                    }
                    Chart(pts) { p in
                        BarMark(x: .value("Date", p.id, unit: period == .year ? .month : .day), y: .value("Hours", p.hours))
                            .foregroundStyle(Brand.flow)
                            .cornerRadius(4)
                    }
                    .frame(height: 180)
                }
            }
        }
        if !nights.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Avg deep", value: Fmt.duration(Math.mean(nights.map(\.deep))), unit: "", systemImage: "moon.fill", tint: Brand.deepBlue)
                MetricTile(title: "Avg REM", value: Fmt.duration(Math.mean(nights.map(\.rem))), unit: "", systemImage: "sparkles", tint: Brand.ocean)
                MetricTile(title: "Avg wake-ups", value: Fmt.one(Math.mean(nights.map { Double($0.interruptions) })), unit: "", systemImage: "eye", tint: Brand.amber)
                MetricTile(title: "Avg efficiency", value: Fmt.int(Math.mean(nights.map(\.efficiency)).map { $0 * 100 }), unit: "%", systemImage: "gauge", tint: Brand.emerald)
            }
            if nights.count >= 4 {
                let c = SleepAnalyzer(calendar: .current).consistency(of: Array(nights.suffix(14)))
                MetricTile(title: "Consistency (last 14 nights)", value: c.score.map(String.init), unit: "/100", systemImage: "calendar", tint: Brand.emerald)
            }
        }
    }
}

struct SleepSuggestionsCard: View {
    let night: SleepNight
    let consistency: Int?
    let need: Double

    var body: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Sleep suggestions", systemImage: "lightbulb")
                if night.asleep < need * 3600 * 0.9 {
                    tip("bed.double", "You slept less than your goal. Going to bed 20–30 minutes earlier is a gentle way to catch up.")
                }
                if let c = consistency, c < 60 {
                    tip("calendar", "Your sleep timing varied this week. Similar bed and wake times help your body clock.")
                }
                if night.interruptions >= 4 {
                    tip("eye", "Several wake-ups last night. A cool, dark, quiet room and less caffeine late in the day may help.")
                }
                if let r = night.restorativeFraction, r < 0.25 {
                    tip("moon.stars", "Deep and REM sleep were on the lower side. Regular exercise and limiting alcohol before bed can support them.")
                }
                tip("sun.max", "Morning daylight helps anchor your sleep rhythm.")
            }
        }
    }

    func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.ocean).frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}
