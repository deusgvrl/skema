//
//  ScanTutorial.swift
//  Final Challenge App
//
//  The steps of the tutorial shown before a scan. The scan needs the subject tapped, the floor seen,
//  and each light and camera tapped within LiDAR's range (5 m) until its tag says Saved.
//

import Foundation

enum ScanTutorialStep: Int, CaseIterable, Identifiable {
    case tapSubject
    case showFloor
    case tapEachItem
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tapSubject: "Tap your product"
        case .showFloor: "Show the floor"
        case .tapEachItem: "Tap each light and camera"
        case .finish: "Tap Finish Scan"
        }
    }

    var message: String {
        switch self {
        case .tapSubject:
            "With Subject picked at the bottom, point at the product and tap it. Every distance is measured from it."
        case .showFloor:
            "Tilt down until the floor is in view. Heights are measured from it."
        case .tapEachItem:
            "Pick Light or Camera at the bottom, then tap the item. Stay within 5 m so LiDAR can measure it; "
                + "its tag says Saved when it’s done."
        case .finish:
            "Once the subject, a camera and a light are saved, you’re done."
        }
    }

    var isLast: Bool { self == Self.allCases.last }

    var next: ScanTutorialStep? { ScanTutorialStep(rawValue: rawValue + 1) }

    var primaryButtonTitle: String { isLast ? "Start Scanning" : "Next" }

    var positionLabel: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }
}
