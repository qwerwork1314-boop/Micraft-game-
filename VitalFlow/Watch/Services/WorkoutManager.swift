import Foundation
import HealthKit
import VitalFlowCore

/// Runs a real HKWorkoutSession only while the user is doing a workout they started.
/// Live heart rate comes from the workout builder. The session always ends when the user
/// taps End; VitalFlow never keeps a session alive just to sample sensors.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    enum State { case idle, running, paused, saving }

    var state: State = .idle
    var activity: WorkoutActivity = .running
    var heartRate: Double?
    var averageHeartRate: Double?
    var activeEnergy: Double = 0
    var distance: Double = 0
    var startDate: Date?
    var lastError: String?
    var onFinished: (() -> Void)?

    private let store = HealthKitService.shared.store
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start(_ activity: WorkoutActivity) async {
        self.activity = activity
        let config = HKWorkoutConfiguration()
        config.activityType = HealthKitService.hkActivity(activity)
        config.locationType = [.running, .walking, .cycling, .hiking].contains(activity) ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            heartRate = nil; averageHeartRate = nil; activeEnergy = 0; distance = 0
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            state = .running
        } catch {
            lastError = error.localizedDescription
            state = .idle
        }
    }

    func togglePause() {
        guard let session else { return }
        if state == .running { session.pause() } else if state == .paused { session.resume() }
    }

    func end() async {
        guard let session, let builder else { return }
        state = .saving
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
        } catch {
            lastError = error.localizedDescription
        }
        self.session = nil
        self.builder = nil
        state = .idle
        onFinished?()
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: self.state = .running
            case .paused: self.state = .paused
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
        let current = hr?.mostRecentQuantity()?.doubleValue(for: bpm)
        let avg = hr?.averageQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let dist = workoutBuilder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        Task { @MainActor in
            if let current { self.heartRate = current }
            if let avg { self.averageHeartRate = avg }
            if let kcal { self.activeEnergy = kcal }
            if let dist { self.distance = dist }
        }
    }
}
