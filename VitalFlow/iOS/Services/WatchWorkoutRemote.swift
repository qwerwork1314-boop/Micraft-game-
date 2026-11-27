import Foundation
import HealthKit
import WatchConnectivity
import VitalFlowCore

/// Starts workouts and quick heart-rate checks on Apple Watch from the iPhone, and shows the
/// live values the watch mirrors back (iOS 17 workout-session mirroring).
///
/// The iPhone has no heart-rate sensor: measurements always come from Apple Watch. The phone
/// launches the VitalFlow watch app in the background with `startWatchApp(with:)`; the watch
/// starts a real workout session and mirrors it, so the user never has to open the watch app.
@MainActor
@Observable
final class WatchWorkoutRemote: NSObject {
    static let shared = WatchWorkoutRemote()

    enum Phase: Equatable { case idle, starting, running, paused, ended, failed(String) }
    enum Mode { case workout, heartCheck }
    enum WatchStatus { case ready, notPaired, appNotInstalled, unsupported, unknown }

    var phase: Phase = .idle
    var mode: Mode = .workout
    var activity: WorkoutActivity = .running
    var live = LiveWorkoutPayload(activeEnergy: 0, distance: 0, elapsed: 0)
    var startDate: Date?
    /// Set when a heart-rate check finishes; the UI stores it in the local history.
    var heartCheckResult: (bpm: Double, date: Date)?

    private let store = HealthKitService.shared.store
    private var mirrored: HKWorkoutSession?
    private var timeout: Task<Void, Never>?
    private var installed = false

    /// Must run early (app launch) so a mirrored session started by the watch is received.
    func install() {
        guard !installed else { return }
        installed = true
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.attach(session) }
        }
    }

    var watchStatus: WatchStatus {
        guard WCSession.isSupported() else { return .unsupported }
        let s = WCSession.default
        guard s.activationState == .activated else { return .unknown }
        if !s.isPaired { return .notPaired }
        if !s.isWatchAppInstalled { return .appNotInstalled }
        return .ready
    }

    var isActive: Bool { phase == .starting || phase == .running || phase == .paused }

    func startWorkout(_ activity: WorkoutActivity) {
        self.activity = activity
        let c = HKWorkoutConfiguration()
        c.activityType = HealthKitService.hkActivity(activity)
        c.locationType = [.running, .walking, .cycling, .hiking].contains(activity) ? .outdoor : .indoor
        launch(c, mode: .workout)
    }

    func measureHeartRate() {
        launch(HeartCheck.configuration(), mode: .heartCheck)
    }

    private func launch(_ config: HKWorkoutConfiguration, mode: Mode) {
        guard !isActive else { return }
        install()
        self.mode = mode
        live = LiveWorkoutPayload(activeEnergy: 0, distance: 0, elapsed: 0)
        heartCheckResult = nil
        phase = .starting
        store.startWatchApp(with: config) { [weak self] ok, error in
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.phase == .starting else { return }
                if !ok {
                    self.phase = .failed(message ?? String(localized: "Couldn't reach Apple Watch."))
                }
            }
        }
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard let self, self.phase == .starting else { return }
            self.phase = .failed(String(localized: "Apple Watch didn't respond. Make sure it's on your wrist, unlocked and nearby, and that the VitalFlow watch app is installed."))
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        timeout?.cancel()
        mirrored = session
        session.delegate = self
        mode = HeartCheck.isHeartCheck(session.workoutConfiguration) ? .heartCheck : .workout
        if mode == .workout { activity = HealthKitService.activity(session.workoutConfiguration.activityType) }
        startDate = session.startDate ?? Date()
        phase = session.state == .paused ? .paused : .running
    }

    func togglePause() {
        guard let s = mirrored else { return }
        if phase == .running { s.pause() } else if phase == .paused { s.resume() }
    }

    func end() {
        if let s = mirrored { s.end() } else { phase = .idle }
    }

    func reset() {
        guard !isActive else { return }
        phase = .idle
    }

    fileprivate func receive(_ data: [Data]) {
        for d in data {
            guard let p = try? JSONDecoder().decode(LiveWorkoutPayload.self, from: d) else { continue }
            live = p
            if let r = p.heartCheckResult { heartCheckResult = (r, Date()) }
        }
    }

    fileprivate func ended() {
        mirrored = nil
        phase = .ended
        Task { await AppModelBridge.refresh?() }
    }
}

/// Lets the remote ask the app model to refresh after a workout without a hard dependency.
@MainActor
enum AppModelBridge {
    static var refresh: (() async -> Void)?
}

extension WatchWorkoutRemote: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: self.phase = .running
            case .paused: self.phase = .paused
            case .ended, .stopped: self.ended()
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.phase = .failed(msg) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            if self.isActive { self.ended() }
        }
    }
}
