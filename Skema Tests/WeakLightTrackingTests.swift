import CoreGraphics
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

/// A10-90 cases D21–D23 through the tracker: weak lights only keep accepted items.
@Suite("Weak lights in the tracker")
struct WeakLightTrackingTests {
    private let camera = CameraModel(intrinsics: simd_float3x3(diagonal: SIMD3(10, 10, 1)),
                                     imageResolution: SIMD2(20, 20), cameraToWorld: matrix_identity_float4x4)
    private let depth = DepthFrame(width: 20, height: 20, depth: [Float](repeating: 1, count: 400),
                                   confidence: [UInt8](repeating: 2, count: 400))
    private let mask = InstanceMask(width: 20, height: 20, pixels: [UInt8](repeating: 1, count: 400))
    private let screen = CGSize(width: 100, height: 100)

    private func light(weak: Bool) -> EquipmentDetection {
        EquipmentDetection(kind: .studioLighting, confidence: weak ? 0.4 : 0.8, mask: mask, isWeak: weak)
    }

    @Test("Case D22–D23: a weak light with no accepted light near it makes no item and nothing is drawn")
    func weakLightStartsNothing() {
        var tracker = EquipmentTracker()
        for index in 0...20 { tracker.look([light(weak: true)], depth: depth, camera: camera, at: Double(index) / 10) }

        #expect(tracker.overlay(subject: nil, screenSize: screen)?.items.isEmpty == true)
    }

    @Test("Case D21: a weak sighting on an accepted light counts as seen")
    func weakLightKeepsAcceptedItem() {
        var tracker = EquipmentTracker()
        for index in 0...11 { tracker.look([light(weak: false)], depth: depth, camera: camera, at: Double(index) / 10) }
        #expect(tracker.overlay(subject: nil, screenSize: screen)?.items.count == 1)

        tracker.look([light(weak: true)], depth: depth, camera: camera, at: 1.2)

        let items = tracker.overlay(subject: nil, screenSize: screen)?.items
        #expect(items?.count == 1)
        #expect(items?.first?.mask != nil)   // drawn now, so seen at this look
    }
}
