// swift-tools-version:5.9
import PackageDescription

// VitalFlowCore contains every platform-independent part of VitalFlow:
// data models, de-duplication, sleep merging, baselines and all wellness
// scores. It has no HealthKit/SwiftUI dependency so it builds and is unit
// tested on macOS, iOS, watchOS and Linux CI.
let package = Package(
    name: "VitalFlowCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "VitalFlowCore", targets: ["VitalFlowCore"])
    ],
    targets: [
        .target(name: "VitalFlowCore"),
        .testTarget(name: "VitalFlowCoreTests", dependencies: ["VitalFlowCore"])
    ]
)
