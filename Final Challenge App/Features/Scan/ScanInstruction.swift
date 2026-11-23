//
//  ScanInstruction.swift
//  Final Challenge App
//
//  The scan screen's one centred instruction, like Apple's Measure (copy approved 23 Nov 2026): the current step, a
//  short "done" line after it, a problem while it lasts, or what the last tap did. One at a time.
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
    /// 1.5 s after a tap, what it set was only seen farther than 5 m.
    case tooFar
    /// 1.5 s after a tap, what it set still has too few LiDAR points.
    case needsCloserLook

    var main: String {
        switch self {
        case .pointAtFloorFirst: "Point at the floor first"
        case .cannotMeasure: "Can't measure that spot"
        case .alreadyAdded(let light): "Light \(light) already added"
        case .tooFar: "Too far to measure"
        case .needsCloserLook: "Need a closer look"
        }
    }

    var detail: String? {
        switch self {
        case .cannotMeasure: "Tap a spot nearer to you"
        case .tooFar: "Walk closer, within 5 m"
        case .needsCloserLook: "Walk closer and hold still"
        case .pointAtFloorFirst, .alreadyAdded: nil
        }
    }

    /// The SF Symbol shown above the line while the camera dims.
    var symbol: String {
        switch self {
        case .pointAtFloorFirst: "arrow.down.to.line"
        case .cannotMeasure: "exclamationmark.triangle.fill"
        case .alreadyAdded: "checkmark.circle.fill"
        case .tooFar: "figure.walk"
        case .needsCloserLook: "circle.dotted"
        }
    }
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

    /// What shows now, in this order: what the last tap did, then a step that was just done, then a problem, then the
    /// current step. Each keeps its small line, so the user always sees why or what to do first.
    static func current(step: ScanStep, completed: ScanStep?, problem: ScanGuidance?,
                        feedback: ScanFeedback?) -> ScanInstruction {
        if let feedback {
            return ScanInstruction(main: feedback.main, detail: feedback.detail, style: .feedback,
                                   symbol: feedback.symbol)
        }
        if let done = completed?.doneTitle {
            return ScanInstruction(main: done, detail: nil, style: .done)
        }
        if let problem {
            return ScanInstruction(main: problem.message, detail: problem.detail, style: .problem,
                                   symbol: problem.symbol)
        }
        return ScanInstruction(main: step.title, detail: step.detail, style: .step)
    }
}
