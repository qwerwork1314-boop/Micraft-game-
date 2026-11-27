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
        [String(localized: "Why is my recovery score lower today?"),
         String(localized: "How well did I sleep last night?"),
         String(localized: "How has my resting heart rate changed this month?"),
         String(localized: "What is my current activity and recovery balance?")]
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
            .toolbar {
                if !messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            for m in messages { context.delete(m) }
                            try? context.save()
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
                Label(model.settings.hasValidExternalConsent ? LocalizedStringKey("External assistant enabled") : LocalizedStringKey("On-device assistant"),
                      systemImage: model.settings.hasValidExternalConsent ? "network" : "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.settings.hasValidExternalConsent ? Brand.amber : Brand.emerald)
                Text("I explain your own trends. I can't diagnose conditions, recommend medication or replace a medical professional.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
        // Medical questions are always answered locally with a referral, never sent anywhere.
        if model.settings.hasValidExternalConsent && WellnessAssistant.classify(q) != .medical {
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
