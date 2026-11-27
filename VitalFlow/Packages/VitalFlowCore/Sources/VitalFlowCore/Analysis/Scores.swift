import Foundation

/// User settings that influence scores.
public struct ScoringProfile: Codable, Hashable, Sendable {
    /// Sleep need in seconds (default 8 h, user adjustable 6–10 h).
    public var sleepNeed: TimeInterval
    /// Age in years, if the user allowed reading the date of birth; used for max HR.
    public var age: Int?

    public init(sleepNeed: TimeInterval = 8 * 3600, age: Int? = nil) {
        self.sleepNeed = Math.clamp(sleepNeed, 6 * 3600, 10 * 3600)
        self.age = age
    }

    /// Tanaka estimate 208 − 0.7 × age; 185 bpm when age is unknown.
    public var estimatedMaxHR: Double {
        guard let age, age > 10, age < 100 else { return 185 }
        return 208 - 0.7 * Double(age)
    }
}

// MARK: - Sleep score

public enum SleepScorer {
    /// Sleep quality score 0–100. See docs/ALGORITHMS.md §Sleep score.
    public static func score(_ night: SleepNight?, consistency: Int?, profile: ScoringProfile) -> ScoreResult {
        guard let night, night.asleep >= 30 * 60 else { return .notEnoughData(missing: [.sleepLastNight]) }
        var parts: [(String, Double?, Double, Double)] = [] // key, value, subscore 0..100, weight

        let durationScore = Math.ramp(night.asleep / profile.sleepNeed, from: 0.5, 1.0, to: 0, 100)
        parts.append(("duration", night.asleep, durationScore, 0.40))

        let effScore = Math.ramp(night.efficiency, from: 0.70, 0.90, to: 0, 100)
        parts.append(("efficiency", night.efficiency, effScore, 0.20))

        if let r = night.restorativeFraction {
            parts.append(("restorative", r, Math.ramp(r, from: 0.15, 0.40, to: 0, 100), 0.20))
        }
        let intScore = Math.clamp(100 - Double(max(0, night.interruptions - 1)) * 15, 0, 100)
        parts.append(("interruptions", Double(night.interruptions), intScore, 0.10))

        if let consistency {
            parts.append(("consistency", Double(consistency), Double(consistency), 0.10))
        }
        let totalWeight = parts.reduce(0) { $0 + $1.3 }
        let value = parts.reduce(0) { $0 + $1.2 * $1.3 } / totalWeight
        let comps = parts.map {
            ScoreComponent(key: $0.0, value: $0.1, baseline: nil, effect: ($0.2 - 70) / 15, weight: $0.3 / totalWeight)
        }
        let conf: Confidence = night.hasStageData ? (consistency != nil ? .high : .medium) : .low
        return .value(Int(value.rounded()), confidence: conf, components: comps)
    }
}

// MARK: - Recovery

public enum RecoveryScorer {
    public static let weights: [String: Double] = [
        "hrv": 0.45, "restingHeartRate": 0.25, "sleep": 0.20, "respiratoryRate": 0.05, "wristTemperature": 0.05
    ]

    /// Daily recovery score 0–100.
    ///
    /// composite z = Σ wᵢ·eᵢ / Σ wᵢ over available components, where
    ///  e_hrv  = z(ln HRV), e_rhr = −z(RHR), e_sleep = (sleepScore − 70)/15,
    ///  e_resp = −max(0, z(resp)), e_temp = −max(0, |z(temp)| − 1);
    /// each eᵢ clamped to ±3. score = 100 · logistic(0.5 + 1.4 · composite).
    /// Requires HRV *or* RHR with a valid (≥4 day) baseline, and ≥ 0.45 of total weight.
    public static func score(day: DayKey, history: [DailyMetrics], sleepScore: Int?,
                             calendar: Calendar) -> ScoreResult {
        let today = history.first { $0.day == day }
        var comps: [ScoreComponent] = []
        var missing: [DataRequirement] = []

        func add(_ key: String, _ value: Double?, _ baseline: Double?, _ effect: Double) {
            comps.append(ScoreComponent(key: key, value: value, baseline: baseline,
                                        effect: Math.clamp(effect, -3, 3), weight: weights[key] ?? 0))
        }

        let hrvB = BaselineCalculator.hrv(for: day, history: history, calendar: calendar)
        if let v = today?.hrv, v > 0, let b = hrvB {
            add("hrv", v, exp(b.median), b.z(log(v)))
        } else {
            if today?.hrv == nil { missing.append(.hrvToday) }
            if hrvB == nil { missing.append(.hrvBaseline) }
        }
        let rhrB = BaselineCalculator.restingHR(for: day, history: history, calendar: calendar)
        if let v = today?.restingHeartRate, let b = rhrB {
            add("restingHeartRate", v, b.median, -b.z(v))
        } else {
            if today?.restingHeartRate == nil { missing.append(.restingHeartRateToday) }
            if rhrB == nil { missing.append(.restingHeartRateBaseline) }
        }
        let hasCardiac = !comps.isEmpty
        if let s = sleepScore {
            add("sleep", Double(s), nil, (Double(s) - 70) / 15)
        } else {
            missing.append(.sleepLastNight)
        }
        if let v = today?.respiratoryRate,
           let b = BaselineCalculator.respiratory(for: day, history: history, calendar: calendar) {
            add("respiratoryRate", v, b.median, -max(0, b.z(v)))
        }
        if let v = today?.wristTemperature,
           let b = BaselineCalculator.wristTemperature(for: day, history: history, calendar: calendar) {
            add("wristTemperature", v, b.median, -max(0, abs(b.z(v)) - 1))
        }

        let totalWeight = comps.reduce(0) { $0 + $1.weight }
        guard hasCardiac, totalWeight >= 0.45 - 1e-9 else {
            return .notEnoughData(missing: missing.isEmpty ? [.hrvBaseline] : missing)
        }
        let composite = comps.reduce(0) { $0 + $1.weight * $1.effect } / totalWeight
        let value = Int((100 * Math.logistic(0.5 + 1.4 * composite)).rounded())
        for i in comps.indices { comps[i].weight /= totalWeight }

        let baselineConf = [hrvB?.confidence, rhrB?.confidence].compactMap { $0 }.max() ?? .low
        var conf = baselineConf
        if totalWeight < 0.65 { conf = min(conf, .low) } else if totalWeight < 0.85 { conf = min(conf, .medium) }
        return .value(Math.clamp(value, 0, 100), confidence: conf, components: comps)
    }
}

// MARK: - Stress

public struct HourlyStress: Codable, Hashable, Sendable {
    public var hourStart: Date
    public var level: Int
}

public struct StressReport: Codable, Hashable, Sendable {
    public var result: ScoreResult
    public var hourly: [HourlyStress]
}

public enum StressEstimator {
    /// Daytime stress estimate 0–100 from heart rate elevation at low movement
    /// (+ daytime HRV when present). See docs/ALGORITHMS.md §Stress.
    ///
    /// Per hour h (excluding hours overlapping workouts and hours with > 1 200 steps):
    ///   hrStress  = 100 · (median HR − RHR_base) / (0.35 · (HRmax − RHR_base)), clamped 0…100
    ///   hrvStress = 50 − 25 · z(ln HRV_h)   (if HRV samples in that hour)
    ///   level     = 0.6·hrStress + 0.4·hrvStress   or hrStress alone
    /// Daily value = mean of valid hours; needs ≥ 3 valid hours and an RHR baseline.
    public static func estimate(day: DayKey, heartRate: [QuantitySample], hrv: [QuantitySample],
                                steps: [QuantitySample], workouts: [WorkoutRecord],
                                history: [DailyMetrics], profile: ScoringProfile,
                                calendar: Calendar, now: Date = Date()) -> StressReport {
        guard let rhrB = BaselineCalculator.restingHR(for: day, history: history, calendar: calendar) else {
            return StressReport(result: .notEnoughData(missing: [.restingHeartRateBaseline]), hourly: [])
        }
        let hrvB = BaselineCalculator.hrv(for: day, history: history, calendar: calendar)
        let reserve = max(20, profile.estimatedMaxHR - rhrB.median)
        let dayStart = day.startDate(in: calendar)
        let hr = Deduplicator.dedupeDiscrete(heartRate)
        let hrvSamples = Deduplicator.dedupeDiscrete(hrv)

        var hourly: [HourlyStress] = []
        for h in 7..<23 {
            guard let a = calendar.date(byAdding: .hour, value: h, to: dayStart),
                  let b = calendar.date(byAdding: .hour, value: h + 1, to: dayStart), b <= now else { continue }
            if workouts.contains(where: { $0.start < b && $0.end > a }) { continue }
            let stepsInHour = Deduplicator.mergedCumulativeTotal(steps, start: a, end: b)
            if stepsInHour > 1_200 { continue }
            let values = hr.filter { $0.start >= a && $0.start < b }.map(\.value)
            guard values.count >= 2, let med = Math.median(values) else { continue }
            let hrStress = Math.clamp(100 * (med - rhrB.median) / (0.35 * reserve), 0, 100)
            var level = hrStress
            let hv = hrvSamples.filter { $0.start >= a && $0.start < b }.map(\.value).filter { $0 > 0 }
            if let hrvB, let m = Math.mean(hv) {
                let hrvStress = Math.clamp(50 - 25 * hrvB.z(log(m)), 0, 100)
                level = 0.6 * hrStress + 0.4 * hrvStress
            }
            hourly.append(HourlyStress(hourStart: a, level: Int(level.rounded())))
        }
        guard hourly.count >= 3, let avg = Math.mean(hourly.map { Double($0.level) }) else {
            return StressReport(result: .notEnoughData(missing: [.heartRateToday]), hourly: hourly)
        }
        let conf: Confidence = hourly.count >= 8 ? min(.high, rhrB.confidence == .high ? .high : .medium) : .low
        let comps = [ScoreComponent(key: "validHours", value: Double(hourly.count), baseline: rhrB.median, effect: 0, weight: 1)]
        return StressReport(result: .value(Int(avg.rounded()), confidence: conf, components: comps), hourly: hourly)
    }
}

// MARK: - Body Battery

public struct BatteryPoint: Codable, Hashable, Sendable {
    public var time: Date
    public var level: Double
}

public struct BodyBatteryReport: Codable, Hashable, Sendable {
    public var result: ScoreResult
    public var morningLevel: Int?
    public var timeline: [BatteryPoint]
}

public enum BodyBatteryEstimator {
    /// Body Battery 0–100: an energy-reservoir model.
    ///   morning = clamp(0.6·recovery + 0.4·sleepScore, 5, 100) (either alone if one is missing)
    ///   per awake hour: −2.0 baseline, −0.04/kcal active energy, −(stress−50)/25 when stress>50,
    ///                   +0.5 during calm hours (stress < 25, < 300 steps).
    public static func estimate(recovery: Int?, sleepScore: Int?, wakeTime: Date?,
                                hourlyActiveEnergy: [(Date, Double)], hourlyStress: [HourlyStress],
                                hourlySteps: [(Date, Double)], now: Date, calendar: Calendar) -> BodyBatteryReport {
        let morning: Double
        switch (recovery, sleepScore) {
        case let (r?, s?): morning = 0.6 * Double(r) + 0.4 * Double(s)
        case let (r?, nil): morning = Double(r)
        case let (nil, s?): morning = Double(s) * 0.9
        default:
            return BodyBatteryReport(result: .notEnoughData(missing: [.recoveryScore, .sleepLastNight]), morningLevel: nil, timeline: [])
        }
        var level = Math.clamp(morning, 5, 100)
        let start = wakeTime ?? calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        var timeline = [BatteryPoint(time: start, level: level)]
        var t = start
        let energyBy = Dictionary(hourlyActiveEnergy.map { (calendar.dateInterval(of: .hour, for: $0.0)?.start ?? $0.0, $0.1) }, uniquingKeysWith: +)
        let stepsBy = Dictionary(hourlySteps.map { (calendar.dateInterval(of: .hour, for: $0.0)?.start ?? $0.0, $0.1) }, uniquingKeysWith: +)
        let stressBy = Dictionary(hourlyStress.map { ($0.hourStart, $0.level) }, uniquingKeysWith: { a, _ in a })
        while t < now {
            let next = min(now, t.addingTimeInterval(3600))
            let fraction = next.timeIntervalSince(t) / 3600
            let hourKey = calendar.dateInterval(of: .hour, for: t)?.start ?? t
            var delta = -2.0 * fraction
            delta -= 0.04 * (energyBy[hourKey] ?? 0) * fraction
            if let s = stressBy[hourKey] {
                if s > 50 { delta -= Double(s - 50) / 25 * fraction }
                if s < 25, (stepsBy[hourKey] ?? 0) < 300 { delta += 0.5 * fraction }
            }
            level = Math.clamp(level + delta, 0, 100)
            t = next
            timeline.append(BatteryPoint(time: t, level: level))
        }
        let conf: Confidence = (recovery != nil && sleepScore != nil) ? .medium : .low
        let comps = [
            ScoreComponent(key: "morningCharge", value: morning, baseline: nil, effect: 0, weight: 1)
        ]
        return BodyBatteryReport(result: .value(Int(level.rounded()), confidence: conf, components: comps),
                                 morningLevel: Int(Math.clamp(morning, 5, 100).rounded()), timeline: timeline)
    }
}

// MARK: - Training load, readiness and balance

public enum TrainingLoad {
    /// Banister TRIMP: minutes · HRr · 0.64 · e^(1.92·HRr), HRr = (avgHR − RHR)/(HRmax − RHR).
    /// Without heart rate: active kcal / 8. Without either: minutes × 0.5.
    public static func load(of w: WorkoutRecord, restingHR: Double?, profile: ScoringProfile) -> Double {
        let minutes = w.duration / 60
        if let avg = w.averageHeartRate, let rhr = restingHR {
            let hrr = Math.clamp((avg - rhr) / max(20, profile.estimatedMaxHR - rhr), 0, 1)
            return minutes * hrr * 0.64 * exp(1.92 * hrr)
        }
        if let kcal = w.activeEnergy { return kcal / 8 }
        return minutes * 0.5
    }

    public static func dailyLoad(day: DayKey, workouts: [WorkoutRecord], restingHR: Double?,
                                 profile: ScoringProfile, calendar: Calendar) -> Double {
        var seen = Set<String>()
        return workouts
            .filter { DayKey($0.start, calendar: calendar) == day && seen.insert($0.id).inserted }
            .reduce(0) { $0 + load(of: $1, restingHR: restingHR, profile: profile) }
    }
}

public enum BalanceZone: String, Codable, Sendable {
    case underTraining, optimal, high, veryHigh
}

public enum TrainingReadinessLevel: String, Codable, Sendable {
    case prime, moderate, easy, rest
}

public struct TrainingReadiness: Codable, Hashable, Sendable {
    public var result: ScoreResult
    public var level: TrainingReadinessLevel?
    public var acwr: Double?
    public var zone: BalanceZone?
    public var acuteLoad: Double?
    public var chronicLoad: Double?
}

public enum ReadinessCalculator {
    /// Acute:chronic workload ratio — 7-day mean load / 28-day mean load.
    /// Needs ≥ 14 days of history in the 28-day window and chronic load > 0.
    public static func acwr(day: DayKey, history: [DailyMetrics], calendar: Calendar) -> (acwr: Double, acute: Double, chronic: Double)? {
        let start28 = day.adding(days: -27, calendar: calendar)
        let start7 = day.adding(days: -6, calendar: calendar)
        let window = history.filter { $0.day >= start28 && $0.day <= day }
        guard window.count >= 14 else { return nil }
        let chronic = window.reduce(0) { $0 + ($1.trainingLoad ?? 0) } / 28
        let acute = window.filter { $0.day >= start7 }.reduce(0) { $0 + ($1.trainingLoad ?? 0) } / 7
        guard chronic > 0.5 else { return nil }
        return (acute / chronic, acute, chronic)
    }

    public static func zone(_ r: Double) -> BalanceZone {
        switch r {
        case ..<0.8: return .underTraining
        case 0.8...1.3: return .optimal
        case 1.3...1.5: return .high
        default: return .veryHigh
        }
    }

    public static func balanceScore(_ r: Double) -> Double {
        switch r {
        case ..<0.8: return 75
        case 0.8...1.3: return 100
        case 1.3...1.6: return Math.ramp(r, from: 1.3, 1.6, to: 100, 40)
        default: return Math.ramp(r, from: 1.6, 2.0, to: 40, 20)
        }
    }

    /// readiness = 0.65·recovery + 0.35·balanceScore (recovery alone when load history is short).
    public static func readiness(day: DayKey, recovery: ScoreResult, history: [DailyMetrics], calendar: Calendar) -> TrainingReadiness {
        guard let rec = recovery.score else {
            return TrainingReadiness(result: .notEnoughData(missing: [.recoveryScore]))
        }
        var comps = [ScoreComponent(key: "recovery", value: Double(rec), baseline: nil, effect: 0, weight: 0.65)]
        var value = Double(rec)
        var conf = min(recovery.confidence ?? .low, .high)
        var out = TrainingReadiness(result: .notEnoughData(missing: []))
        if let a = acwr(day: day, history: history, calendar: calendar) {
            let bs = balanceScore(a.acwr)
            value = 0.65 * Double(rec) + 0.35 * bs
            comps.append(ScoreComponent(key: "loadBalance", value: a.acwr, baseline: 1.0, effect: 0, weight: 0.35))
            out.acwr = a.acwr; out.zone = zone(a.acwr); out.acuteLoad = a.acute; out.chronicLoad = a.chronic
        } else {
            comps[0].weight = 1
            conf = min(conf, .low)
        }
        let v = Int(value.rounded())
        out.result = .value(v, confidence: conf, components: comps)
        out.level = v >= 75 ? .prime : v >= 50 ? .moderate : v >= 30 ? .easy : .rest
        return out
    }
}

public enum ActivityRecoveryBalance: String, Codable, Sendable {
    case roomToPush      // recovered, low load
    case balanced
    case overreaching    // heavy load while recovery is low
    case restDay         // low recovery, low load — good choice
}

public enum BalanceCalculator {
    /// Activity load 0–100 for today relative to the user's chronic load:
    /// 100 · (1 − e^(−load / (1.5 · max(chronic, 20)))).
    public static func activityLoadScore(todayLoad: Double, chronic: Double?) -> Int {
        let ref = 1.5 * max(chronic ?? 20, 20)
        return Int((100 * (1 - exp(-todayLoad / ref))).rounded())
    }

    public static func balance(recovery: Int?, activityLoad: Int) -> ActivityRecoveryBalance? {
        guard let recovery else { return nil }
        let diff = activityLoad - recovery
        if diff > 25 { return .overreaching }
        if recovery < 40 && activityLoad < 40 { return .restDay }
        if diff < -35 { return .roomToPush }
        return .balanced
    }
}
