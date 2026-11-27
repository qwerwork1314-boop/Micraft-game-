import Foundation

/// Removes duplicate HealthKit records.
///
/// Duplicates appear when the same measurement is written by several apps (e.g. the
/// Apple Watch and a third-party app that re-exports it), when a sync re-delivers a
/// sample, or when an anchored query returns a sample twice across pages.
public enum Deduplicator {
    /// Ranks sources; higher wins. Apple Watch > iPhone/other Apple > third party.
    public static func sourceRank(sourceID: String, isFromWatch: Bool) -> Int {
        if isFromWatch { return 3 }
        if sourceID.hasPrefix("com.apple.") { return 2 }
        return 1
    }

    /// Discrete samples (heart rate, HRV, SpO2 …):
    /// 1. identical `id` → keep one;
    /// 2. same kind, start within `timeTolerance`, value within `valueTolerance` → keep the
    ///    sample from the highest-ranked source.
    public static func dedupeDiscrete(_ samples: [QuantitySample],
                                      timeTolerance: TimeInterval = 1,
                                      valueTolerance: Double = 0.001) -> [QuantitySample] {
        var seenIDs = Set<String>()
        let unique = samples.filter { seenIDs.insert($0.id).inserted }
        let sorted = unique.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return sourceRank(sourceID: $0.sourceID, isFromWatch: $0.isFromWatch)
                > sourceRank(sourceID: $1.sourceID, isFromWatch: $1.isFromWatch)
        }
        var result: [QuantitySample] = []
        for s in sorted {
            // Compare against recent kept samples of the same kind inside the time window.
            var isDuplicate = false
            var idx = result.count - 1
            while idx >= 0, s.start.timeIntervalSince(result[idx].start) <= timeTolerance {
                let r = result[idx]
                if r.kind == s.kind,
                   abs(r.value - s.value) <= max(valueTolerance, abs(r.value) * valueTolerance) {
                    isDuplicate = true
                    if sourceRank(sourceID: s.sourceID, isFromWatch: s.isFromWatch)
                        > sourceRank(sourceID: r.sourceID, isFromWatch: r.isFromWatch) {
                        result[idx] = s
                    }
                    break
                }
                idx -= 1
            }
            if !isDuplicate { result.append(s) }
        }
        return result
    }

    /// Cumulative samples (steps, energy …) from several sources that overlap in time.
    ///
    /// HealthKit's statistics queries already do this in production; this implementation
    /// mirrors the documented behaviour for demo data, imports and tests: when intervals
    /// from different sources overlap, only the highest-ranked source counts for the
    /// overlapping time, with each sample's value spread uniformly over its interval.
    /// Returns the total for the samples that fall in `[start, end)`.
    public static func mergedCumulativeTotal(_ samples: [QuantitySample], start: Date, end: Date) -> Double {
        var seenIDs = Set<String>()
        let unique = samples.filter { seenIDs.insert($0.id).inserted && $0.end > start && $0.start < end }
        guard !unique.isEmpty else { return 0 }

        // Elementary intervals from all boundaries.
        var bounds = Set<Date>([start, end])
        for s in unique {
            bounds.insert(max(start, s.start))
            bounds.insert(min(end, s.end))
        }
        let points = bounds.sorted()
        var total = 0.0
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            guard b > a else { continue }
            let covering = unique.filter { $0.start < b && $0.end > a }
            guard let bestRank = covering.map({ sourceRank(sourceID: $0.sourceID, isFromWatch: $0.isFromWatch) }).max() else { continue }
            // If several samples of the same best-ranked source cover the slice, they are
            // distinct measurements of that source (e.g. two consecutive watch samples) and add up.
            let winners = covering.filter { sourceRank(sourceID: $0.sourceID, isFromWatch: $0.isFromWatch) == bestRank }
            let bestSource = winners.map(\.sourceID).sorted().first
            for s in winners where s.sourceID == bestSource {
                total += portion(of: s, from: a, to: b)
            }
        }
        // Instantaneous samples (start == end) carry their full value.
        for s in unique where s.duration == 0 && s.start >= start && s.start < end {
            let rank = sourceRank(sourceID: s.sourceID, isFromWatch: s.isFromWatch)
            let shadowed = unique.contains {
                $0.duration > 0 && $0.start <= s.start && $0.end > s.start
                    && sourceRank(sourceID: $0.sourceID, isFromWatch: $0.isFromWatch) > rank
            }
            if !shadowed { total += s.value }
        }
        return total
    }

    /// Part of a cumulative sample's value that falls within `[a, b)`, assuming uniform rate.
    public static func portion(of s: QuantitySample, from a: Date, to b: Date) -> Double {
        guard s.duration > 0 else { return 0 }
        let overlap = min(b, s.end).timeIntervalSince(max(a, s.start))
        guard overlap > 0 else { return 0 }
        return s.value * overlap / s.duration
    }
}
