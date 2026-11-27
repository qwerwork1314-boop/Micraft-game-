import Foundation

/// Every metric VitalFlow reads. The raw values map 1:1 to HealthKit identifiers
/// in the app layer (see `HealthKitTypes.swift`), but this package never imports HealthKit.
public enum MetricKind: String, Codable, CaseIterable, Sendable {
    case heartRate              // count/min, discrete
    case restingHeartRate       // count/min, discrete (one per day, computed by Apple)
    case hrvSDNN                // ms, discrete
    case oxygenSaturation       // fraction 0...1, discrete
    case respiratoryRate        // count/min, discrete
    case wristTemperature       // degC (absolute sleeping wrist temperature), discrete
    case stepCount              // count, cumulative
    case distanceWalkingRunning // meters, cumulative
    case activeEnergy           // kcal, cumulative
    case basalEnergy            // kcal, cumulative
    case exerciseMinutes        // minutes, cumulative
    case vo2Max                 // ml/(kg*min), discrete
    case timeInDaylight         // minutes, cumulative
    case bodyMass               // kg, discrete
    case dietaryWater           // ml, cumulative

    /// Cumulative metrics are summed per day; discrete metrics are averaged/sampled.
    public var isCumulative: Bool {
        switch self {
        case .stepCount, .distanceWalkingRunning, .activeEnergy, .basalEnergy,
             .exerciseMinutes, .timeInDaylight, .dietaryWater:
            return true
        default:
            return false
        }
    }
}

/// A platform-neutral quantity sample.
public struct QuantitySample: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: MetricKind
    public var value: Double
    public var start: Date
    public var end: Date
    /// Stable source identifier (HealthKit bundle identifier).
    public var sourceID: String
    /// `true` when the sample was recorded by an Apple Watch. Used for source priority.
    public var isFromWatch: Bool

    public init(id: String = UUID().uuidString, kind: MetricKind, value: Double,
                start: Date, end: Date? = nil, sourceID: String = "unknown", isFromWatch: Bool = false) {
        self.id = id
        self.kind = kind
        self.value = value
        self.start = start
        self.end = end ?? start
        self.sourceID = sourceID
        self.isFromWatch = isFromWatch
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Sleep stages as recorded by HealthKit's `HKCategoryValueSleepAnalysis`.
public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, core, deep, rem

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: return true
        case .inBed, .awake: return false
        }
    }

    /// Conflict-resolution priority inside one source when samples overlap.
    /// Awake wins (conservative: never over-count sleep), then the most specific stage.
    public var priority: Int {
        switch self {
        case .awake: return 6
        case .deep: return 5
        case .rem: return 4
        case .core: return 3
        case .asleepUnspecified: return 2
        case .inBed: return 1
        }
    }

    public var isStaged: Bool { self == .core || self == .deep || self == .rem }
}

public struct SleepSample: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public var sourceID: String
    public var isFromWatch: Bool

    public init(id: String = UUID().uuidString, stage: SleepStage, start: Date, end: Date,
                sourceID: String = "unknown", isFromWatch: Bool = false) {
        self.id = id
        self.stage = stage
        self.start = start
        self.end = end
        self.sourceID = sourceID
        self.isFromWatch = isFromWatch
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

public enum WorkoutActivity: String, Codable, CaseIterable, Sendable {
    case running, walking, cycling, swimming, hiking, strength, hiit, yoga, rowing, elliptical, other
}

public struct WorkoutRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var activity: WorkoutActivity
    public var start: Date
    public var end: Date
    public var activeEnergy: Double?      // kcal
    public var distance: Double?          // meters
    public var averageHeartRate: Double?  // bpm
    public var maxHeartRate: Double?      // bpm
    public var sourceID: String

    public init(id: String = UUID().uuidString, activity: WorkoutActivity, start: Date, end: Date,
                activeEnergy: Double? = nil, distance: Double? = nil, averageHeartRate: Double? = nil,
                maxHeartRate: Double? = nil, sourceID: String = "unknown") {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.activeEnergy = activeEnergy
        self.distance = distance
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.sourceID = sourceID
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Calendar day identifier that is independent of time zone once created.
public struct DayKey: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Local midnight that starts this day.
    public func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// Local midnight that ends this day (handles 23h/25h DST days).
    public func endDate(in calendar: Calendar) -> Date {
        let s = startDate(in: calendar)
        return calendar.date(byAdding: .day, value: 1, to: s) ?? s.addingTimeInterval(86_400)
    }

    public func adding(days: Int, calendar: Calendar) -> DayKey {
        let d = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar).addingTimeInterval(43_200)) ?? Date()
        return DayKey(d, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

/// One merged, non-overlapping sleep interval.
public struct SleepSegment: Codable, Hashable, Sendable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }
}

/// The analysed main sleep of one night, attributed to the day the user woke up.
public struct SleepNight: Codable, Hashable, Sendable {
    public var wakeDay: DayKey
    public var segments: [SleepSegment]
    public var start: Date
    public var end: Date
    public var asleep: TimeInterval
    public var awake: TimeInterval
    public var deep: TimeInterval
    public var rem: TimeInterval
    public var core: TimeInterval
    public var unspecified: TimeInterval
    public var interruptions: Int
    public var napDuration: TimeInterval
    public var hasStageData: Bool
    public var primarySourceID: String?

    public var timeInBed: TimeInterval { max(0, end.timeIntervalSince(start)) }
    public var efficiency: Double { timeInBed > 0 ? min(1, asleep / timeInBed) : 0 }
    public var midpoint: Date { start.addingTimeInterval(timeInBed / 2) }
    public var restorativeFraction: Double? {
        guard hasStageData, asleep > 0 else { return nil }
        return (deep + rem) / asleep
    }
}

/// Aggregated values for a single calendar day. `nil` always means "no measurement".
public struct DailyMetrics: Codable, Hashable, Sendable {
    public var day: DayKey
    public var restingHeartRate: Double?
    public var hrv: Double?                 // ms, nightly average preferred
    public var averageHeartRate: Double?
    public var oxygenSaturation: Double?    // 0...1
    public var respiratoryRate: Double?
    public var wristTemperature: Double?    // degC absolute
    public var steps: Double?
    public var distance: Double?            // m
    public var activeEnergy: Double?        // kcal
    public var basalEnergy: Double?         // kcal
    public var exerciseMinutes: Double?
    public var daylightMinutes: Double?
    public var waterML: Double?
    public var bodyMass: Double?
    public var vo2Max: Double?
    public var sleep: SleepNight?
    public var trainingLoad: Double?        // TRIMP-like arbitrary units

    public init(day: DayKey) { self.day = day }
}
