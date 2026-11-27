import Foundation
import HealthKit
import VitalFlowCore

/// Runs a real HKWorkoutSession only while the user is doing something they started —
/// either from the watch or remotely from the iPhone app (`HKHealthStore.startWatchApp`).
/// Live data is mirrored to the iPhone (`startMirroringToCompanionDevice`, watchOS 10).
/// A quick heart-rate check runs for `HeartCheck.duration` seconds, ends by itself and is
/// discarded. VitalFlow never keeps a session alive just to sample sensors.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    enum State { case idle, running, paused, saving }
    enum Mode { case workout, heartCheck }

    var state: State = .idle
    var mode: Mode = .workout
    var activity: WorkoutActivity = .running
    var heartRate: Double?
    var averageHeartRate: Double?
    var activeEnergy: Double = 0
    var distance: Double = 0
    var startDate: Date?
    var lastError: String?
    var heartCheckProgress: Double = 0
    var lastHeartCheck: (bpm: Double, date: Date)?
    var onFinished: (() -> Void)?

    private let store = HealthKitService.shared.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var readings: [(Date, Double)] = []
    private var lastSent = Date.distantPast
    private var heartCheckTask: Task<Void, Never>?

    func start(_ activity: WorkoutActivity) async {
        self.activity = activity
        let config = HKWorkoutConfiguration()
        config.activityType = HealthKitService.hkActivity(activity)
        config.locationType = [.running, .walking, .cycling, .hiking].contains(activity) ? .outdoor : .indoor
        await start(configuration: config)
    }

    func startHeartCheck() async {
        await start(configuration: HeartCheck.configuration())
    }

    /// Entry point for both on-watch starts and iPhone-initiated starts.
    func start(configuration config: HKWorkoutConfiguration) async {
        guard state == .idle else { return }
        mode = HeartCheck.isHeartCheck(config) ? .heartCheck : .workout
        if mode == .workout { activity = HealthKitService.activity(config.activityType) }
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            heartRate = nil; averageHeartRate = nil; activeEnergy = 0; distance = 0
            readings = []; heartCheckProgress = 0
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            state = .running
            // Mirror to the iPhone so it can show live values and pause/end the session.
            try? await session.startMirroringToCompanionDevice()
            if mode == .heartCheck { scheduleHeartCheckEnd(start: start) }
        } catch {
            lastError = error.localizedDescription
            state = .idle
            session = nil
            builder = nil
        }
    }

    private func scheduleHeartCheckEnd(start: Date) {
        heartCheckTask?.cancel()
        heartCheckTask = Task { [weak self] in
            let steps = 40
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(HeartCheck.duration / Double(steps) * 1_000_000_000))
                guard let self, !Task.isCancelled, self.state != .idle else { return }
                self.heartCheckProgress = Double(i) / Double(steps)
                self.sendLive(force: true)
            }
            await self?.finishHeartCheck(start: start)
        }
    }

    private func finishHeartCheck(start: Date) async {
        guard let session, let builder else { return }
        let result = HeartCheck.result(from: readings, start: start)
        if let result {
            lastHeartCheck = (result, Date())
            heartRate = result
        }
        sendLive(force: true, result: result)
        state = .saving
        session.end()
        try? await builder.endCollection(at: Date())
        // A measurement is not a workout: don't add it to the user's workout history.
        builder.discardWorkout()
        self.session = nil
        self.builder = nil
        state = .idle
        mode = .workout
    }

    func togglePause() {
        guard let session else { return }
        if state == .running { session.pause() } else if state == .paused { session.resume() }
    }

    func end() async {
        guard let session, let builder else { return }
        heartCheckTask?.cancel()
        let wasHeartCheck = mode == .heartCheck
        state = .saving
        session.end()
        do {
            try await builder.endCollection(at: Date())
            if wasHeartCheck {
                builder.discardWorkout()
            } else {
                _ = try await builder.finishWorkout()
            }
        } catch {
            lastError = error.localizedDescription
        }
        self.session = nil
        self.builder = nil
        state = .idle
        mode = .workout
        if !wasHeartCheck { onFinished?() }
    }

    /// Ends the local state when the session was ended remotely (from the iPhone).
    fileprivate func handleRemoteEnd() async {
        guard let builder, state != .idle, state != .saving else { return }
        heartCheckTask?.cancel()
        let wasHeartCheck = mode == .heartCheck
        state = .saving
        do {
            try await builder.endCollection(at: Date())
            if wasHeartCheck { builder.discardWorkout() } else { _ = try await builder.finishWorkout() }
        } catch {
            lastError = error.localizedDescription
        }
        session = nil
        self.builder = nil
        state = .idle
        mode = .workout
        if !wasHeartCheck { onFinished?() }
    }

    /// Sends the latest values to the iPhone (at most about once per second).
    fileprivate func sendLive(force: Bool = false, result: Double? = nil) {
        guard let session, force || Date().timeIntervalSince(lastSent) >= 1 else { return }
        lastSent = Date()
        let payload = LiveWorkoutPayload(heartRate: heartRate, averageHeartRate: averageHeartRate,
                                         activeEnergy: activeEnergy, distance: distance,
                                         elapsed: startDate.map { Date().timeIntervalSince($0) } ?? 0,
                                         heartCheckProgress: mode == .heartCheck ? heartCheckProgress : nil,
                                         heartCheckResult: result)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    fileprivate func record(heartRate current: Double?, average: Double?, kcal: Double?, dist: Double?) {
        if let current {
            heartRate = current
            readings.append((Date(), current))
        }
        if let average { averageHeartRate = average }
        if let kcal { activeEnergy = kcal }
        if let dist { distance = dist }
        sendLive()
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: if self.state == .paused { self.state = .running }
            case .paused: self.state = .paused
            case .ended: await self.handleRemoteEnd()
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.lastError = msg }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        let current = collectedTypes.contains(HKQuantityType(.heartRate)) ? hr?.mostRecentQuantity()?.doubleValue(for: bpm) : nil
        let avg = hr?.averageQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let dist = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        Task { @MainActor in
            self.record(heartRate: current, average: avg, kcal: kcal, dist: dist)
        }
    }
}
