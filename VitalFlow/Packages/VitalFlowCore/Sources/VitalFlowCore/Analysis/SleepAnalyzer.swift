import Foundation

/// Turns raw, possibly overlapping multi-source sleep samples into clean nights.
///
/// Algorithm (documented in docs/ALGORITHMS.md §Sleep):
/// 1. Drop exact duplicates (same id) and zero-length samples.
/// 2. Choose a *primary source* per night: the source with the most staged sleep
///    (core/deep/REM), falling back to the most asleep time, then source rank.
/// 3. Sweep-line over all boundaries. For each elementary slice the winning sample is the
///    one with the highest (isPrimarySource, stage priority) tuple. Secondary sources only
///    fill gaps where the primary source recorded nothing (e.g. the watch battery died).
/// 4. Merge adjacent slices of the same stage, group into sessions split by gaps > 90 min.
/// 5. Attribute sessions to the wake day: the night for day D is the window
///    [D-1 18:00, D 18:00). Sessions that lie fully between 10:00 and 18:00 are naps.
public struct SleepAnalyzer: Sendable {
    public var calendar: Calendar
    public var sessionGap: TimeInterval = 90 * 60
    public var minInterruption: TimeInterval = 60

    public init(calendar: Calendar) { self.calendar = calendar }

    /// The window that belongs to `day` (wake-up day).
    public func window(for day: DayKey) -> (start: Date, end: Date) {
        let dayStart = day.startDate(in: calendar)
        let start = calendar.date(byAdding: .hour, value: -6, to: dayStart) ?? dayStart.addingTimeInterval(-21_600)
        let end = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? dayStart.addingTimeInterval(64_800)
        return (start, end)
    }

    /// Merge samples into non-overlapping segments (steps 1–4 except session grouping).
    public func mergeSegments(_ raw: [SleepSample]) -> [SleepSegment] {
        var seen = Set<String>()
        let samples = raw.filter { $0.end > $0.start && seen.insert($0.id).inserted }
        guard !samples.isEmpty else { return [] }

        let primary = primarySource(samples)
        var bounds = Set<Date>()
        for s in samples { bounds.insert(s.start); bounds.insert(s.end) }
        let points = bounds.sorted()

        // Sort samples by start for a moving active window.
        let byStart = samples.sorted { $0.start < $1.start }
        var slices: [SleepSegment] = []
        var cursor = 0
        var active: [SleepSample] = []
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            while cursor < byStart.count, byStart[cursor].start <= a {
                active.append(byStart[cursor])
                cursor += 1
            }
            active.removeAll { $0.end <= a }
            let covering = active.filter { $0.start < b && $0.end > a }
            guard let winner = covering.max(by: { lhs, rhs in
                let l = (lhs.sourceID == primary ? 1 : 0, lhs.stage.priority)
                let r = (rhs.sourceID == primary ? 1 : 0, rhs.stage.priority)
                return l < r
            }) else { continue }
            if let last = slices.last, last.stage == winner.stage, last.end == a {
                slices[slices.count - 1].end = b
            } else {
                slices.append(SleepSegment(stage: winner.stage, start: a, end: b))
            }
        }
        return slices
    }

    public func primarySource(_ samples: [SleepSample]) -> String? {
        var staged: [String: TimeInterval] = [:]
        var asleep: [String: TimeInterval] = [:]
        var rank: [String: Int] = [:]
        for s in samples {
            if s.stage.isStaged { staged[s.sourceID, default: 0] += s.duration }
            if s.stage.isAsleep { asleep[s.sourceID, default: 0] += s.duration }
            rank[s.sourceID] = max(rank[s.sourceID] ?? 0, Deduplicator.sourceRank(sourceID: s.sourceID, isFromWatch: s.isFromWatch))
        }
        return rank.keys.max { a, b in
            let l = (staged[a] ?? 0, asleep[a] ?? 0, rank[a] ?? 0, b)
            let r = (staged[b] ?? 0, asleep[b] ?? 0, rank[b] ?? 0, a)
            return l < r
        }
    }

    /// Analyse the night that ends on `day`. Returns nil when there is no asleep time.
    public func night(for day: DayKey, samples: [SleepSample]) -> SleepNight? {
        let w = window(for: day)
        // Include samples that overlap the window; clip them to it.
        let clipped: [SleepSample] = samples.compactMap { s in
            guard s.end > w.start, s.start < w.end else { return nil }
            var c = s
            c.start = max(s.start, w.start)
            c.end = min(s.end, w.end)
            return c
        }
        let segments = mergeSegments(clipped)
        guard segments.contains(where: { $0.stage.isAsleep }) else { return nil }

        // Group into sessions using asleep/awake segments (in-bed only extends nothing).
        let sleepSegs = segments.filter { $0.stage != .inBed }
        var sessions: [[SleepSegment]] = []
        for seg in sleepSegs {
            if let last = sessions.last?.last, seg.start.timeIntervalSince(last.end) <= sessionGap {
                sessions[sessions.count - 1].append(seg)
            } else {
                sessions.append([seg])
            }
        }
        // Trim leading/trailing awake from each session.
        sessions = sessions.compactMap { s in
            guard let first = s.firstIndex(where: { $0.stage.isAsleep }),
                  let last = s.lastIndex(where: { $0.stage.isAsleep }) else { return nil }
            return Array(s[first...last])
        }
        guard !sessions.isEmpty else { return nil }

        let dayStart = day.startDate(in: calendar)
        let napStart = calendar.date(byAdding: .hour, value: 10, to: dayStart) ?? dayStart
        func isNap(_ s: [SleepSegment]) -> Bool {
            guard let f = s.first, let l = s.last else { return false }
            return f.start >= napStart && l.end <= w.end
        }
        let main = sessions.filter { !isNap($0) }
        let naps = sessions.filter(isNap)
        guard !main.isEmpty else { return nil }

        // Main sleep = all non-nap sessions in the window (split nights are merged).
        let mainSegs = main.flatMap { $0 }
        var night = SleepNight(wakeDay: day, segments: mainSegs,
                               start: mainSegs.first!.start, end: mainSegs.last!.end,
                               asleep: 0, awake: 0, deep: 0, rem: 0, core: 0, unspecified: 0,
                               interruptions: 0, napDuration: 0, hasStageData: false,
                               primarySourceID: primarySource(clipped))
        for seg in mainSegs {
            switch seg.stage {
            case .deep: night.deep += seg.duration
            case .rem: night.rem += seg.duration
            case .core: night.core += seg.duration
            case .asleepUnspecified: night.unspecified += seg.duration
            case .awake:
                night.awake += seg.duration
                if seg.duration >= minInterruption { night.interruptions += 1 }
            case .inBed: break
            }
        }
        // Gaps between sessions of a split night also count as interruptions + awake time.
        if main.count > 1 {
            for i in 1..<main.count {
                let gap = main[i].first!.start.timeIntervalSince(main[i - 1].last!.end)
                night.awake += max(0, gap)
                night.interruptions += 1
            }
        }
        night.asleep = night.deep + night.rem + night.core + night.unspecified
        night.hasStageData = (night.deep + night.rem + night.core) > 0.5 * night.asleep
        night.napDuration = naps.flatMap { $0 }.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.duration }
        return night
    }

    /// Sleep consistency 0–100 from the variability of mid-sleep time across nights.
    /// σ ≤ 15 min → 100; σ ≥ 95 min → 0. Needs ≥ 4 nights.
    public func consistency(of nights: [SleepNight]) -> ScoreResult {
        guard nights.count >= 4 else { return .notEnoughData(missing: [.sleepHistory]) }
        // Minutes from local noon so that midnight wrap-around is continuous.
        let mids: [Double] = nights.map { n in
            let c = calendar.dateComponents([.hour, .minute], from: n.midpoint)
            var minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 720
            if minutes < 0 { minutes += 1440 }
            return minutes
        }
        guard let sd = Math.standardDeviation(mids) else { return .notEnoughData(missing: [.sleepHistory]) }
        let score = Int(Math.ramp(sd, from: 15, 95, to: 100, 0).rounded())
        let conf: Confidence = nights.count >= 7 ? .high : .medium
        return .value(score, confidence: conf,
                      components: [ScoreComponent(key: "midSleepSD", value: sd, baseline: nil, effect: 0, weight: 1)])
    }
}
