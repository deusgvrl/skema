// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeasureKit",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "MeasureKit", targets: ["MeasureKit"]),
    ],
    targets: [
        // Pure maths: no UI, no ARKit, no Vision. Runs and tests on the Mac.
        .target(name: "MeasureKit"),
        .testTarget(name: "MeasureKitTests", dependencies: ["MeasureKit"]),
    ],
    // Same as the PoC package, so its code moves in unchanged.
    swiftLanguageModes: [.v5]
)
