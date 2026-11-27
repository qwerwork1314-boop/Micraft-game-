import Foundation
import SwiftData
import Security

/// Assistant conversation, stored only on this device.
@Model
final class ChatMessageRecord {
    var id: UUID
    var createdAt: Date
    var isUser: Bool
    var text: String
    /// "local" or "external" — shown in the UI so the user knows where an answer came from.
    var origin: String

    init(isUser: Bool, text: String, origin: String = "local") {
        self.id = UUID()
        self.createdAt = Date()
        self.isUser = isUser
        self.text = text
        self.origin = origin
    }
}

/// Date an achievement was first unlocked (the unlock itself is recomputed from history).
@Model
final class AchievementRecord {
    @Attribute(.unique) var key: String
    var unlockedAt: Date
    init(key: String, unlockedAt: Date = Date()) {
        self.key = key
        self.unlockedAt = unlockedAt
    }
}

/// Cached daily score results so history survives offline launches and Health sync gaps.
@Model
final class DailyScoreRecord {
    @Attribute(.unique) var dayKey: String
    var recovery: Int?
    var sleepScore: Int?
    var stress: Int?
    var bodyBattery: Int?
    var readiness: Int?
    var goalsCompleted: Int
    var isDemo: Bool
    var updatedAt: Date

    init(dayKey: String, recovery: Int?, sleepScore: Int?, stress: Int?, bodyBattery: Int?, readiness: Int?,
         goalsCompleted: Int, isDemo: Bool) {
        self.dayKey = dayKey
        self.recovery = recovery
        self.sleepScore = sleepScore
        self.stress = stress
        self.bodyBattery = bodyBattery
        self.readiness = readiness
        self.goalsCompleted = goalsCompleted
        self.isDemo = isDemo
        self.updatedAt = Date()
    }
}

/// Result of a quick heart-rate check started from the app (measured by Apple Watch).
@Model
final class HeartCheckRecord {
    var id: UUID
    var date: Date
    var bpm: Double

    init(bpm: Double, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.bpm = bpm
    }
}

enum LocalStore {
    static let schema = Schema([ChatMessageRecord.self, AchievementRecord.self, DailyScoreRecord.self, HeartCheckRecord.self])

    /// SwiftData store in Application Support with complete file protection
    /// (encrypted at rest and unreadable while the device is locked).
    static func makeContainer() -> ModelContainer {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let folder = dir.appendingPathComponent("VitalFlow", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.complete])
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
        let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("VitalFlow.store"))
        if let c = try? ModelContainer(for: schema, configurations: [config]) { return c }
        // Last resort keeps the app usable if the store is corrupted.
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @MainActor
    static func deleteAll(in context: ModelContext) {
        try? context.delete(model: ChatMessageRecord.self)
        try? context.delete(model: AchievementRecord.self)
        try? context.delete(model: DailyScoreRecord.self)
        try? context.delete(model: HeartCheckRecord.self)
        try? context.save()
    }
}

/// Minimal Keychain wrapper for the optional external-assistant API key.
enum Keychain {
    static let service = "VitalFlow.ExternalAssistant"

    static func set(_ value: String, for account: String) {
        delete(account)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
