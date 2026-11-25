//
//  ScanTutorial.swift
//  Final Challenge App
//
//  The guided tap scan (Sketch UT Review T01–T10): the floor, the subject, the camera, each light, then Finish.
//  The floor is found by pointing the phone at it (A10-112, no tap); each tap then sets the next thing still missing,
//  so the photographer never picks what a tap means.
//

import Foundation

/// One step of the guided scan, in order. The floor step has no tap: it is done once ARKit finds the floor.
enum ScanStep: Int, CaseIterable {
    case floor
    case subject
    case camera
    case light
    case finish

    /// The instruction's line for this step (copy decided 24 Nov 2026).
    var title: String {
        switch self {
        case .floor: "Point at the floor"
        case .subject: "Tap the subject"
        case .camera: "Tap the camera"
        case .light: "Tap a light"
        case .finish: "Tap the next light"
        }
    }

    /// The small line under it: why the step matters, or what to do first.
    var detail: String {
        switch self {
        case .floor: "Heights are measured from it"
        case .subject, .camera, .light: "Walk up to it first"
        case .finish: "Or tap Finish Scan if that’s all"
        }
    }

    /// What a tap sets in this step: nothing on the floor step (the floor is found, not tapped). After the first light,
    /// taps keep adding lights.
    var tapKind: ScanTapKind? {
        switch self {
        case .floor: nil
        case .subject: .subject
        case .camera: .camera
        case .light, .finish: .light
        }
    }

    /// The first thing still missing, always in the same order.
    static func current(hasFloor: Bool, hasSubject: Bool, cameras: Int, lights: Int) -> ScanStep {
        if !hasFloor { return .floor }
        if !hasSubject { return .subject }
        if cameras == 0 { return .camera }
        if lights == 0 { return .light }
        return .finish
    }
}
