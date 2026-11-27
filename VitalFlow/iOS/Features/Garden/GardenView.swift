import SwiftUI
import Charts
import SwiftData
import VitalFlowCore

extension GoalKind {
    var title: LocalizedStringKey {
        switch self {
        case .steps: "Steps"
        case .exerciseMinutes: "Exercise"
        case .activeEnergy: "Move"
        case .sleepHours: "Sleep"
        case .waterML: "Water"
        case .daylightMinutes: "Daylight"
        }
    }
    var unit: String {
        switch self {
        case .steps: ""
        case .exerciseMinutes, .daylightMinutes: "min"
        case .activeEnergy: "kcal"
        case .sleepHours: "h"
        case .waterML: "ml"
        }
    }
    var icon: String {
        switch self {
        case .steps: "figure.walk"
        case .exerciseMinutes: "figure.run"
        case .activeEnergy: "flame"
        case .sleepHours: "moon.zzz"
        case .waterML: "drop"
        case .daylightMinutes: "sun.max"
        }
    }
    var color: Color {
        switch self {
        case .steps: Brand.ocean
        case .exerciseMinutes: Brand.emerald
        case .activeEnergy: Brand.coral
        case .sleepHours: Brand.deepBlue
        case .waterML: Color(red: 0.3, green: 0.7, blue: 0.95)
        case .daylightMinutes: Brand.amber
        }
    }
}

extension Achievement {
    var title: LocalizedStringKey {
        switch self {
        case .firstGoal: "First sprout"
        case .threeDayStreak: "Three-day rhythm"
        case .sevenDayStreak: "Week in bloom"
        case .tenKSteps: "10,000 steps"
        case .hydrationWeek: "Well watered"
        case .restfulWeek: "Restful stretch"
        case .firstBloom: "First bloom"
        case .firstTree: "Old oak"
        case .earlyLight: "Sun seeker"
        }
    }
    var detail: LocalizedStringKey {
        switch self {
        case .firstGoal: "Complete any daily goal."
        case .threeDayStreak: "Meet two goals three days in a row."
        case .sevenDayStreak: "Meet two goals seven days in a row."
        case .tenKSteps: "Walk 10,000 steps in a day."
        case .hydrationWeek: "Reach your water goal seven days in a row."
        case .restfulWeek: "Sleep seven hours or more five nights in a row."
        case .firstBloom: "Grow a plant to full bloom."
        case .firstTree: "Grow a plant into a tree."
        case .earlyLight: "Spend an hour in daylight in one day."
        }
    }
    var icon: String {
        switch self {
        case .firstGoal: "leaf"
        case .threeDayStreak: "3.circle"
        case .sevenDayStreak: "7.circle"
        case .tenKSteps: "shoeprints.fill"
        case .hydrationWeek: "drop.circle"
        case .restfulWeek: "bed.double.circle"
        case .firstBloom: "camera.macro"
        case .firstTree: "tree"
        case .earlyLight: "sun.horizon"
        }
    }
}

struct GardenView: View {
    @Environment(AppModel.self) private var model
    @State private var editingGoals = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isDemo { DemoBanner() }
                    gardenCard
                    goalsCard
                    weeklyCard
                    achievementsCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .vfBackground()
            .navigationTitle(Text("Garden"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit goals") { editingGoals = true }
                }
            }
            .sheet(isPresented: $editingGoals) { GoalEditor() }
        }
    }

    private var gardenCard: some View {
        let g = model.garden
        return VFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Brand.deepBlue.opacity(0.85), Brand.emerald.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 210)
                    GardenScene(plants: g.plants)
                        .frame(height: 210)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Your garden").font(.headline).foregroundStyle(.white)
                            Text(String(format: String(localized: "%d growth · %d-day rhythm"), g.totalGrowth, g.currentStreak))
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(16)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                Text("Each goal you complete helps a plant grow. Missed days never wilt your garden — plants simply rest.")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }
        }
    }

    private var goalsCard: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Today's goals", systemImage: "target")
                if let m = model.assessment?.metrics {
                    ForEach(GoalKind.allCases.filter { model.settings.goals.enabled.contains($0) }) { k in
                        let p = model.settings.goals.progress(k, metrics: m)
                        HStack(spacing: 12) {
                            Image(systemName: p >= 1 ? "checkmark.circle.fill" : k.icon)
                                .foregroundStyle(k.color).frame(width: 26)
                                .symbolEffect(.bounce, value: p >= 1)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(k.title).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(verbatim: "\(Fmt.one(k.value(from: m)).map { k == .sleepHours ? $0 : (Fmt.int(k.value(from: m)) ?? $0) } ?? "—") / \(Fmt.int(model.settings.goals.target(for: k)) ?? "") \(k.unit)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                ProgressView(value: min(1, p)).tint(k.color)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var weeklyCard: some View {
        let cal = Calendar.current
        let end = model.assessment?.day ?? DayKey(Date(), calendar: cal)
        let r = ReportBuilder.report(history: model.history, goals: model.settings.goals, end: end, days: 7, calendar: cal)
        let week = model.history.suffix(7)
        return VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weekly report", systemImage: "calendar")
                Chart(Array(week), id: \.day) { m in
                    BarMark(x: .value("Day", m.day.startDate(in: cal), unit: .day),
                            y: .value("Goals", model.settings.goals.completed(metrics: m).count))
                        .foregroundStyle(Brand.flow)
                        .cornerRadius(4)
                }
                .chartYScale(domain: 0...max(1, model.settings.goals.enabled.count))
                .frame(height: 110)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("Goals completed").foregroundStyle(.secondary); Text(verbatim: "\(r.goalsCompleted)") }
                    GridRow { Text("Average sleep").foregroundStyle(.secondary); Text(verbatim: Fmt.one(r.averageSleepHours).map { "\($0) h" } ?? "—") }
                    GridRow { Text("Average steps").foregroundStyle(.secondary); Text(verbatim: Fmt.int(r.averageSteps) ?? "—") }
                    GridRow { Text("Average resting HR").foregroundStyle(.secondary); Text(verbatim: Fmt.int(r.averageRestingHR).map { "\($0) bpm" } ?? "—") }
                }
                .font(.subheadline)
            }
        }
    }

    private var achievementsCard: some View {
        let unlocked = model.achievements
        return VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Badges", systemImage: "rosette")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(Achievement.allCases) { a in
                        let on = unlocked.contains(a)
                        VStack(spacing: 6) {
                            Image(systemName: a.icon)
                                .font(.title)
                                .foregroundStyle(on ? AnyShapeStyle(Brand.flow) : AnyShapeStyle(.tertiary))
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(on ? Brand.emerald.opacity(0.12) : Color.secondary.opacity(0.08)))
                            Text(a.title).font(.caption.weight(.medium)).multilineTextAlignment(.center)
                            Text(a.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .opacity(on ? 1 : 0.6)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(on ? Text("Unlocked") : Text("Locked"))
                    }
                }
            }
        }
    }
}

/// Original illustrated garden built from SF Symbols; plant size reflects growth stage.
struct GardenScene: View {
    let plants: [GardenPlant]

    func symbol(_ s: PlantStage) -> String {
        switch s {
        case .seed: "circle.fill"
        case .sprout: "leaf"
        case .sapling: "leaf.fill"
        case .bud: "camera.macro"
        case .bloom: "camera.macro.circle.fill"
        case .tree: "tree.fill"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let shown = Array(plants.suffix(14))
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.black.opacity(0.18)).frame(height: 40).offset(y: 20)
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                    let x = (CGFloat(i) + 0.5) / CGFloat(max(shown.count, 1)) * geo.size.width
                    let size = 14 + CGFloat(p.stage.rawValue) * 9
                    Image(systemName: symbol(p.stage))
                        .font(.system(size: size))
                        .foregroundStyle(p.kind.color.gradient)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .position(x: x, y: geo.size.height - 22 - size / 2 + CGFloat(i % 2) * 6)
                        .transition(.scale.combined(with: .opacity))
                }
                if shown.isEmpty {
                    Image(systemName: "circle.dotted").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                        .position(x: geo.size.width / 2, y: geo.size.height - 40)
                }
            }
        }
        .accessibilityLabel(Text("Garden illustration"))
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: plants.count)
    }
}

struct GoalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    ForEach(GoalKind.allCases) { k in
                        VStack(alignment: .leading) {
                            Toggle(isOn: Binding(get: { model.settings.goals.enabled.contains(k) },
                                                 set: { on in
                                                     if on { model.settings.goals.enabled.insert(k) } else { model.settings.goals.enabled.remove(k) }
                                                 })) {
                                Label(k.title, systemImage: k.icon)
                            }
                            Stepper(value: Binding(get: { model.settings.goals.target(for: k) },
                                                   set: { model.settings.goals.setTarget($0, for: k) }),
                                    in: k.allowedRange, step: k.step) {
                                Text(verbatim: "\(Fmt.one(model.settings.goals.target(for: k)).map { k == .sleepHours ? $0 : (Fmt.int(model.settings.goals.target(for: k)) ?? $0) } ?? "") \(k.unit)")
                                    .monospacedDigit()
                            }
                        }
                    }
                } footer: {
                    Text("Goals stay within healthy ranges. VitalFlow never sets extreme exercise or calorie targets.")
                }
            }
            .navigationTitle(Text("Goals"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
