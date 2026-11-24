//
//  ScanInstruction.swift
//  Final Challenge App
//
//  The scan screen's one instruction (layout A, 24 Nov 2026): what the last tap did, a problem while it lasts, a short
//  "done" line, the item being scanned, or the current step. One at a time, in that order (the priority ladder in the
//  scan screen report).
//

import Foundation

/// What the last tap did when it set nothing new; it shows for a moment instead of the step.
enum ScanFeedback: Equatable {
    /// A tap before the floor is found.
    case pointAtFloorFirst
    /// No LiDAR depth under the tap.
    case cannotMeasure
    /// A light tap inside a light's grown box (A10-106): that light again, not a new one.
    case alreadyAdded(light: Int)
    /// A tap while an item is still being scanned (the hard gate, phase 3): the item's name, "Light 1", "the camera".
    case finishFirst(String)
    /// Finish Scan before the scan can finish: what to add first.
    case addFirst(ScanTapKind)

    var main: String {
        switch self {
        case .pointAtFloorFirst: "Point at the floor first"
        case .cannotMeasure: "Can't measure that spot"
        case .alreadyAdded(let light): "Light \(light) already added"
        case .finishFirst(let name): "Finish \(name) first"
        case .addFirst(.subject): "Add the subject first"
        case .addFirst(.camera): "Add the camera first"
        case .addFirst(.light): "Add a light first"
        }
    }

    var detail: String? {
        switch self {
        case .cannotMeasure: "Tap a spot nearer to you"
        case .finishFirst: "Walk around it until its tag turns green"
        case .pointAtFloorFirst, .alreadyAdded, .addFirst: nil
        }
    }

    /// The SF Symbol shown above the line while the camera dims.
    var symbol: String {
        switch self {
        case .pointAtFloorFirst: "arrow.down.to.line"
        case .cannotMeasure: "exclamationmark.triangle.fill"
        case .alreadyAdded: "checkmark.circle.fill"
        case .finishFirst: "figure.walk"
        case .addFirst: "plus.circle.fill"
        }
    }
}

/// A short line once something is done: the floor found, or an item scanned (seen from far enough around).
enum ScanDone: Equatable {
    case floor
    case subject
    /// A camera or a light, by its name: "Camera", "Light 1".
    case item(String)

    var line: String {
        switch self {
        case .floor: "Floor found"
        case .subject: "Subject done"
        case .item(let name): "\(name) done"
        }
    }
}

/// The item tapped but not done yet: the instruction asks to walk around it, or closer while it is out of range.
struct ScanScanning: Equatable {
    /// "Light 1", "the camera", "the subject".
    let name: String
    /// Only seen beyond 5 m so far.
    let isTooFar: Bool
}

/// The one line (and an optional small line) in the middle of the scan screen.
struct ScanInstruction: Hashable {
    enum Style: Hashable {
        case step
        case done
        case problem
        case feedback
    }

    let main: String
    let detail: String?
    let style: Style
    /// The SF Symbol above a blocking line (Measure's coaching look); nil for steps and done lines.
    var symbol: String?

    /// A problem or what a tap did: the user is held up, so the camera dims behind an icon and the line, as in
    /// Measure's coaching screen. Steps and done lines stay plain text, so the items stay easy to see and tap.
    var isBlocking: Bool { style == .problem || style == .feedback }

    /// What shows now, in this order (24 Nov ladder): what the last tap did, then a problem, then something just done,
    /// then the item being scanned, then the current step. Each keeps its small line, so the user always sees why or
    /// what to do first.
    static func current(step: ScanStep, done: ScanDone?, problem: ScanGuidance?, feedback: ScanFeedback?,
                        scanning: ScanScanning?) -> ScanInstruction {
        if let feedback {
            return ScanInstruction(main: feedback.main, detail: feedback.detail, style: .feedback,
                                   symbol: feedback.symbol)
        }
        if let problem {
            return ScanInstruction(main: problem.message, detail: problem.detail, style: .problem,
                                   symbol: problem.symbol)
        }
        if let done {
            return ScanInstruction(main: done.line, detail: nil, style: .done)
        }
        if let scanning, scanning.isTooFar {
            return ScanInstruction(main: "Walk closer to \(scanning.name)", detail: "It's more than 5 m away",
                                   style: .step)
        }
        if let scanning {
            return ScanInstruction(main: "Walk around \(scanning.name)",
                                   detail: "Keep it in view until its tag turns green", style: .step)
        }
        return ScanInstruction(main: step.title, detail: step.detail, style: .step)
    }
}
