import Foundation
import VitalFlowCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why the on-device model can or can't be used.
enum AIAvailability: Equatable {
    case available, requiresNewerOS, deviceNotEligible, notEnabled, modelNotReady, unknown
}

/// Holds the latest data for the coach's tools. Tools read it at call time, so a long
/// conversation always sees the freshest numbers after a refresh.
final class CoachDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _toolkit: CoachToolkit
    init(_ t: CoachToolkit) { _toolkit = t }
    var toolkit: CoachToolkit {
        get { lock.lock(); defer { lock.unlock() }; return _toolkit }
        set { lock.lock(); _toolkit = newValue; lock.unlock() }
    }
}

enum AICoachError: LocalizedError {
    case unavailable
    var errorDescription: String? { String(localized: "Apple Intelligence isn't available on this device.") }
}

/// AI coach powered by Apple Intelligence's on-device foundation model (iOS 26+).
/// Everything runs on the iPhone: no account, no API key, no network, no cost, and health
/// data never leaves the device. The model looks up the user's data through tools instead
/// of having numbers pasted into the prompt, and is instructed never to diagnose.
@MainActor
final class AICoach {
    static let shared = AICoach()

    private let box = CoachDataBox(CoachToolkit(assessment: nil, history: [], workouts: [], goals: GoalSet(),
                                                calendar: .current, isDemo: false))
    private var session: AnyObject?
    private var sessionKey: String?

    var availability: AIAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .unknown
                }
            }
        }
        #endif
        return .requiresNewerOS
    }

    func update(_ toolkit: CoachToolkit) { box.toolkit = toolkit }

    func resetConversation() {
        session = nil
        sessionKey = nil
    }

    static func instructions(language: AssistantLanguage, isDemo: Bool) -> String {
        let lang: String
        switch language {
        case .english: lang = "English"
        case .traditionalChinese: lang = "Traditional Chinese (繁體中文)"
        case .simplifiedChinese: lang = "Simplified Chinese (简体中文)"
        }
        return """
        You are VitalFlow Coach, a warm, encouraging and concise wellness coach inside a health app.
        Always use the tools to look up the user's own data before answering anything about their health, sleep, \
        activity, scores or trends. Never invent or estimate numbers that the tools did not return. If data is missing, \
        say there is not enough data yet and explain what is needed (usually wearing Apple Watch, including to sleep, \
        for a few days).
        VitalFlow scores are experimental wellness estimates, not medical measurements.
        Safety rules: never diagnose, never say a disease or condition is likely, never interpret symptoms medically, \
        never recommend, change or comment on medication or supplements. For medical concerns, suggest talking to a \
        doctor; for emergencies, tell the user to contact local emergency services. Never suggest extreme exercise, \
        fasting, dieting or calorie targets, and never shame the user.
        Give at most two practical, gentle suggestions. Keep answers under 120 words unless the user asks for detail. \
        Plain text; short bullet points are fine.
        \(isDemo ? "The app is in DEMO mode: the data is synthetic. Mention this briefly when you cite numbers." : "")
        Always reply in \(lang).
        """
    }

    /// Answers a question in a continuing conversation.
    func ask(_ question: String, toolkit: CoachToolkit, language: AssistantLanguage) async throws -> String {
        box.toolkit = toolkit
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let key = "\(language.rawValue)-\(toolkit.isDemo)"
            let s: LanguageModelSession
            if let existing = session as? LanguageModelSession, sessionKey == key {
                s = existing
            } else {
                s = makeSession(language: language, isDemo: toolkit.isDemo)
                session = s
                sessionKey = key
            }
            do {
                return try await s.respond(to: question).content
            } catch let error as LanguageModelSession.GenerationError {
                // The on-device context window is small; start a fresh conversation and retry once.
                if case .exceededContextWindowSize = error {
                    let fresh = makeSession(language: language, isDemo: toolkit.isDemo)
                    session = fresh
                    return try await fresh.respond(to: question).content
                }
                throw error
            }
        }
        #endif
        throw AICoachError.unavailable
    }

    /// One-shot daily briefing for the Today screen.
    func briefing(toolkit: CoachToolkit, language: AssistantLanguage) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let s = LanguageModelSession(instructions: Self.instructions(language: language, isDemo: toolkit.isDemo))
            let prompt = """
            Here is the user's data for today:
            \(toolkit.briefingContext())

            Write today's briefing: 2 or 3 short sentences (max 60 words). Say how recovered they seem and why, \
            then give one gentle, practical suggestion for today. Do not use headings.
            """
            return try await s.respond(to: prompt).content
        }
        #endif
        throw AICoachError.unavailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func makeSession(language: AssistantLanguage, isDemo: Bool) -> LanguageModelSession {
        let tools: [any Tool] = [TodayWellnessTool(box: box), SleepTool(box: box), TrendTool(box: box),
                                 WorkoutsTool(box: box), GoalsTool(box: box)]
        return LanguageModelSession(tools: tools, instructions: Self.instructions(language: language, isDemo: isDemo))
    }
    #endif
}

#if canImport(FoundationModels)

@available(iOS 26.0, *)
struct TodayWellnessTool: Tool {
    let box: CoachDataBox
    let name = "getTodayWellness"
    let description = "Get today's VitalFlow wellness estimates (recovery, sleep score, stress, Body Battery, training readiness), how each input compares with the user's personal baseline, and today's activity, heart rate and hydration."

    @Generable
    struct Arguments {
        @Guide(description: "Whether to include the inputs behind the recovery score")
        var includeDetails: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        box.toolkit.todaySummary(details: arguments.includeDetails)
    }
}

@available(iOS 26.0, *)
struct SleepTool: Tool {
    let box: CoachDataBox
    let name = "getSleep"
    let description = "Get sleep details for one night: time asleep, efficiency, wake-ups, deep/REM/core sleep and the 7-night average."

    @Generable
    struct Arguments {
        @Guide(description: "0 for last night, 1 for the night before, and so on", .range(0...30))
        var nightsAgo: Int
    }

    func call(arguments: Arguments) async throws -> String {
        box.toolkit.sleepSummary(nightsAgo: arguments.nightsAgo)
    }
}

@available(iOS 26.0, *)
struct TrendTool: Tool {
    let box: CoachDataBox
    let name = "getMetricTrend"
    let description = "Get the trend of one health metric over the last N days: average, minimum, maximum, change between the first and second half of the period, week-over-week direction and recent daily values."

    @Generable
    struct Arguments {
        @Guide(description: "The metric to analyse", .anyOf(CoachToolkit.metrics))
        var metric: String
        @Guide(description: "How many days to look back, for example 7, 30 or 90", .range(7...365))
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        box.toolkit.trendSummary(metric: arguments.metric, days: arguments.days)
    }
}

@available(iOS 26.0, *)
struct WorkoutsTool: Tool {
    let box: CoachDataBox
    let name = "getRecentWorkouts"
    let description = "List the user's recent workouts with type, duration, energy, distance and average heart rate."

    @Generable
    struct Arguments {
        @Guide(description: "How many days to look back", .range(1...90))
        var days: Int
    }

    func call(arguments: Arguments) async throws -> String {
        box.toolkit.workoutsSummary(days: arguments.days)
    }
}

@available(iOS 26.0, *)
struct GoalsTool: Tool {
    let box: CoachDataBox
    let name = "getGoalsAndGarden"
    let description = "Get today's progress on the user's daily goals and the state of their VitalFlow garden and streak."

    @Generable
    struct Arguments {
        @Guide(description: "Whether to include the garden streak details")
        var includeGarden: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        box.toolkit.goalsSummary()
    }
}

#endif
