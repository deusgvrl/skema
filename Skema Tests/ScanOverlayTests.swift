//
//  ScanOverlayTests.swift
//  Skema Tests
//
//  A10-62 test cases 1–26 (written in the A10-62 Jira issue).
//  Camera: 1920 x 1440 sideways picture, fx = fy = 1000, centre (960, 720), shown upright (portrait).
//  The screen is 1440 x 1920, the same size as the upright picture, so its centre is (720, 960).
//

import CoreGraphics
import MeasureKit
import simd
import Testing
@testable import Final_Challenge_App

private let screen = CGSize(width: 1440, height: 1920)
private let mask = InstanceMask(width: 1, height: 1, pixels: [1])

private func camera(facingBack: Bool = false) -> CameraModel {
    var intrinsics = matrix_identity_float3x3
    intrinsics[0][0] = 1000
    intrinsics[1][1] = 1000
    intrinsics[2][0] = 960
    intrinsics[2][1] = 720
    var pose = matrix_identity_float4x4
    if facingBack {
        pose.columns.0 = SIMD4(-1, 0, 0, 0)
        pose.columns.2 = SIMD4(0, 0, -1, 0)
    }
    return CameraModel(intrinsics: intrinsics, imageResolution: SIMD2(1920, 1440), cameraToWorld: pose)
}

/// An item 1 m straight in front of the default camera unless another position is given.
private func item(_ label: String, _ status: ItemStatus, number: Int? = nil, progress: Double = 0,
                  isSeen: Bool = true, at position: SIMD3<Float> = SIMD3(0, 0, -1), id: Int = 0) -> TrackedItem {
    TrackedItem(id: id, label: label, status: status, number: number, position: position,
                progress: progress, isSeen: isSeen)
}

private func acceptedCamera(_ number: Int, id: Int) -> TrackedItem {
    item("Camera", .accepted, number: number, progress: 1, id: id)
}

private func acceptedLight(_ number: Int, id: Int) -> TrackedItem {
    item("studio lighting", .accepted, number: number, progress: 1, id: id)
}

private func overlay(_ items: [TrackedItem], masks: [Int: InstanceMask] = [:], subject: SIMD3<Float>? = nil,
                     camera: CameraModel = camera()) -> ScanOverlay {
    ScanOverlay(items: items, masks: masks, subject: subject, camera: camera, screenSize: screen)
}

@Suite("Scan overlay")
struct ScanOverlayTests {
    // MARK: Pending items

    @Test("Case 1: a light that was just found shows an empty ring and Detecting…, with no number")
    func justFoundLightShowsEmptyRing() {
        let shown = overlay([item("studio lighting", .pending, progress: 0)]).items
        #expect(shown.map(\.ring) == [0])
        #expect(shown.map(\.tag) == ["Detecting…"])
    }

    @Test("Case 2: a pending light seen for 0.5 s has a half-full ring")
    func pendingLightHasHalfRing() {
        let shown = overlay([item("studio lighting", .pending, progress: 0.5)]).items
        #expect(shown.map(\.ring) == [0.5])
        #expect(shown.map(\.tag) == ["Detecting…"])
    }

    @Test("Case 3: no text shows a confidence %")
    func noTextShowsAPercent() {
        let items = [item("studio lighting", .pending, progress: 0.62, id: 0), acceptedCamera(1, id: 1)]
        let built = overlay(items, subject: SIMD3(0, 0, -2))
        let texts = built.items.map(\.tag) + [built.subject?.tag ?? ""] + built.chips
        #expect(!texts.isEmpty)
        #expect(texts.allSatisfy { !$0.contains("%") })
    }

    @Test("Case 21: a pending item not seen at this look has no mask, but its ring and Detecting… stay")
    func unseenPendingItemKeepsRing() {
        let shown = overlay([item("studio lighting", .pending, progress: 0.5, isSeen: false)], masks: [0: mask]).items
        #expect(shown.map(\.mask) == [nil])
        #expect(shown.map(\.ring) == [0.5])
        #expect(shown.map(\.tag) == ["Detecting…"])
    }

    // MARK: Accepted items

    @Test("Case 4: an accepted camera, number 1, shows Camera 1 ✓ and no ring")
    func acceptedCameraTag() {
        let shown = overlay([acceptedCamera(1, id: 0)]).items
        #expect(shown.map(\.tag) == ["Camera 1 ✓"])
        #expect(shown.map(\.ring) == [nil])
    }

    @Test("Case 5: an accepted light, number 2, shows Studio Lighting 2 ✓ and no ring")
    func acceptedLightTag() {
        let shown = overlay([acceptedLight(2, id: 0)]).items
        #expect(shown.map(\.tag) == ["Studio Lighting 2 ✓"])
        #expect(shown.map(\.ring) == [nil])
    }

    // MARK: Masks

    @Test("Case 6: a pending item seen at this look has a white mask")
    func pendingMaskIsWhite() {
        let shown = overlay([item("studio lighting", .pending, progress: 0.3)], masks: [0: mask]).items
        #expect(shown.map(\.mask) == [mask])
        #expect(shown.map(\.maskColor) == [.white])
    }

    @Test("Case 7: an accepted item seen at this look has a green mask")
    func acceptedMaskIsGreen() {
        let shown = overlay([acceptedCamera(1, id: 0)], masks: [0: mask]).items
        #expect(shown.map(\.mask) == [mask])
        #expect(shown.map(\.maskColor) == [.green])
    }

    @Test("Case 8: an accepted item not seen at this look has no mask")
    func unseenAcceptedItemHasNoMask() {
        let unseen = item("Camera", .accepted, number: 1, progress: 1, isSeen: false)
        #expect(overlay([unseen], masks: [0: mask]).items.map(\.mask) == [nil])
    }

    // MARK: Tag position

    @Test("Case 9: an item 1 m straight in front has its tag at the centre of the screen")
    func tagInFrontIsAtTheCentre() {
        #expect(overlay([acceptedCamera(1, id: 0)]).items.map(\.tagPosition) == [CGPoint(x: 720, y: 960)])
    }

    @Test("Case 10: an item behind the camera has no tag on screen")
    func itemBehindHasNoTag() {
        let behind = item("Camera", .accepted, number: 1, progress: 1, at: SIMD3(0, 0, 1))
        #expect(overlay([behind]).items.map(\.tagPosition) == [nil])
    }

    @Test("Case 22: an item beside the camera, outside the picture, has no tag on screen")
    func itemBesideHasNoTag() {
        let beside = item("Camera", .accepted, number: 1, progress: 1, at: SIMD3(5, 0, -1))
        #expect(overlay([beside]).items.map(\.tagPosition) == [nil])
    }

    @Test("Case 23: an item almost touching the camera gives no crash and no tag")
    func itemTouchingHasNoTag() {
        let touching = item("Camera", .accepted, number: 1, progress: 1, at: SIMD3(0, 0, -0.001))
        #expect(overlay([touching]).items.map(\.tagPosition) == [nil])
    }

    @Test("Case 11: an accepted item that left the view gets its tag back when the camera turns back")
    func tagComesBackWhenTheCameraReturns() {
        let light = item("studio lighting", .accepted, number: 1, progress: 1, isSeen: false)
        #expect(overlay([light], camera: camera(facingBack: true)).items.map(\.tagPosition) == [nil])
        #expect(overlay([light], camera: camera()).items.map(\.tagPosition) == [CGPoint(x: 720, y: 960)])
    }

    // MARK: Subject

    @Test("Case 24: a chosen subject has the tag Subject ✓ at its spot, with no ring and no mask")
    func subjectTag() throws {
        let subject = try #require(overlay([], subject: SIMD3(0, 0, -1)).subject)
        #expect(subject.tag == "Subject ✓")
        #expect(subject.tagPosition == CGPoint(x: 720, y: 960))
        #expect(subject.ring == nil)
        #expect(subject.mask == nil)
    }

    @Test("Case 25: a chosen subject has the chip Subject • 1")
    func subjectChip() {
        #expect(overlay([], subject: SIMD3(0, 0, -1)).chips == ["Subject • 1"])
    }

    @Test("Case 26: no subject, no subject chip")
    func noSubjectNoChip() {
        let built = overlay([acceptedCamera(1, id: 0)])
        #expect(built.subject == nil)
        #expect(built.chips == ["Camera • 1"])
    }

    // MARK: Chips

    @Test("Case 12: one chip per kind with the sum of accepted items, in the order Subject, Camera, Studio Lighting")
    func chipsPerKind() {
        let items = [acceptedLight(1, id: 0), acceptedCamera(1, id: 1), acceptedLight(2, id: 2),
                     acceptedCamera(2, id: 3), acceptedLight(3, id: 4)]
        #expect(overlay(items, subject: SIMD3(0, 0, -1)).chips == ["Subject • 1", "Camera • 2", "Studio Lighting • 3"])
        #expect(overlay(items).chips == ["Camera • 2", "Studio Lighting • 3"])
    }

    @Test("Case 13: a pending light is not counted in the chip")
    func pendingNotCounted() {
        let items = [acceptedCamera(1, id: 0), acceptedCamera(2, id: 1), acceptedLight(1, id: 2),
                     acceptedLight(2, id: 3), acceptedLight(3, id: 4),
                     item("studio lighting", .pending, progress: 0.4, id: 5)]
        #expect(overlay(items).chips == ["Camera • 2", "Studio Lighting • 3"])
    }

    @Test("Case 14: no accepted camera, no camera chip")
    func noCameraChip() {
        let items = [acceptedLight(1, id: 0), item("Camera", .pending, progress: 0.4, id: 1)]
        #expect(overlay(items).chips == ["Studio Lighting • 1"])
    }

    @Test("Case 15: an accepted camera out of view is still counted")
    func outOfViewStillCounted() {
        let away = item("Camera", .accepted, number: 1, progress: 1, isSeen: false, at: SIMD3(0, 0, 1))
        #expect(overlay([away]).chips == ["Camera • 1"])
    }

    // MARK: Finish Scan

    @Test("Case 16: Finish Scan is enabled with 1 subject, 1 accepted camera and 1 accepted light")
    func finishEnabled() {
        #expect(overlay([acceptedCamera(1, id: 0), acceptedLight(1, id: 1)], subject: SIMD3(0, 0, -1)).canFinish)
    }

    @Test("Case 17: no Finish Scan without a subject")
    func noFinishWithoutSubject() {
        #expect(!overlay([acceptedCamera(1, id: 0), acceptedLight(1, id: 1)]).canFinish)
    }

    @Test("Case 18: no Finish Scan without an accepted camera")
    func noFinishWithoutCamera() {
        #expect(!overlay([acceptedLight(1, id: 0)], subject: SIMD3(0, 0, -1)).canFinish)
    }

    @Test("Case 19: no Finish Scan without an accepted light")
    func noFinishWithoutLight() {
        #expect(!overlay([acceptedCamera(1, id: 0)], subject: SIMD3(0, 0, -1)).canFinish)
    }

    @Test("Case 20: a light that is still pending doesn't count for Finish Scan")
    func pendingLightDoesNotCountForFinish() {
        let items = [acceptedCamera(1, id: 0), item("studio lighting", .pending, progress: 0.9, id: 1)]
        #expect(!overlay(items, subject: SIMD3(0, 0, -1)).canFinish)
    }
}
