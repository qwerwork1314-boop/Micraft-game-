import SwiftUI
import VitalFlowCore

/// Explains why VitalFlow does or doesn't see Health data, with counts per data type.
struct HealthConnectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var status: HealthKitService.RequestStatus = .unknown
    @State private var counts: [(id: String, count: Int)] = []
    @State private var loading = true

    private var total: Int { counts.reduce(0) { $0 + $1.count } }
    private var entitlementMissing: Bool {
        (model.healthAuthError ?? "").localizedCaseInsensitiveContains("entitlement")
    }

    var body: some View {
        List {
            Section {
                diagnosis
            }
            Section("Data VitalFlow can read (last 7 days)") {
                if loading {
                    ProgressView()
                } else {
                    ForEach(counts, id: \.id) { row in
                        HStack {
                            Text(Self.name(row.id))
                            Spacer()
                            Text(verbatim: row.count == 0 ? "—" : "\(row.count)")
                                .monospacedDigit()
                                .foregroundStyle(row.count == 0 ? .secondary : .primary)
                        }
                    }
                }
            }
            Section {
                Button { Task { await model.requestHealthAccess(); await load() } } label: {
                    Label("Ask for Health access again", systemImage: "heart.text.square")
                }
                Button {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                } label: { Label("Open the Health app", systemImage: "arrow.up.forward.app") }
                Button {
                    model.setDemoMode(true)
                } label: { Label("Use demo data instead", systemImage: "theatermasks") }
            }
            if let e = model.healthAuthError {
                Section("Technical details") {
                    Text(verbatim: e).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle(Text("Health connection"))
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var diagnosis: some View {
        if !model.healthAvailable {
            row("xmark.octagon", Brand.amber, "Health data unavailable",
                "This device doesn't support HealthKit. You can explore VitalFlow with demo data in Settings.")
        } else if entitlementMissing {
            row("lock.slash", Brand.amber, "This copy of VitalFlow can't use Apple Health",
                "It was installed without the Apple Health permission (this often happens with free sideloading). Health data can't be read in this install. Use demo data, or install through TestFlight, which keeps the permission.")
        } else if status == .notAsked {
            row("hand.raised", Brand.ocean, "Health access hasn't been requested yet",
                "Tap “Ask for Health access again” and allow the data types you want to share.")
        } else if !loading && total == 0 {
            row("questionmark.circle", Brand.amber, "No readable Health data",
                "VitalFlow has asked for access but can't read any data. In the Health app open your profile → Apps → VitalFlow and turn on all categories. Without Apple Watch, only iPhone data such as steps and distance is available, and sleep needs Sleep Focus or a sleep-tracking device.")
        } else if !loading {
            row("checkmark.seal.fill", Brand.emerald, "Connected to Apple Health",
                "Scores need about 4 nights of sleep with Apple Watch to learn your baseline. Until then they show “Not enough data”.")
        } else {
            ProgressView()
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        status = await HealthKitService.shared.authorizationRequestStatus()
        counts = await HealthKitService.shared.sampleCounts(days: 7)
        loading = false
    }

    static func name(_ id: String) -> LocalizedStringKey {
        switch id {
        case "heartRate": "Heart rate"
        case "restingHeartRate": "Resting heart rate"
        case "hrvSDNN": "Heart rate variability"
        case "oxygenSaturation": "Blood oxygen"
        case "respiratoryRate": "Respiratory rate"
        case "wristTemperature": "Wrist temperature"
        case "stepCount": "Steps"
        case "distanceWalkingRunning": "Walking + running distance"
        case "activeEnergy": "Active energy"
        case "basalEnergy": "Resting energy"
        case "exerciseMinutes": "Exercise minutes"
        case "vo2Max": "VO2 max"
        case "timeInDaylight": "Time in daylight"
        case "bodyMass": "Body weight"
        case "dietaryWater": "Water"
        case "sleep": "Sleep"
        case "workouts": "Workouts"
        default: LocalizedStringKey(id)
        }
    }
}
