import SwiftUI
import SwiftData
import VitalFlowCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDelete = false
    @State private var showConsent = false
    @State private var showGoals = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Health data") {
                    NavigationLink { HealthConnectionView() } label: {
                        Label("Health connection", systemImage: "stethoscope")
                    }
                    Button {
                        Task { await model.requestHealthAccess() }
                    } label: { Label("Review Health permissions", systemImage: "heart.text.square") }
                    Button {
                        if let url = URL(string: "x-apple-health://") { openURL(url) }
                    } label: { Label("Open the Health app", systemImage: "arrow.up.forward.app") }
                    Text("To change what VitalFlow can read, open Health → Profile → Apps → VitalFlow. HealthKit doesn't tell apps which read permissions were denied, so missing data simply shows as “Not enough data”.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: Binding(get: { model.settings.demoMode }, set: { model.setDemoMode($0) })) {
                        Label("Demo mode", systemImage: "theatermasks")
                    }
                } footer: {
                    Text("Shows clearly labelled synthetic data for exploring the app. Demo data is never written to Health and is never mixed with your real data.")
                }

                Section("Goals & sleep") {
                    Button { showGoals = true } label: { Label("Daily goals", systemImage: "target") }
                    Stepper(value: $model.settings.sleepNeedHours, in: 6...10, step: 0.5) {
                        Text(String(format: String(localized: "Sleep need: %@ h"), Fmt.one(model.settings.sleepNeedHours) ?? ""))
                    }
                }

                Section {
                    Toggle("Gentle hydration reminders", isOn: $model.settings.hydrationReminders)
                    Toggle("Bedtime wind-down reminder", isOn: $model.settings.bedtimeReminder)
                    if model.settings.bedtimeReminder {
                        DatePicker("Bedtime", selection: Binding(
                            get: { Calendar.current.date(from: DateComponents(hour: model.settings.bedtimeHour, minute: model.settings.bedtimeMinute)) ?? Date() },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                model.settings.bedtimeHour = c.hour ?? 22
                                model.settings.bedtimeMinute = c.minute ?? 30
                            }), displayedComponents: .hourAndMinute)
                    }
                } header: { Text("Reminders") } footer: {
                    Text("Optional and off by default. VitalFlow never sends guilt-based or streak-loss notifications.")
                }
                .onChange(of: model.settings) { _, s in Task { await ReminderScheduler.apply(s) } }

                Section {
                    Toggle(isOn: Binding(get: { model.settings.useAppleIntelligence },
                                         set: { on in
                                             model.settings.appleIntelligenceCoachDisabled = on ? nil : true
                                             AICoach.shared.resetConversation()
                                             Task { await model.refreshBriefing(force: true) }
                                         })) {
                        Label("AI coach (Apple Intelligence)", systemImage: "sparkles")
                    }
                    if model.settings.useAppleIntelligence && AICoach.shared.availability != .available {
                        Text(AssistantView.aiUnavailableReason(AICoach.shared.availability, enabled: true))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle(isOn: Binding(get: { model.settings.externalAssistantEnabled },
                                         set: { on in if on { showConsent = true } else { revokeExternal() } })) {
                        Label("External AI assistant", systemImage: "network")
                    }
                    if model.settings.hasValidExternalConsent {
                        APIKeyField()
                        if let d = model.settings.externalConsentDate {
                            Text(String(format: String(localized: "Consent given %@"), d.formatted(date: .abbreviated, time: .shortened)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Assistant") } footer: {
                    Text("The AI coach uses Apple Intelligence on your iPhone: free, private, nothing leaves the device. The external assistant is optional, off by default, and used only when Apple Intelligence isn't available.")
                }

                Section("Privacy") {
                    NavigationLink { PrivacyPolicyView() } label: { Label("Privacy policy", systemImage: "hand.raised") }
                    NavigationLink { AboutScoresView() } label: { Label("How scores work", systemImage: "function") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete all VitalFlow data", systemImage: "trash")
                    }
                }

                Section {
                    Text("VitalFlow provides experimental wellness estimates for general fitness and wellbeing. It is not a medical device and does not diagnose, treat or prevent any condition. Always consult a qualified health professional about medical concerns.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Text("Settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showConsent) { ExternalConsentView() }
            .sheet(isPresented: $showGoals) { GoalEditor() }
            .confirmationDialog("Delete all VitalFlow data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.deleteAllLocalData(context: context)
                    Haptics.success()
                    dismiss()
                }
            } message: {
                Text("This removes settings, conversation history, cached scores, widget data and any stored API key from this device. Data in the Health app is not affected — manage it in the Health app.")
            }
        }
    }

    private func revokeExternal() {
        model.settings.externalAssistantEnabled = false
        model.settings.externalConsentVersion = nil
        model.settings.externalConsentDate = nil
        Keychain.delete(ExternalAssistant.keychainAccount)
    }
}

struct APIKeyField: View {
    @State private var key = ""
    @State private var saved = Keychain.get(ExternalAssistant.keychainAccount) != nil

    var body: some View {
        if saved {
            HStack {
                Label("API key stored in Keychain", systemImage: "key.fill").font(.subheadline)
                Spacer()
                Button("Remove", role: .destructive) { Keychain.delete(ExternalAssistant.keychainAccount); saved = false }
            }
        } else {
            SecureField("Anthropic API key", text: $key)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save key") {
                Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: ExternalAssistant.keychainAccount)
                key = ""
                saved = true
            }
            .disabled(key.isEmpty)
        }
    }
}

struct ExternalConsentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before you enable the external assistant").font(.title2.weight(.semibold))
                    point("arrow.up.right.circle", "Your question and a small summary of your scores are sent to Anthropic (Claude) over an encrypted connection to generate an answer.")
                    point("eye.slash", "Only rounded daily numbers are sent — for example recovery, sleep hours, resting heart rate and HRV averages. No raw samples, names, dates of birth, device identifiers or locations.")
                    point("stethoscope", "Questions about diagnoses or medication are never sent; they're answered on-device with a referral to a professional.")
                    point("key", "You use your own API key, stored only in this device's Keychain. The provider's own privacy terms apply to data it receives.")
                    point("arrow.uturn.backward", "You can turn this off at any time; the key is deleted immediately.")
                    Text("Example of exactly what would be sent:").font(.subheadline.weight(.semibold))
                    Text(verbatim: ExternalAssistant.previewPayload(question: String(localized: "How well did I sleep last night?"), assessment: model.assessment))
                        .font(.caption.monospaced())
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    Toggle("I understand and agree to send this information", isOn: $understood)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enable") {
                        model.settings.externalAssistantEnabled = true
                        model.settings.externalConsentVersion = UserSettings.currentConsentVersion
                        model.settings.externalConsentDate = Date()
                        dismiss()
                    }
                    .disabled(!understood)
                }
            }
        }
    }

    func point(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Brand.emerald).frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy policy").font(.title2.weight(.semibold))
                Text("VitalFlow is local-first. All health analysis happens on your iPhone and Apple Watch.")
                Text("What we access").font(.headline)
                Text("With your permission, VitalFlow reads health and fitness data from Apple Health (such as heart rate, HRV, sleep, activity, workouts, VO2 max, daylight, weight and water) and writes water intake and Apple Watch workouts you record.")
                Text("What we store").font(.headline)
                Text("Settings, cached daily scores and assistant conversations are stored on this device with iOS file protection. Widgets receive only summary scores.")
                Text("What we share").font(.headline)
                Text("Nothing, by default. There are no accounts, ads, analytics or tracking. Health data is never sold, used for advertising or shared with data brokers. If you opt in to the external assistant, only the minimal summary shown on the consent screen is sent to the AI provider to answer your question.")
                Text("Your controls").font(.headline)
                Text("Manage Health permissions in the Health app at any time. Use Settings → Delete all VitalFlow data to erase everything VitalFlow stored on this device.")
                Text("Not medical advice").font(.headline)
                Text("VitalFlow scores are experimental wellness estimates and are not intended to diagnose, treat, cure or prevent any disease.")
            }
            .font(.subheadline)
            .padding()
        }
        .navigationTitle(Text("Privacy"))
    }
}

struct AboutScoresView: View {
    var body: some View {
        List {
            Section("Recovery") { Text("HRV (45%), resting heart rate (25%), sleep quality (20%), respiratory rate (5%) and wrist temperature (5%) compared with your own 28-day baseline. At least 4 days of history are required.") }
            Section("Sleep score") { Text("Duration vs your need (40%), efficiency (20%), deep + REM share (20%), interruptions (10%) and consistency (10%).") }
            Section("Stress") { Text("Heart rate at rest relative to your resting baseline and heart-rate reserve, plus daytime HRV, during hours without workouts or much walking.") }
            Section("Body Battery") { Text("Morning charge from recovery and sleep; drains with time awake, active energy and high stress; small recharge during calm hours.") }
            Section("Training readiness") { Text("65% recovery and 35% load balance (7-day vs 28-day training load ratio).") }
            Section("Confidence") { Text("Low with fewer than 14 days of baseline or missing inputs, medium with 14–20 days, high with 21+ days and most inputs available.") }
            Section { ExperimentalNote() }
        }
        .navigationTitle(Text("How scores work"))
    }
}
