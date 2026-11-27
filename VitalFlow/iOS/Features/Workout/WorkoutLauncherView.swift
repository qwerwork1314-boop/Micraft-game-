import SwiftUI
import SwiftData
import VitalFlowCore

/// Start a workout or a quick heart-rate check on Apple Watch from the iPhone, and follow it live.
struct WorkoutLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \HeartCheckRecord.date, order: .reverse) private var checks: [HeartCheckRecord]
    @State private var remote = WatchWorkoutRemote.shared
    var startHeartCheckImmediately = false

    private let activities: [(WorkoutActivity, LocalizedStringKey, String)] = [
        (.running, "Run", "figure.run"), (.walking, "Walk", "figure.walk"), (.cycling, "Cycle", "figure.outdoor.cycle"),
        (.strength, "Strength", "dumbbell"), (.hiit, "HIIT", "flame"), (.yoga, "Yoga", "figure.yoga"),
        (.hiking, "Hike", "figure.hiking"), (.swimming, "Swim", "figure.pool.swim"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusBanner
                    if remote.isActive || remote.phase == .ended {
                        if remote.mode == .heartCheck { heartCheckLive } else { workoutLive }
                    } else {
                        heartCheckCard
                        workoutGrid
                    }
                    if !checks.isEmpty { historyCard }
                    Text("Measurements come from Apple Watch. iPhone has no heart-rate sensor; VitalFlow wakes the watch app for you, so you don't need to open it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .vfBackground()
            .navigationTitle(Text("Workout & heart rate"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                remote.reset()
                if startHeartCheckImmediately && remote.watchStatus == .ready { start { remote.measureHeartRate() } }
            }
            .onChange(of: remote.heartCheckResult?.date) {
                if let r = remote.heartCheckResult {
                    context.insert(HeartCheckRecord(bpm: r.bpm, date: r.date))
                    try? context.save()
                    Haptics.success()
                }
            }
        }
    }

    private func start(_ action: () -> Void) {
        Haptics.tap()
        action()
    }

    @ViewBuilder private var statusBanner: some View {
        switch remote.watchStatus {
        case .notPaired:
            banner("applewatch.slash", "No Apple Watch is paired with this iPhone. Heart-rate checks and workout tracking need Apple Watch.")
        case .appNotInstalled:
            banner("applewatch", "The VitalFlow app isn't installed on your Apple Watch. Install it from the Watch app on iPhone → My Watch → Available Apps. (Free sideloaded installs usually can't include the watch app.)")
        case .unsupported:
            banner("applewatch.slash", "This device can't connect to Apple Watch.")
        default:
            EmptyView()
        }
        if case .failed(let message) = remote.phase {
            banner("exclamationmark.triangle", LocalizedStringKey(message))
        }
    }

    private func banner(_ icon: String, _ text: LocalizedStringKey) -> some View {
        VFCard {
            Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon).foregroundStyle(Brand.amber) }
        }
    }

    private var canStart: Bool { remote.watchStatus == .ready || remote.watchStatus == .unknown }

    private var heartCheckCard: some View {
        VFCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Quick heart rate", systemImage: "heart.fill").font(.headline).foregroundStyle(Brand.coral)
                Text("Measures for about 40 seconds on Apple Watch. Sit still with the watch snug on your wrist. The check isn't saved as a workout.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    start { remote.measureHeartRate() }
                } label: {
                    Label("Measure now", systemImage: "waveform.path.ecg")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.coral)
                .disabled(!canStart)
            }
        }
    }

    private var workoutGrid: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Start a workout on Apple Watch", systemImage: "figure.run")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(activities, id: \.0) { a in
                        Button {
                            start { remote.startWorkout(a.0) }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: a.2).font(.title2)
                                Text(a.1).font(.caption.weight(.medium))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Brand.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canStart)
                    }
                }
            }
        }
    }

    private var heartCheckLive: some View {
        VFCard(padding: 24) {
            VStack(spacing: 14) {
                ZStack {
                    ScoreRing(progress: remote.phase == .ended ? 1 : (remote.live.heartCheckProgress ?? 0), color: Brand.coral, lineWidth: 14)
                    VStack(spacing: 2) {
                        Image(systemName: "heart.fill").foregroundStyle(Brand.coral)
                            .symbolEffect(.pulse, isActive: remote.isActive)
                        Text(verbatim: displayBPM.map { String(Int($0)) } ?? "—")
                            .font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("bpm").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 200)
                switch remote.phase {
                case .starting: Text("Waking Apple Watch…").foregroundStyle(.secondary)
                case .running, .paused: Text("Measuring… keep your wrist still").foregroundStyle(.secondary)
                case .ended:
                    if remote.heartCheckResult != nil {
                        Text("Heart rate measured").font(.headline)
                    } else {
                        Text("Not enough readings. Make sure the watch is snug and try again.").foregroundStyle(.secondary)
                    }
                    Button("Measure again") { start { remote.phase = .idle; remote.measureHeartRate() } }
                        .buttonStyle(.borderedProminent).tint(Brand.coral)
                default: EmptyView()
                }
                if remote.isActive {
                    Button("Cancel", role: .cancel) { remote.end() }
                }
                ExperimentalNote()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var displayBPM: Double? { remote.heartCheckResult?.bpm ?? remote.live.heartRate }

    private var workoutLive: some View {
        VFCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(remote.phase == .starting ? "Waking Apple Watch…" : "Workout in progress", systemImage: "figure.run")
                        .font(.headline).foregroundStyle(Brand.emerald)
                    Spacer()
                    if let s = remote.startDate, remote.isActive {
                        Text(s, style: .timer).font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(Brand.coral).symbolEffect(.pulse, isActive: remote.isActive)
                    Text(verbatim: remote.live.heartRate.map { String(Int($0)) } ?? "—")
                        .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bpm").foregroundStyle(.secondary)
                }
                HStack(spacing: 20) {
                    stat("Active energy", "\(Int(remote.live.activeEnergy)) kcal")
                    stat("Distance", String(format: "%.2f km", remote.live.distance / 1000))
                    stat("Average", remote.live.averageHeartRate.map { "\(Int($0)) bpm" } ?? "—")
                }
                if remote.isActive && remote.phase != .starting {
                    HStack {
                        Button { remote.togglePause() } label: {
                            Label(remote.phase == .paused ? "Resume" : "Pause", systemImage: remote.phase == .paused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(Brand.amber)
                        Button(role: .destructive) { remote.end() } label: {
                            Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                } else if remote.phase == .ended {
                    Text("Workout saved to Apple Health from your watch.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Done") { remote.phase = .idle }.buttonStyle(.borderedProminent).tint(Brand.emerald)
                } else if remote.phase == .starting {
                    Button("Cancel", role: .cancel) { remote.phase = .idle }
                }
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var historyCard: some View {
        VFCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Recent heart checks", systemImage: "clock.arrow.circlepath")
                ForEach(checks.prefix(8)) { c in
                    HStack {
                        Text(c.date, format: .dateTime.month().day().hour().minute()).font(.subheadline)
                        Spacer()
                        Text(verbatim: "\(Int(c.bpm)) bpm").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
    }
}
