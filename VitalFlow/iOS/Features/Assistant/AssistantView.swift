import SwiftUI
import SwiftData
import VitalFlowCore

struct AssistantView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessageRecord.createdAt) private var messages: [ChatMessageRecord]
    @State private var input = ""
    @State private var thinking = false
    @FocusState private var focused: Bool

    private var examples: [String] {
        [String(localized: "What should I focus on today?"),
         String(localized: "Why is my recovery score lower today?"),
         String(localized: "How well did I sleep last night?"),
         String(localized: "How has my resting heart rate changed this month?"),
         String(localized: "What is my current activity and recovery balance?"),
         String(localized: "Compare my sleep this week with last week.")]
    }

    private enum Engine { case appleIntelligence, external, rules }

    /// Apple Intelligence (on-device) first, then an opted-in external provider, then built-in rules.
    private var engine: Engine {
        if model.aiAvailable { return .appleIntelligence }
        if model.settings.hasValidExternalConsent { return .external }
        return .rules
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header
                            if messages.isEmpty { suggestions }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            if thinking { ProgressView().padding(.leading, 12) }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                inputBar
            }
            .vfBackground()
            .navigationTitle(Text("Coach"))
            .onAppear(perform: consumePending)
            .onChange(of: model.pendingCoachQuestion) { consumePending() }
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            for m in messages { context.delete(m) }
                            try? context.save()
                            AICoach.shared.resetConversation()
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Text("Clear conversation"))
                    }
                }
            }
        }
    }

    private var header: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 6) {
                switch engine {
                case .appleIntelligence:
                    Label("AI coach · Apple Intelligence on-device", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.emerald)
                    Text("Answers are generated privately on your iPhone from your own data. Nothing is sent to the internet.")
                        .font(.caption).foregroundStyle(.secondary)
                case .external:
                    Label("External assistant enabled", systemImage: "network")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.amber)
                case .rules:
                    Label("On-device assistant", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.emerald)
                    Text(Self.aiUnavailableReason(AICoach.shared.availability, enabled: model.settings.useAppleIntelligence))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.isDemo && !model.hasRecentHealthData && model.bundle != nil {
                    Label("No Health data yet — answers will be limited. Check Settings → Health connection.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Brand.amber)
                }
                Text("I explain your own trends. I can't diagnose conditions, recommend medication or replace a medical professional.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func aiUnavailableReason(_ a: AIAvailability, enabled: Bool) -> LocalizedStringKey {
        if !enabled { return "The AI coach is turned off in Settings, so built-in answers are used." }
        switch a {
        case .available: return "Apple Intelligence is available."
        case .requiresNewerOS: return "The AI coach needs iOS 26 or later with Apple Intelligence. Built-in answers are used for now."
        case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence (iPhone 15 Pro or newer is required). Built-in answers are used."
        case .notEnabled: return "Turn on Apple Intelligence in iPhone Settings → Apple Intelligence & Siri to use the AI coach."
        case .modelNotReady: return "Apple Intelligence is still downloading. The AI coach will be ready soon."
        case .unknown: return "Apple Intelligence isn't available right now. Built-in answers are used."
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(examples.enumerated()), id: \.offset) { _, q in
                Button {
                    send(q)
                } label: {
                    Text(verbatim: q).font(.subheadline).multilineTextAlignment(.leading)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ m: ChatMessageRecord) -> some View {
        HStack {
            if m.isUser { Spacer(minLength: 40) }
            VStack(alignment: m.isUser ? .trailing : .leading, spacing: 4) {
                Text(m.text)
                    .font(.subheadline)
                    .padding(12)
                    .foregroundStyle(m.isUser ? .white : .primary)
                    .background {
                        if m.isUser {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.flow)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                        }
                    }
                if !m.isUser && m.origin == "external" {
                    Text("Answered by external AI").font(.caption2).foregroundStyle(.secondary)
                }
                if !m.isUser && m.origin == "apple" {
                    Label("Apple Intelligence · on-device", systemImage: "sparkles").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !m.isUser { Spacer(minLength: 40) }
        }
        .textSelection(.enabled)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your trends…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { send(input) }
            Button { send(input) } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(Brand.flow)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || thinking)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    private func send(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        input = ""
        Haptics.tap()
        context.insert(ChatMessageRecord(isUser: true, text: q))
        let ctx = AssistantContext(today: model.assessment, history: model.history,
                                   waterGoalML: model.settings.goals.target(for: .waterML), calendar: model.calendar)
        let local = WellnessAssistant(language: model.language)
        let isMedical = WellnessAssistant.classify(q) == .medical
        // Medical questions are always answered with the fixed safety referral, never by a model.
        if engine == .appleIntelligence && !isMedical {
            thinking = true
            let toolkit = model.coachToolkit
            let language = model.language
            Task {
                do {
                    let text = try await AICoach.shared.ask(q, toolkit: toolkit, language: language)
                    context.insert(ChatMessageRecord(isUser: false, text: text, origin: "apple"))
                } catch {
                    // Guardrail, unsupported language or model busy: fall back to the built-in answer.
                    context.insert(ChatMessageRecord(isUser: false, text: local.answer(q, context: ctx)))
                }
                thinking = false
                try? context.save()
            }
        } else if engine == .external && !isMedical {
            thinking = true
            Task {
                do {
                    let text = try await ExternalAssistant.ask(question: q, assessment: model.assessment, language: model.language)
                    context.insert(ChatMessageRecord(isUser: false, text: text, origin: "external"))
                } catch {
                    context.insert(ChatMessageRecord(isUser: false, text: local.answer(q, context: ctx) + "\n\n(" + error.localizedDescription + ")"))
                }
                thinking = false
                try? context.save()
            }
        } else {
            context.insert(ChatMessageRecord(isUser: false, text: local.answer(q, context: ctx)))
            try? context.save()
        }
    }
}

extension AssistantView {
    fileprivate func consumePending() {
        guard let q = model.pendingCoachQuestion else { return }
        model.pendingCoachQuestion = nil
        send(q)
    }
}
