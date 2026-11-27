import XCTest
@testable import VitalFlowCore

final class DeduplicationTests: XCTestCase {
    let t0 = TestCal.date(2026, 3, 10, 9)

    func testIdenticalIDsAreRemoved() {
        let s = QuantitySample(id: "a", kind: .heartRate, value: 60, start: t0)
        XCTAssertEqual(Deduplicator.dedupeDiscrete([s, s, s]).count, 1)
    }

    func testCrossSourceDuplicateKeepsWatch() {
        let phone = QuantitySample(id: "p", kind: .heartRate, value: 61, start: t0, sourceID: "com.thirdparty.app")
        let watch = QuantitySample(id: "w", kind: .heartRate, value: 61, start: t0.addingTimeInterval(0.5), sourceID: "com.apple.health.x", isFromWatch: true)
        let out = Deduplicator.dedupeDiscrete([phone, watch])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.id, "w")
    }

    func testDifferentValuesAreNotDuplicates() {
        let a = QuantitySample(id: "a", kind: .heartRate, value: 60, start: t0)
        let b = QuantitySample(id: "b", kind: .heartRate, value: 75, start: t0)
        XCTAssertEqual(Deduplicator.dedupeDiscrete([a, b]).count, 2)
    }

    func testDifferentKindsAreNotDuplicates() {
        let a = QuantitySample(id: "a", kind: .heartRate, value: 60, start: t0)
        let b = QuantitySample(id: "b", kind: .restingHeartRate, value: 60, start: t0)
        XCTAssertEqual(Deduplicator.dedupeDiscrete([a, b]).count, 2)
    }

    func testOverlappingCumulativeSourcesCountedOnce() {
        // Watch and iPhone both counted the same walk; HealthKit-style priority keeps the watch.
        let end = t0.addingTimeInterval(3600)
        let watch = QuantitySample(id: "w", kind: .stepCount, value: 1000, start: t0, end: end, sourceID: "watch", isFromWatch: true)
        let phone = QuantitySample(id: "p", kind: .stepCount, value: 1200, start: t0, end: end, sourceID: "com.apple.phone")
        let total = Deduplicator.mergedCumulativeTotal([watch, phone], start: t0, end: end)
        XCTAssertEqual(total, 1000, accuracy: 0.001)
    }

    func testPartialOverlapUsesLowerPrioritySourceForGap() {
        // Phone 9:00–10:00 (1200 steps), watch only 9:30–10:00 (500 steps).
        let phone = QuantitySample(id: "p", kind: .stepCount, value: 1200, start: t0, end: t0.addingTimeInterval(3600), sourceID: "com.apple.phone")
        let watch = QuantitySample(id: "w", kind: .stepCount, value: 500, start: t0.addingTimeInterval(1800), end: t0.addingTimeInterval(3600), sourceID: "watch", isFromWatch: true)
        let total = Deduplicator.mergedCumulativeTotal([phone, watch], start: t0, end: t0.addingTimeInterval(3600))
        XCTAssertEqual(total, 600 + 500, accuracy: 0.001)
    }

    func testDuplicateCumulativeIDsCountedOnce() {
        let s = QuantitySample(id: "x", kind: .dietaryWater, value: 250, start: t0)
        XCTAssertEqual(Deduplicator.mergedCumulativeTotal([s, s], start: t0.addingTimeInterval(-10), end: t0.addingTimeInterval(10)), 250)
    }
}
