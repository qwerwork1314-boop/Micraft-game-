import Foundation

/// Small, already-computed summary shared with widgets, complications and the watch.
/// Contains no raw samples. Stored in the App Group container.
struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var recovery: Int?
    var bodyBattery: Int?
    var stress: Int?
    var sleepScore: Int?
    var sleepMinutes: Int?
    var restingHR: Int?
    var latestHR: Int?
    var steps: Int?
    var stepGoal: Int
    var activeEnergy: Int?
    var energyGoal: Int
    var exerciseMinutes: Int?
    var exerciseGoal: Int
    var waterML: Int
    var waterGoal: Int
    var readinessLevel: String?
    var isDemo: Bool

    static let placeholder = WidgetSnapshot(generatedAt: Date(), recovery: 72, bodyBattery: 64, stress: 28, sleepScore: 81,
                                            sleepMinutes: 452, restingHR: 56, latestHR: 68, steps: 6400, stepGoal: 8000,
                                            activeEnergy: 320, energyGoal: 400, exerciseMinutes: 22, exerciseGoal: 30,
                                            waterML: 1250, waterGoal: 2000, readinessLevel: "moderate", isDemo: true)

    static let empty = WidgetSnapshot(generatedAt: .distantPast, recovery: nil, bodyBattery: nil, stress: nil, sleepScore: nil,
                                      sleepMinutes: nil, restingHR: nil, latestHR: nil, steps: nil, stepGoal: 8000,
                                      activeEnergy: nil, energyGoal: 400, exerciseMinutes: nil, exerciseGoal: 30,
                                      waterML: 0, waterGoal: 2000, readinessLevel: nil, isDemo: false)
}

enum SnapshotStore {
    static let key = "vf.widgetSnapshot.v1"

    static var appGroup: String? { Bundle.main.object(forInfoDictionaryKey: "VFAppGroup") as? String }

    /// Falls back to standard defaults when the App Group isn't provisioned (e.g. unsigned CI builds).
    static var defaults: UserDefaults {
        if let g = appGroup, let d = UserDefaults(suiteName: g) { return d }
        return .standard
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ s: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }

    static func clear() { defaults.removeObject(forKey: key) }
}
