//
//  ScanTutorial.swift
//  Final Challenge App
//
//  The steps of the tutorial shown before a scan. The scan needs the subject tapped, the floor seen,
//  and each light and camera held in view until it turns green; nobody has to walk around the set.
//

import Foundation

enum ScanTutorialStep: Int, CaseIterable, Identifiable {
    case tapSubject
    case showFloor
    case turnToEachItem
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tapSubject: "Tap your product"
        case .showFloor: "Show the floor"
        case .turnToEachItem: "Turn to each light and camera"
        case .finish: "Tap Finish Scan"
        }
    }

    var message: String {
        switch self {
        case .tapSubject:
            "Point at the product and tap it. Every distance is measured from it."
        case .showFloor:
            "Tilt down until the floor is in view. Heights are measured from it."
        case .turnToEachItem:
            "Stay where you are and hold each one in view until its tag turns green. No need to walk around the set."
        case .finish:
            "Once the subject, a camera and a light are captured, you’re done."
        }
    }

    var isLast: Bool { self == Self.allCases.last }

    var next: ScanTutorialStep? { ScanTutorialStep(rawValue: rawValue + 1) }

    var primaryButtonTitle: String { isLast ? "Start Scanning" : "Next" }

    var positionLabel: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }
}
