//
//  ScanTutorial.swift
//  Final Challenge App
//
//  The guided tap scan (Sketch UT Review T01–T10): the floor, the product, the camera, each light, then Finish.
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

    /// "STEP 1 OF 5", on the coaching panel.
    var positionLabel: String { "STEP \(rawValue + 1) OF \(Self.allCases.count)" }

    var title: String {
        switch self {
        case .floor: "Point at the floor"
        case .subject: "Tap your product"
        case .camera: "Tap the camera"
        case .light: "Tap each light"
        case .finish: "Tap Finish Scan"
        }
    }

    var message: String {
        switch self {
        case .floor: "Point the phone down at the floor until it's found. Heights are measured from it."
        case .subject: "Point at the product and tap it. Every distance is measured from it."
        case .camera: "Walk up to the camera and tap it. You can add more cameras in the plan."
        case .light: "Walk up to a light and tap it. Tap every light in the setup."
        case .finish: "Tap any other lights first, then finish."
        }
    }

    /// The green line once the step is done (the floor found, or the step's tap landed); nil for Finish.
    var doneTitle: String? {
        switch self {
        case .floor: "Floor found"
        case .subject: "Subject set"
        case .camera: "Camera added"
        case .light: "Light added"
        case .finish: nil
        }
    }

    /// The pill shown instead of the panel once the tutorial is done.
    var hint: String {
        self == .floor ? "Point at the floor to start" : title
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

    /// The step a tap of `kind` completes.
    init(completing kind: ScanTapKind) {
        switch kind {
        case .subject: self = .subject
        case .camera: self = .camera
        case .light: self = .light
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
