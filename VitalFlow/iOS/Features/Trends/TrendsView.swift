import SwiftUI
import Charts
import VitalFlowCore

enum TrendMetric: String, CaseIterable, Identifiable {
    case hrv, restingHeartRate, sleep, steps, activeEnergy, respiratoryRate, oxygen, vo2Max, bodyMass, daylight, water
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .sleep: "Sleep"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        case .respiratoryRate: "Respiratory rate"
        case .oxygen: "Blood oxygen"
        case .vo2Max: "VO2 max"
        case .bodyMass: "Body weight"
        case .daylight: "Time in daylight"
        case .water: "Water"
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .sleep: "h"
        case .steps: ""
        case .activeEnergy: "kcal"
        case .respiratoryRate: "br/min"
        case .oxygen: "%"
        case .vo2Max: "ml/kg/min"
        case .bodyMass: "kg"
        case .daylight: "min"
        case .water: "ml"
        }
    }

    func value(_ m: DailyMetrics) -> Double? {
        switch self {
        case .hrv: m.hrv
        case .restingHeartRate: m.restingHeartRate
        case .sleep: m.sleep.map { $0.asleep / 3600 }
        case .steps: m.steps
        case .activeEnergy: m.activeEnergy
        case .respiratoryRate: m.respiratoryRate
        case .oxygen: m.oxygenSaturation.map { $0 * 100 }
        case .vo2Max: m.vo2Max
        case .bodyMass: m.bodyMass
        case .daylight: m.daylightMinutes
        case .water: m.waterML
        }
    }
}

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var metric: TrendMetric = .hrv
    @State private var range = 30
    @State private var selected: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isDemo { DemoBanner() }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TrendMetric.allCases) { m in
                                Button { Haptics.selection(); metric = m } label: {
                                    Text(m.title).font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(metric == m ? AnyShapeStyle(Brand.flow) : AnyShapeStyle(.thinMaterial), in: Capsule())
                                        .foregroundStyle(metric == m ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Picker("Range", selection: $range) {
                        Text("7D").tag(7); Text("30D").tag(30); Text("90D").tag(90); Text("1Y").tag(365)
                    }
                    .pickerStyle(.segmented)
                    chartCard
                    weeklyCard
                    ExperimentalNote()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .vfBackground()
            .navigationTitle(Text("Trends"))
        }
    }

    struct P: Identifiable { let id: Date; let v: Double }

    private var points: [P] {
        let cal = Calendar.current
        return model.history.suffix(range).compactMap { m in metric.value(m).map { P(id: m.day.startDate(in: cal), v: $0) } }
    }

    private var chartCard: some View {
        let pts = points
        let avg = Math.mean(pts.map(\.v))
        return VFCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title).font(.headline)
                        Text("Average").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let s = selected, let p = pts.min(by: { abs($0.id.timeIntervalSince(s)) < abs($1.id.timeIntervalSince(s)) }) {
                        VStack(alignment: .trailing) {
                            Text(verbatim: "\(Fmt.one(p.v) ?? "") \(metric.unit)").font(.title3.weight(.semibold).monospacedDigit())
                            Text(p.id, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(verbatim: "\(Fmt.one(avg) ?? "—") \(metric.unit)").font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
                if pts.count < 2 {
                    NotEnoughDataView(missing: [])
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(pts) { p in
                            LineMark(x: .value("Date", p.id, unit: .day), y: .value("Value", p.v))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Brand.emerald)
                            AreaMark(x: .value("Date", p.id, unit: .day), y: .value("Value", p.v))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(colors: [Brand.emerald.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        }
                        if let avg {
                            RuleMark(y: .value("Average", avg))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(.secondary)
                        }
                        if let s = selected {
                            RuleMark(x: .value("Selected", s, unit: .day)).foregroundStyle(Brand.ocean.opacity(0.4))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXSelection(value: $selected)
                    .frame(height: 220)
                    .sensoryFeedback(.selection, trigger: selected)
                }
            }
        }
    }

    private var weeklyCard: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "This week vs last week", systemImage: "arrow.left.arrow.right")
                ForEach(model.assessment?.trends ?? [], id: \.metric) { t in
                    HStack {
                        Text(trendName(t.metric)).font(.subheadline)
                        Spacer()
                        if let c = t.changePercent {
                            Text(verbatim: "\(c >= 0 ? "+" : "")\(Fmt.one(c) ?? "")%").font(.subheadline.monospacedDigit())
                        }
                        Image(systemName: icon(t.direction)).foregroundStyle(color(t.direction))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    func trendName(_ key: String) -> LocalizedStringKey {
        switch key {
        case "hrv": "HRV"
        case "restingHeartRate": "Resting heart rate"
        case "sleep": "Sleep"
        case "steps": "Steps"
        case "activeEnergy": "Active energy"
        case "daylight": "Time in daylight"
        default: LocalizedStringKey(key)
        }
    }

    func icon(_ d: TrendDirection) -> String {
        switch d {
        case .improving: "arrow.up.right.circle.fill"
        case .declining: "arrow.down.right.circle.fill"
        case .stable: "equal.circle.fill"
        case .insufficient: "questionmark.circle"
        }
    }

    func color(_ d: TrendDirection) -> Color {
        switch d {
        case .improving: Brand.emerald
        case .declining: Brand.amber
        default: .secondary
        }
    }
}
