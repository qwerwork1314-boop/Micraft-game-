import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (SnapshotStore.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SnapshotStore.load() ?? .empty)
        // The app reloads timelines whenever scores change; this is only a fallback refresh.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct VitalFlowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(s.recovery ?? 0), in: 0...100) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                Text(verbatim: s.recovery.map(String.init) ?? "—")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("VitalFlow").font(.headline).widgetAccentable()
                Text(verbatim: "\(String(localized: "Recovery")) \(s.recovery.map(String.init) ?? "—")")
                Text(verbatim: "\(String(localized: "Battery")) \(s.bodyBattery.map(String.init) ?? "—") · \(String(localized: "Stress")) \(s.stress.map(String.init) ?? "—")")
            }
            .font(.caption)
        case .accessoryInline:
            Text(verbatim: "\(String(localized: "Recovery")) \(s.recovery.map(String.init) ?? "—") · \(String(localized: "Battery")) \(s.bodyBattery.map(String.init) ?? "—")")
        case .systemMedium:
            HStack(spacing: 16) {
                ring(String(localized: "Recovery"), s.recovery, Brand.scoreColor(s.recovery), size: 86)
                VStack(alignment: .leading, spacing: 8) {
                    row("battery.75percent", String(localized: "Body Battery"), s.bodyBattery.map(String.init))
                    row("waveform.path.ecg", String(localized: "Stress"), s.stress.map(String.init))
                    row("moon.zzz.fill", String(localized: "Sleep"), s.sleepMinutes.map { "\($0 / 60)h \($0 % 60)m" })
                    row("figure.walk", String(localized: "Steps"), s.steps.map { $0.formatted() })
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .topTrailing) { demoTag(s) }
        default:
            VStack(alignment: .leading, spacing: 8) {
                ring(String(localized: "Recovery"), s.recovery, Brand.scoreColor(s.recovery), size: 70)
                HStack(spacing: 4) {
                    Image(systemName: "battery.75percent").foregroundStyle(Brand.ocean)
                    Text(verbatim: s.bodyBattery.map(String.init) ?? "—").font(.headline.monospacedDigit())
                }
            }
            .overlay(alignment: .topTrailing) { demoTag(s) }
        }
    }

    @ViewBuilder func demoTag(_ s: WidgetSnapshot) -> some View {
        if s.isDemo { Text("Demo").font(.caption2.weight(.bold)).foregroundStyle(Brand.amber) }
    }

    func ring(_ title: String, _ v: Int?, _ c: Color, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack {
                ScoreRing(progress: Double(v ?? 0) / 100, color: c, lineWidth: size * 0.11)
                Text(verbatim: v.map(String.init) ?? "—").font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            }
            .frame(width: size, height: size)
            Text(verbatim: title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    func row(_ icon: String, _ title: String, _ v: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(Brand.emerald).frame(width: 16)
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(verbatim: v ?? "—").font(.caption.weight(.semibold).monospacedDigit())
        }
    }
}

struct VitalFlowSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalFlowSummary", provider: SnapshotProvider()) { entry in
            VitalFlowWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        }
        .configurationDisplayName(Text("VitalFlow"))
        .description(Text("Recovery, Body Battery, stress and sleep at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VitalFlowWidgetBundle: WidgetBundle {
    var body: some Widget { VitalFlowSummaryWidget() }
}
