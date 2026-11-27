import XCTest
import HealthKit
import VitalFlowCore
@testable import VitalFlow

final class HealthKitMappingTests: XCTestCase {
    func testSleepStageMapping() {
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.inBed.rawValue), .inBed)
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.awake.rawValue), .awake)
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.asleepCore.rawValue), .core)
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.asleepDeep.rawValue), .deep)
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.asleepREM.rawValue), .rem)
        XCTAssertEqual(HealthKitService.sleepStage(HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue), .asleepUnspecified)
        XCTAssertNil(HealthKitService.sleepStage(999))
    }

    func testEveryMetricHasTypeAndCompatibleUnit() {
        for kind in MetricKind.allCases {
            let type = HealthKitService.quantityType(kind)
            XCTAssertTrue(type.is(compatibleWith: HealthKitService.unit(kind)), "\(kind)")
            XCTAssertEqual(type.aggregationStyle == .cumulative, kind.isCumulative, "\(kind)")
        }
    }

    func testReadTypesCoverAllMetrics() {
        let read = HealthKitService.readTypes
        for kind in MetricKind.allCases { XCTAssertTrue(read.contains(HealthKitService.quantityType(kind))) }
        XCTAssertTrue(read.contains(HKCategoryType(.sleepAnalysis)))
        XCTAssertTrue(read.contains(HKObjectType.workoutType()))
    }

    func testActivityRoundTrip() {
        for a in WorkoutActivity.allCases {
            XCTAssertEqual(HealthKitService.activity(HealthKitService.hkActivity(a)), a)
        }
    }
}

final class SnapshotTests: XCTestCase {
    func testSnapshotRoundTrip() throws {
        let s = WidgetSnapshot.placeholder
        let d = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: d), s)
    }

    func testDemoProviderIsLabelled() async {
        let b = await DemoDataProvider().load(days: 30, now: Date(), calendar: .current, profile: ScoringProfile())
        XCTAssertTrue(b.isDemo)
        XCTAssertEqual(b.history.count, 30)
    }

    @MainActor
    func testExternalPayloadIsMinimal() async {
        let b = await DemoDataProvider().load(days: 40, now: Date(), calendar: .current, profile: ScoringProfile())
        let a = WellnessEngine(calendar: .current, profile: ScoringProfile())
            .assess(day: DayKey(Date(), calendar: .current), history: b.history, intraday: b.intraday, now: Date(), isDemo: true)
        let p = ExternalAssistant.previewPayload(question: "q", assessment: a)
        XCTAssertFalse(p.contains(DemoDataGenerator.sourceID))
        XCTAssertFalse(p.contains("start"))
        XCTAssertFalse(Suggestions.make(a, goals: GoalSet()).isEmpty)
    }
}
