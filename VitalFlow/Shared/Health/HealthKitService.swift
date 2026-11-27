import Foundation
import HealthKit
import VitalFlowCore

/// Thin, testable wrapper around HealthKit. Converts HealthKit objects into
/// platform-neutral VitalFlowCore models. Never fabricates values: anything that
/// can't be read (unsupported device, denied permission, no samples) becomes `nil`/empty.
final class HealthKitService: @unchecked Sendable {
    static let shared = HealthKitService()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Types

    static func quantityType(_ kind: MetricKind) -> HKQuantityType {
        switch kind {
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .hrvSDNN: return HKQuantityType(.heartRateVariabilitySDNN)
        case .oxygenSaturation: return HKQuantityType(.oxygenSaturation)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .wristTemperature: return HKQuantityType(.appleSleepingWristTemperature)
        case .stepCount: return HKQuantityType(.stepCount)
        case .distanceWalkingRunning: return HKQuantityType(.distanceWalkingRunning)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .basalEnergy: return HKQuantityType(.basalEnergyBurned)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .timeInDaylight: return HKQuantityType(.timeInDaylight)
        case .bodyMass: return HKQuantityType(.bodyMass)
        case .dietaryWater: return HKQuantityType(.dietaryWater)
        }
    }

    static func unit(_ kind: MetricKind) -> HKUnit {
        switch kind {
        case .heartRate, .restingHeartRate, .respiratoryRate: return HKUnit.count().unitDivided(by: .minute())
        case .hrvSDNN: return .secondUnit(with: .milli)
        case .oxygenSaturation: return .percent()
        case .wristTemperature: return .degreeCelsius()
        case .stepCount: return .count()
        case .distanceWalkingRunning: return .meter()
        case .activeEnergy, .basalEnergy: return .kilocalorie()
        case .exerciseMinutes, .timeInDaylight: return .minute()
        case .vo2Max: return HKUnit(from: "ml/kg*min")
        case .bodyMass: return .gramUnit(with: .kilo)
        case .dietaryWater: return .literUnit(with: .milli)
        }
    }

    static var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>(MetricKind.allCases.map { quantityType($0) })
        s.insert(HKCategoryType(.sleepAnalysis))
        s.insert(HKObjectType.workoutType())
        s.insert(HKObjectType.activitySummaryType())
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { s.insert(dob) }
        return s
    }

    static var shareTypes: Set<HKSampleType> {
        #if os(watchOS)
        return [HKQuantityType(.dietaryWater), HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning)]
        #else
        return [HKQuantityType(.dietaryWater)]
        #endif
    }

    // MARK: Authorization

    /// Shows the system permission sheet. HealthKit never reveals whether *read* access was
    /// granted, so callers must treat "no data" and "denied" the same way ("Not enough data").
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    func canWriteWater() -> Bool {
        store.authorizationStatus(for: HKQuantityType(.dietaryWater)) == .sharingAuthorized
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Health data is not available on this device.") }
    }

    // MARK: Reading

    private static func isWatch(_ s: HKSample) -> Bool {
        (s.sourceRevision.productType ?? "").hasPrefix("Watch") || (s.device?.model ?? "") == "Watch"
    }

    func quantitySamples(_ kind: MetricKind, start: Date, end: Date, limit: Int? = nil) async -> [QuantitySample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.quantityType(kind), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: limit)
        do {
            let unit = Self.unit(kind)
            return try await descriptor.result(for: store).map { s in
                QuantitySample(id: s.uuid.uuidString, kind: kind, value: s.quantity.doubleValue(for: unit),
                               start: s.startDate, end: s.endDate,
                               sourceID: s.sourceRevision.source.bundleIdentifier, isFromWatch: Self.isWatch(s))
            }
        } catch {
            return []
        }
    }

    /// Daily statistics. For cumulative metrics HealthKit merges overlapping sources by the
    /// user's source priority, which is the correct de-duplication for steps, energy, etc.
    func dailyStatistics(_ kind: MetricKind, days: [DayKey], calendar: Calendar) async -> [DayKey: Double] {
        guard isAvailable, let first = days.min(), let last = days.max() else { return [:] }
        let start = first.startDate(in: calendar), end = last.endDate(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: Self.quantityType(kind), predicate: predicate),
            options: kind.isCumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1))
        do {
            let collection = try await descriptor.result(for: store)
            let unit = Self.unit(kind)
            var out: [DayKey: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                let q = kind.isCumulative ? stats.sumQuantity() : stats.averageQuantity()
                if let v = q?.doubleValue(for: unit) {
                    out[DayKey(stats.startDate, calendar: calendar)] = v
                }
            }
            return out
        } catch {
            return [:]
        }
    }

    func sleepSamples(start: Date, end: Date) async -> [SleepSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            return try await descriptor.result(for: store).compactMap { s in
                guard let stage = Self.sleepStage(s.value) else { return nil }
                return SleepSample(id: s.uuid.uuidString, stage: stage, start: s.startDate, end: s.endDate,
                                   sourceID: s.sourceRevision.source.bundleIdentifier, isFromWatch: Self.isWatch(s))
            }
        } catch {
            return []
        }
    }

    static func sleepStage(_ raw: Int) -> SleepStage? {
        // Imported C enums accept any raw value, so match explicitly and ignore unknown values
        // instead of guessing a stage.
        switch raw {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .asleepUnspecified
        default: return nil
        }
    }

    func workouts(start: Date, end: Date) async -> [WorkoutRecord] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        do {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            return try await descriptor.result(for: store).map { w in
                let hr = w.statistics(for: HKQuantityType(.heartRate))
                return WorkoutRecord(id: w.uuid.uuidString, activity: Self.activity(w.workoutActivityType),
                                     start: w.startDate, end: w.endDate,
                                     activeEnergy: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                                     distance: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()),
                                     averageHeartRate: hr?.averageQuantity()?.doubleValue(for: bpm),
                                     maxHeartRate: hr?.maximumQuantity()?.doubleValue(for: bpm),
                                     sourceID: w.sourceRevision.source.bundleIdentifier)
            }
        } catch {
            return []
        }
    }

    static func activity(_ t: HKWorkoutActivityType) -> WorkoutActivity {
        switch t {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .hiking: return .hiking
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        case .highIntensityIntervalTraining: return .hiit
        case .yoga: return .yoga
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        default: return .other
        }
    }

    static func hkActivity(_ a: WorkoutActivity) -> HKWorkoutActivityType {
        switch a {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .hiking: return .hiking
        case .strength: return .traditionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .yoga: return .yoga
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .other: return .other
        }
    }

    func age(now: Date = Date()) -> Int? {
        guard let dob = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: now).year
    }

    // MARK: Writing

    func logWater(milliliters: Double, at date: Date = Date()) async throws {
        let q = HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters)
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater), quantity: q, start: date, end: date)
        try await store.save(sample)
    }

    // MARK: Change notifications

    /// Observes changes to the metrics that drive scores. On iOS, background delivery wakes the
    /// app at most hourly (system-controlled), which also covers Watch→iPhone sync delays.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        guard isAvailable else { return }
        let types: [HKSampleType] = [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRateVariabilitySDNN),
                                     HKQuantityType(.restingHeartRate), HKObjectType.workoutType()]
        for type in types {
            let q = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { onChange() }
                completion()
            }
            store.execute(q)
            #if os(iOS)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            #endif
        }
    }
}
