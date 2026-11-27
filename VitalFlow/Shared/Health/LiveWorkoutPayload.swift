import Foundation
import HealthKit

/// Live values the Apple Watch sends to the iPhone through the mirrored workout session.
struct LiveWorkoutPayload: Codable, Equatable {
    var heartRate: Double?
    var averageHeartRate: Double?
    var activeEnergy: Double
    var distance: Double
    var elapsed: TimeInterval
    /// 0…1 while a quick heart-rate check is measuring.
    var heartCheckProgress: Double?
    /// Final result of a quick heart-rate check (bpm).
    var heartCheckResult: Double?
}

/// A quick heart-rate check is a short, user-started measurement session on the watch.
/// It is identified by the `.mindAndBody` activity type, which VitalFlow's workout list never
/// uses, runs for `duration` seconds, then ends automatically and is discarded (not saved
/// as a workout). It never keeps running in the background.
enum HeartCheck {
    static let activityType: HKWorkoutActivityType = .mindAndBody
    static let duration: TimeInterval = 40
    static let warmUp: TimeInterval = 10

    static func configuration() -> HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        c.activityType = activityType
        c.locationType = .indoor
        return c
    }

    static func isHeartCheck(_ c: HKWorkoutConfiguration) -> Bool { c.activityType == activityType }

    /// Median of readings after the warm-up, rounded. nil when there are too few readings.
    static func result(from readings: [(Date, Double)], start: Date) -> Double? {
        let settled = readings.filter { $0.0.timeIntervalSince(start) >= warmUp }.map(\.1).sorted()
        let use = settled.count >= 3 ? settled : readings.map(\.1).sorted()
        guard use.count >= 3 else { return nil }
        return use[use.count / 2].rounded()
    }
}
