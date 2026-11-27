import Foundation
import WatchConnectivity

/// iPhone side of WatchConnectivity. Sends the latest computed snapshot via
/// `updateApplicationContext` (latest-state-wins, delivered when the watch wakes) and
/// receives hydration logs / workout-finished events from the watch.
final class PhoneConnectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = PhoneConnectivity()
    private weak var model: AppModel?
    private var pending: WidgetSnapshot?

    @MainActor
    func activate(model: AppModel) {
        self.model = model
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { pending = snapshot; return }
        guard s.isPaired, s.isWatchAppInstalled, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? s.updateApplicationContext(["snapshot": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated, let p = pending { pending = nil; send(snapshot: p) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

    private func handle(_ info: [String: Any]) {
        // The watch already wrote water/workouts to HealthKit; we only need to recompute.
        if info["event"] as? String != nil {
            Task { @MainActor in await self.model?.refresh() }
        }
    }
}
