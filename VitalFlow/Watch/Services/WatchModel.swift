import Foundation
import SwiftUI
import HealthKit
import WatchConnectivity
import WidgetKit
import VitalFlowCore

/// Watch state. Scores come from the iPhone (computed with full history there); live values
/// such as today's activity, hydration and the most recent heart rate are read directly from
/// HealthKit on the watch. No continuous sensor polling: heart rate is whatever watchOS has
/// already recorded, except during a workout the user explicitly starts.
@MainActor
@Observable
final class WatchModel: NSObject {
    var snapshot: WidgetSnapshot = SnapshotStore.load() ?? .empty
    var steps: Double?
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var waterML: Double = 0
    var latestHR: Double?
    var latestHRDate: Date?
    var authorized = false

    private let hk = HealthKitService.shared
    private var hrQuery: HKAnchoredObjectQuery?

    func start() {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        Task {
            try? await hk.requestAuthorization()
            authorized = true
            await refresh()
            observeHeartRate()
        }
    }

    func refresh() async {
        let cal = Calendar.current
        let today = DayKey(Date(), calendar: cal)
        async let s = hk.dailyStatistics(.stepCount, days: [today], calendar: cal)
        async let e = hk.dailyStatistics(.activeEnergy, days: [today], calendar: cal)
        async let x = hk.dailyStatistics(.exerciseMinutes, days: [today], calendar: cal)
        async let w = hk.dailyStatistics(.dietaryWater, days: [today], calendar: cal)
        let (sv, ev, xv, wv) = await (s, e, x, w)
        steps = sv[today]; activeEnergy = ev[today]; exerciseMinutes = xv[today]; waterML = wv[today] ?? 0
        let recentHR = await hk.quantitySamples(.heartRate, start: Date().addingTimeInterval(-3 * 3600), end: Date())
        if let last = recentHR.last { latestHR = last.value; latestHRDate = last.start }
        updateLocalSnapshot()
    }

    /// Updates the watch-side copy used by complications with the freshest on-watch values.
    private func updateLocalSnapshot() {
        var s = snapshot
        if let steps { s.steps = Int(steps) }
        if let activeEnergy { s.activeEnergy = Int(activeEnergy) }
        if let exerciseMinutes { s.exerciseMinutes = Int(exerciseMinutes) }
        s.waterML = Int(waterML)
        if let latestHR { s.latestHR = Int(latestHR) }
        snapshot = s
        SnapshotStore.save(s)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Anchored query: delivers new heart-rate samples as watchOS records them (battery-friendly).
    private func observeHeartRate() {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: nil)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            guard let q = (samples as? [HKQuantitySample])?.max(by: { $0.startDate < $1.startDate }) else { return }
            let v = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let d = q.startDate
            Task { @MainActor in self?.latestHR = v; self?.latestHRDate = d }
        }
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        hk.store.execute(q)
        hrQuery = q
    }

    func logWater(_ ml: Double) async {
        do {
            try await hk.logWater(milliliters: ml)
            waterML += ml
            updateLocalSnapshot()
            notifyPhone("water")
        } catch {}
    }

    func notifyPhone(_ event: String) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(["event": event, "at": Date().timeIntervalSince1970])
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ ctx: [String: Any]) {
        guard let data = ctx["snapshot"] as? Data, let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        snapshot = s
        updateLocalSnapshot()
    }
}
