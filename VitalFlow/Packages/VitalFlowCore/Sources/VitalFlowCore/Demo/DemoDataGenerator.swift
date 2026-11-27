import Foundation

/// Deterministic pseudo-random generator (SplitMix64) so demo data is reproducible.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * Double(next() >> 11) / Double(1 << 53)
    }
    public mutating func normal(_ mean: Double, _ sd: Double) -> Double {
        let u1 = max(1e-12, uniform(0, 1)), u2 = uniform(0, 1)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

public struct DemoDataset: Sendable {
    public var quantities: [QuantitySample]
    public var sleep: [SleepSample]
    public var workouts: [WorkoutRecord]
}

/// DEMONSTRATION MODE ONLY. Generates a clearly labelled synthetic dataset for screenshots,
/// UI testing and the Simulator (which has no Apple Watch). Production code paths never call
/// this; the app shows a persistent "Demo data" banner whenever it is active.
public enum DemoDataGenerator {
    public static let sourceID = "com.vitalflow.demo"

    public static func generate(days: Int, endingAt now: Date, calendar: Calendar, seed: UInt64 = 42) -> DemoDataset {
        var rng = SeededRandom(seed: seed)
        var q: [QuantitySample] = []
        var sleep: [SleepSample] = []
        var workouts: [WorkoutRecord] = []
        let today = DayKey(now, calendar: calendar)

        func sample(_ kind: MetricKind, _ v: Double, _ s: Date, _ e: Date? = nil) {
            if s <= now { q.append(QuantitySample(kind: kind, value: v, start: s, end: min(e ?? s, now), sourceID: sourceID, isFromWatch: true)) }
        }

        for offset in stride(from: days - 1, through: 0, by: -1) {
            let day = today.adding(days: -offset, calendar: calendar)
            let dayStart = day.startDate(in: calendar)
            let fatigue = sin(Double(offset) / 3.0) * 0.8 + rng.normal(0, 0.4) // slow wave + noise

            // Night ending this morning.
            let bed = dayStart.addingTimeInterval(-3600 * rng.uniform(0.3, 1.6))  // 22:24–23:42
            var t = bed
            let target = 3600 * Math.clamp(rng.normal(7.4 - fatigue * 0.4, 0.5), 5.0, 9.0)
            var asleep = 0.0
            var cycle = 0
            while asleep < target {
                let stages: [(SleepStage, Double)] = [
                    (.core, rng.uniform(20, 40)), (.deep, max(5, rng.uniform(25, 45) - Double(cycle) * 7)),
                    (.core, rng.uniform(10, 20)), (.rem, rng.uniform(10, 18) + Double(cycle) * 6)
                ]
                for (stage, minutes) in stages {
                    let e = t.addingTimeInterval(minutes * 60)
                    sleep.append(SleepSample(stage: stage, start: t, end: e, sourceID: sourceID, isFromWatch: true))
                    asleep += minutes * 60
                    t = e
                }
                if rng.uniform(0, 1) < 0.35 {
                    let e = t.addingTimeInterval(rng.uniform(2, 8) * 60)
                    sleep.append(SleepSample(stage: .awake, start: t, end: e, sourceID: sourceID, isFromWatch: true))
                    t = e
                }
                cycle += 1
            }
            let wake = t
            // Nightly HRV, respiratory rate, wrist temperature, SpO2.
            let hrvNight = exp(rng.normal(log(52) - fatigue * 0.12, 0.05))
            var h = bed.addingTimeInterval(1800)
            while h < wake {
                sample(.hrvSDNN, max(10, rng.normal(hrvNight, 6)), h)
                sample(.respiratoryRate, rng.normal(14.2 + fatigue * 0.3, 0.4), h)
                sample(.oxygenSaturation, Math.clamp(rng.normal(0.965, 0.01), 0.9, 1), h)
                sample(.heartRate, rng.normal(54 + fatigue * 2, 3), h)
                h = h.addingTimeInterval(3600)
            }
            sample(.wristTemperature, rng.normal(34.6 + fatigue * 0.08, 0.1), wake)
            sample(.restingHeartRate, rng.normal(56 + fatigue * 2.2, 0.8), dayStart.addingTimeInterval(9 * 3600))

            // Daytime.
            let isWorkoutDay = rng.uniform(0, 1) < 0.5
            let workoutHour = Int(rng.uniform(7, 19))
            for hour in 7..<23 {
                let a = dayStart.addingTimeInterval(Double(hour) * 3600)
                let b = a.addingTimeInterval(3600)
                guard a < now else { break }
                let inWorkout = isWorkoutDay && hour == workoutHour
                let steps = inWorkout ? rng.uniform(4000, 6500) : max(0, rng.normal(450, 300))
                sample(.stepCount, steps, a, b)
                sample(.distanceWalkingRunning, steps * 0.75, a, b)
                sample(.activeEnergy, inWorkout ? rng.uniform(350, 520) : max(5, steps * 0.04 + rng.normal(10, 4)), a, b)
                sample(.basalEnergy, 68, a, b)
                if inWorkout { sample(.exerciseMinutes, rng.uniform(35, 55), a, b) }
                else if rng.uniform(0, 1) < 0.2 { sample(.exerciseMinutes, rng.uniform(3, 10), a, b) }
                if hour >= 9 && hour <= 17 && rng.uniform(0, 1) < 0.45 { sample(.timeInDaylight, rng.uniform(5, 25), a, b) }
                if hour % 2 == 0 && rng.uniform(0, 1) < 0.7 { sample(.dietaryWater, 250, a.addingTimeInterval(600)) }
                let stressBump = (hour >= 10 && hour <= 15 ? 8 : 0) + fatigue * 3
                for m in stride(from: 0, to: 60, by: 10) {
                    let hrBase = inWorkout ? 145 : 70 + stressBump
                    sample(.heartRate, rng.normal(hrBase, 5), a.addingTimeInterval(Double(m) * 60))
                }
                if rng.uniform(0, 1) < 0.15 { sample(.hrvSDNN, max(10, rng.normal(hrvNight * 0.8, 8)), a.addingTimeInterval(1500)) }
                if inWorkout {
                    let activity: WorkoutActivity = [.running, .cycling, .strength, .walking, .hiit][Int(rng.uniform(0, 4.99))]
                    let s = a.addingTimeInterval(300), e = s.addingTimeInterval(rng.uniform(35, 55) * 60)
                    if e <= now {
                        workouts.append(WorkoutRecord(activity: activity, start: s, end: e, activeEnergy: rng.uniform(320, 520),
                                                      distance: activity == .strength ? nil : rng.uniform(4000, 12000),
                                                      averageHeartRate: rng.normal(142, 6), maxHeartRate: rng.normal(172, 5),
                                                      sourceID: sourceID))
                    }
                }
            }
            if offset % 7 == 0 { sample(.vo2Max, rng.normal(44, 0.4), dayStart.addingTimeInterval(19 * 3600)) }
            if offset % 3 == 0 { sample(.bodyMass, rng.normal(70, 0.3), dayStart.addingTimeInterval(7.5 * 3600)) }
        }
        return DemoDataset(quantities: q, sleep: sleep.filter { $0.start < now }, workouts: workouts)
    }
}
