import Foundation
import VitalFlowCore

/// OPTIONAL external AI provider (Anthropic Claude Messages API). Disabled by default.
///
/// Safeguards:
/// * Only used after explicit, versioned informed consent (`UserSettings.hasValidExternalConsent`).
/// * Sends only `MinimizedHealthSummary` (rounded aggregate scores) + the question text.
///   No raw samples, identifiers, timestamps, device or location data.
/// * The user's own API key is stored in the Keychain (this-device-only), never in code or Git.
/// * The system prompt forbids diagnosis and medication advice.
struct ExternalAssistant {
    static let keychainAccount = "anthropic-api-key"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"

    enum Failure: LocalizedError {
        case noKey, http(Int), refused, emptyResponse
        var errorDescription: String? {
            switch self {
            case .noKey: return String(localized: "Add an API key in Settings to use the external assistant.")
            case .http(let code): return String(localized: "The external assistant returned an error (\(code)).")
            case .refused: return String(localized: "The external assistant declined this request.")
            case .emptyResponse: return String(localized: "The external assistant returned no answer.")
            }
        }
    }

    static func systemPrompt(language: AssistantLanguage) -> String {
        let lang: String
        switch language {
        case .english: lang = "English"
        case .simplifiedChinese: lang = "Simplified Chinese"
        case .traditionalChinese: lang = "Traditional Chinese"
        }
        return """
        You are VitalFlow's wellness coach. You receive a small JSON summary of a user's experimental, \
        non-clinical wellness estimates (0-100 scores and rounded daily averages) and a question. \
        Explain trends in plain, encouraging language using only the numbers provided; say so if data is missing. \
        Never diagnose diseases, interpret symptoms medically, or recommend, adjust or comment on medication. \
        For medical concerns, recommend speaking with a qualified health professional. \
        Avoid extreme exercise, dieting or calorie targets. Keep answers under 150 words. Reply in \(lang).
        """
    }

    struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct Thinking: Encodable { let type = "adaptive" }
        struct OutputConfig: Encodable { let effort = "low" }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        let thinking = Thinking()
        let output_config = OutputConfig()
        /// Server-side refusal fallback (routes a declined request to a suitable fallback model).
        let fallbacks = "default"
    }

    struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    /// Builds the exact JSON body that would be sent, so it can be shown to the user before consent.
    static func previewPayload(question: String, assessment: DailyAssessment?) -> String {
        let summary = MinimizedHealthSummary.from(assessment)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let s = (try? enc.encode(summary)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "summary: \(s)\nquestion: \(question)"
    }

    static func ask(question: String, assessment: DailyAssessment?, language: AssistantLanguage) async throws -> String {
        guard let key = Keychain.get(keychainAccount), !key.isEmpty else { throw Failure.noKey }
        let body = Request(model: model, max_tokens: 1024, system: systemPrompt(language: language),
                           messages: [.init(role: "user", content: previewPayload(question: question, assessment: assessment))])
        var req = URLRequest(url: endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONEncoder().encode(body)

        let config = URLSessionConfiguration.ephemeral // no caching of health-related traffic
        config.urlCache = nil
        let (data, response) = try await URLSession(configuration: config).data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if decoded.stop_reason == "refusal" { throw Failure.refused }
        let text = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else { throw Failure.emptyResponse }
        return text
    }
}
