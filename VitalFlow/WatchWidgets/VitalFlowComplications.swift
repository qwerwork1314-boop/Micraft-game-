import WidgetKit
import SwiftUI

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: context.isPreview ? .placeholder : (SnapshotStore.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // Reloaded by the watch app on new data; hourly fallback keeps the budget small.
        completion(Timeline(entries: [ComplicationEntry(date: Date(), snapshot: SnapshotStore.load() ?? .empty)],
                            policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry
    let metric: Metric

    enum Metric { case recovery, battery, water }

    var value: Int? {
        switch metric {
        case .recovery: entry.snapshot.recovery
        case .battery: entry.snapshot.bodyBattery
        case .water: entry.snapshot.waterGoal > 0 ? Int(Double(entry.snapshot.waterML) / Double(entry.snapshot.waterGoal) * 100) : nil
        }
    }

    var icon: String {
        switch metric {
        case .recovery: "leaf.fill"
        case .battery: "battery.75percent"
        case .water: "drop.fill"
        }
    }

    var label: String {
        switch metric {
        case .recovery: String(localized: "Recovery")
        case .battery: String(localized: "Battery")
        case .water: String(localized: "Water")
        }
    }

    var body: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: icon)
                .widgetLabel {
                    Gauge(value: Double(value ?? 0), in: 0...100) { Text(verbatim: label) }
                        currentValueLabel: { Text(verbatim: value.map(String.init) ?? "—") }
                }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("VitalFlow").font(.headline).widgetAccentable()
                Text(verbatim: "\(String(localized: "Recovery")) \(entry.snapshot.recovery.map(String.init) ?? "—")")
                Text(verbatim: "\(String(localized: "Battery")) \(entry.snapshot.bodyBattery.map(String.init) ?? "—") · \(entry.snapshot.waterML) ml")
            }
        case .accessoryInline:
            Text(verbatim: "\(label) \(value.map(String.init) ?? "—")")
        default:
            Gauge(value: Double(min(value ?? 0, 100)), in: 0...100) {
                Image(systemName: icon)
            } currentValueLabel: {
                Text(verbatim: value.map(String.init) ?? "—")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }
}

struct RecoveryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalFlowRecovery", provider: ComplicationProvider()) { e in
            ComplicationView(entry: e, metric: .recovery).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text("Recovery"))
        .description(Text("Today's recovery estimate."))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalFlowBattery", provider: ComplicationProvider()) { e in
            ComplicationView(entry: e, metric: .battery).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text("Body Battery"))
        .description(Text("Estimated energy level."))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitalFlowWater", provider: ComplicationProvider()) { e in
            ComplicationView(entry: e, metric: .water).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text("Hydration"))
        .description(Text("Progress toward today's water goal."))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct VitalFlowComplicationBundle: WidgetBundle {
    var body: some Widget {
        RecoveryComplication()
        BatteryComplication()
        WaterComplication()
    }
}
