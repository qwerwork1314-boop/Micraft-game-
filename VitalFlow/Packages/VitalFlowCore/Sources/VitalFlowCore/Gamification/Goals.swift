import Foundation

public enum GoalKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case steps, exerciseMinutes, activeEnergy, sleepHours, waterML, daylightMinutes
    public var id: String { rawValue }

    /// Healthy, non-extreme bounds the user can choose within. Calorie goals are capped
    /// and sleep goals stay within 6–10 h to avoid unhealthy targets.
    public var allowedRange: ClosedRange<Double> {
        switch self {
        case .steps: return 2_000...20_000
        case .exerciseMinutes: return 10...90
        case .activeEnergy: return 150...900
        case .sleepHours: return 6...10
        case .waterML: return 1_000...3_500
        case .daylightMinutes: return 10...120
        }
    }

    public var defaultTarget: Double {
        switch self {
        case .steps: return 8_000
        case .exerciseMinutes: return 30
        case .activeEnergy: return 400
        case .sleepHours: return 8
        case .waterML: return 2_000
        case .daylightMinutes: return 30
        }
    }

    public var step: Double {
        switch self {
        case .steps: return 500
        case .exerciseMinutes, .daylightMinutes: return 5
        case .activeEnergy: return 25
        case .sleepHours: return 0.5
        case .waterML: return 250
        }
    }

    public func value(from m: DailyMetrics) -> Double? {
        switch self {
        case .steps: return m.steps
        case .exerciseMinutes: return m.exerciseMinutes
        case .activeEnergy: return m.activeEnergy
        case .sleepHours: return m.sleep.map { $0.asleep / 3600 }
        case .waterML: return m.waterML
        case .daylightMinutes: return m.daylightMinutes
        }
    }
}

public struct GoalSet: Codable, Hashable, Sendable {
    public private(set) var targets: [GoalKind: Double]
    public var enabled: Set<GoalKind>

    public init(targets: [GoalKind: Double] = [:], enabled: Set<GoalKind> = Set(GoalKind.allCases)) {
        self.targets = [:]
        self.enabled = enabled
        for k in GoalKind.allCases { setTarget(targets[k] ?? k.defaultTarget, for: k) }
    }

    public func target(for kind: GoalKind) -> Double { targets[kind] ?? kind.defaultTarget }

    /// Stores the target clamped into the healthy range.
    public mutating func setTarget(_ v: Double, for kind: GoalKind) {
        targets[kind] = Math.clamp(v, kind.allowedRange.lowerBound, kind.allowedRange.upperBound)
    }

    public func progress(_ kind: GoalKind, metrics: DailyMetrics) -> Double {
        guard let v = kind.value(from: metrics) else { return 0 }
        return Math.clamp(v / target(for: kind), 0, 1.5)
    }

    public func completed(metrics: DailyMetrics) -> [GoalKind] {
        GoalKind.allCases.filter { enabled.contains($0) && progress($0, metrics: metrics) >= 1 }
    }
}

// MARK: - Garden

public enum PlantStage: Int, Codable, Sendable, CaseIterable {
    case seed, sprout, sapling, bud, bloom, tree
}

public struct GardenPlant: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var kind: GoalKind
    public var growth: Int
    public var stage: PlantStage {
        PlantStage(rawValue: min(PlantStage.tree.rawValue, growth / 3)) ?? .tree
    }
}

public struct GardenState: Codable, Hashable, Sendable {
    public var plants: [GardenPlant]
    public var totalGrowth: Int
    public var currentStreak: Int
    public var bestStreak: Int
}

public enum Garden {
    /// Pure function of the goal history, so it never desynchronises between devices.
    /// Each completed goal adds one growth point to that goal's plant; a plant that reaches
    /// "tree" (18 points) stays and a new seed of the same kind is planted.
    /// Missed days never remove growth — plants simply rest (no shame mechanics).
    /// A day counts toward the streak when at least `streakThreshold` goals are met.
    public static func build(history: [DailyMetrics], goals: GoalSet, streakThreshold: Int = 2) -> GardenState {
        var plants: [GardenPlant] = []
        var current: [GoalKind: Int] = [:] // index into plants
        var total = 0, streak = 0, best = 0
        var nextID = 0
        for m in history.sorted(by: { $0.day < $1.day }) {
            let done = goals.completed(metrics: m)
            for k in done {
                total += 1
                if let i = current[k], plants[i].growth < 18 {
                    plants[i].growth += 1
                } else {
                    plants.append(GardenPlant(id: nextID, kind: k, growth: 1))
                    current[k] = plants.count - 1
                    nextID += 1
                }
            }
            if done.count >= streakThreshold { streak += 1; best = max(best, streak) } else { streak = 0 }
        }
        return GardenState(plants: plants, totalGrowth: total, currentStreak: streak, bestStreak: best)
    }
}

// MARK: - Achievements

public enum Achievement: String, Codable, CaseIterable, Sendable, Identifiable {
    case firstGoal, threeDayStreak, sevenDayStreak, tenKSteps, hydrationWeek, restfulWeek, firstBloom, firstTree, earlyLight
    public var id: String { rawValue }
}

public enum AchievementEvaluator {
    public static func unlocked(history: [DailyMetrics], goals: GoalSet) -> Set<Achievement> {
        let sorted = history.sorted { $0.day < $1.day }
        let garden = Garden.build(history: sorted, goals: goals)
        var out = Set<Achievement>()
        if garden.totalGrowth > 0 { out.insert(.firstGoal) }
        if garden.bestStreak >= 3 { out.insert(.threeDayStreak) }
        if garden.bestStreak >= 7 { out.insert(.sevenDayStreak) }
        if sorted.contains(where: { ($0.steps ?? 0) >= 10_000 }) { out.insert(.tenKSteps) }
        if longestRun(sorted, { goals.progress(.waterML, metrics: $0) >= 1 }) >= 7 { out.insert(.hydrationWeek) }
        if longestRun(sorted, { ($0.sleep?.asleep ?? 0) >= 7 * 3600 }) >= 5 { out.insert(.restfulWeek) }
        if garden.plants.contains(where: { $0.stage.rawValue >= PlantStage.bloom.rawValue }) { out.insert(.firstBloom) }
        if garden.plants.contains(where: { $0.stage == .tree }) { out.insert(.firstTree) }
        if sorted.contains(where: { ($0.daylightMinutes ?? 0) >= 60 }) { out.insert(.earlyLight) }
        return out
    }

    static func longestRun(_ days: [DailyMetrics], _ ok: (DailyMetrics) -> Bool) -> Int {
        var best = 0, cur = 0
        for d in days { if ok(d) { cur += 1; best = max(best, cur) } else { cur = 0 } }
        return best
    }
}

// MARK: - Reports

public struct WellnessReport: Codable, Hashable, Sendable {
    public var start: DayKey
    public var end: DayKey
    public var daysWithData: Int
    public var goalsCompleted: Int
    public var averageSleepHours: Double?
    public var averageSteps: Double?
    public var averageRestingHR: Double?
    public var averageHRV: Double?
    public var bestDay: DayKey?
}

public enum ReportBuilder {
    public static func report(history: [DailyMetrics], goals: GoalSet, end: DayKey, days: Int, calendar: Calendar) -> WellnessReport {
        let start = end.adding(days: -(days - 1), calendar: calendar)
        let window = history.filter { $0.day >= start && $0.day <= end }
        let completedPerDay = window.map { ($0.day, goals.completed(metrics: $0).count) }
        return WellnessReport(
            start: start, end: end,
            daysWithData: window.filter { $0.steps != nil || $0.sleep != nil || $0.restingHeartRate != nil }.count,
            goalsCompleted: completedPerDay.reduce(0) { $0 + $1.1 },
            averageSleepHours: Math.mean(window.compactMap { $0.sleep.map { $0.asleep / 3600 } }),
            averageSteps: Math.mean(window.compactMap(\.steps)),
            averageRestingHR: Math.mean(window.compactMap(\.restingHeartRate)),
            averageHRV: Math.mean(window.compactMap(\.hrv)),
            bestDay: completedPerDay.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
        )
    }
}
