// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeasureKit",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "MeasureKit", targets: ["MeasureKit"]),
        .library(name: "MeasureKitVision", targets: ["MeasureKitVision"]),
    ],
    targets: [
        // Pure maths: no ARKit, no Vision. Runs and tests on the Mac.
        .target(name: "MeasureKit"),
        // Phase 1 detector: Apple Vision saliency + classification.
        .target(name: "MeasureKitVision", dependencies: ["MeasureKit"]),
        .testTarget(name: "MeasureKitTests", dependencies: ["MeasureKit"]),
        .testTarget(
            name: "MeasureKitVisionTests",
            dependencies: ["MeasureKitVision"],
            resources: [.copy("Fixtures"), .copy("YOLOFixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
