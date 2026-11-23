//
//  ScanInstructionTests.swift
//  Skema Tests
//
//  The scan screen's one centred instruction, like Apple's Measure (copy approved 23 Nov 2026): the current step, a
//  short "done" line, a problem, or what a tap did; one at a time, in that order of priority (feedback first).
//

import Testing
@testable import Skema_Photo

@MainActor
@Suite("Scan instruction")
struct ScanInstructionTests {
    private func instruction(step: ScanStep = .floor, completed: ScanStep? = nil, problem: ScanGuidance? = nil,
                             feedback: ScanFeedback? = nil) -> ScanInstruction {
        ScanInstruction.current(step: step, completed: completed, problem: problem, feedback: feedback)
    }

    // MARK: Steps

    @Test("Each step has its line and a small line saying why", arguments: [
        (ScanStep.floor, "Point at the floor", "Heights are measured from it"),
        (.subject, "Tap your product", "Distances are measured from it"),
        (.camera, "Tap the camera", "Walk up to it first"),
        (.light, "Tap each light", "Walk up to each one"),
        (.finish, "Tap Finish Scan", "Or tap another light first")
    ])
    func steps(step: ScanStep, main: String, detail: String) {
        #expect(instruction(step: step) == ScanInstruction(main: main, detail: detail, style: .step))
    }

    // MARK: Done

    @Test("A step that was just done says so", arguments: [
        (ScanStep.floor, "Floor found"), (.subject, "Subject set"), (.camera, "Camera added"), (.light, "Light added")
    ])
    func done(step: ScanStep, main: String) {
        #expect(instruction(step: .finish, completed: step) == ScanInstruction(main: main, detail: nil, style: .done))
    }

    // MARK: Problems

    @Test("Each problem has its lines", arguments: [
        (ScanGuidance.moreLight, ["More light needed"]),
        (.moveCloser, ["Move closer"]),
        (.floorNotFound, ["Floor not found yet", "Tilt down and move closer to it"])
    ])
    func problems(problem: ScanGuidance, lines: [String]) {
        let shown = instruction(problem: problem)

        #expect(shown.main == lines[0] && shown.detail == lines.dropFirst().first && shown.style == .problem)
    }

    // MARK: After a tap

    @Test("What a tap did has its lines", arguments: [
        (ScanFeedback.pointAtFloorFirst, ["Point at the floor first"]),
        (.cannotMeasure, ["Can't measure that spot", "Tap a spot nearer to you"]),
        (.alreadyAdded(light: 1), ["Light 1 already added"]),
        (.alreadyAdded(light: 3), ["Light 3 already added"]),
        (.tooFar, ["Too far to measure", "Walk closer, within 5 m"]),
        (.needsCloserLook, ["Need a closer look", "Walk closer and hold still"])
    ])
    func feedback(feedback: ScanFeedback, lines: [String]) {
        let shown = instruction(feedback: feedback)

        #expect(shown.main == lines[0] && shown.detail == lines.dropFirst().first && shown.style == .feedback)
    }

    // MARK: Measure's look

    @Test("Problems and what a tap did block: the camera dims; steps and done lines do not")
    func blocking() {
        #expect(instruction(problem: .moreLight).isBlocking)
        #expect(instruction(feedback: .cannotMeasure).isBlocking)
        #expect(!instruction(step: .camera).isBlocking)
        #expect(!instruction(step: .camera, completed: .subject).isBlocking)
    }

    @Test("Each problem has its icon", arguments: [
        (ScanGuidance.moreLight, "lightbulb.max.fill"), (.moveCloser, "figure.walk"),
        (.floorNotFound, "arrow.down.to.line")
    ])
    func problemSymbols(problem: ScanGuidance, symbol: String) {
        #expect(instruction(problem: problem).symbol == symbol)
    }

    @Test("Each tap message has its icon; steps and done lines have none", arguments: [
        (ScanFeedback.pointAtFloorFirst, "arrow.down.to.line"), (.cannotMeasure, "exclamationmark.triangle.fill"),
        (.alreadyAdded(light: 2), "checkmark.circle.fill"), (.tooFar, "figure.walk"),
        (.needsCloserLook, "circle.dotted")
    ])
    func feedbackSymbols(feedback: ScanFeedback, symbol: String) {
        #expect(instruction(feedback: feedback).symbol == symbol)
        #expect(instruction(step: .light).symbol == nil)
        #expect(instruction(step: .finish, completed: .light).symbol == nil)
    }

    // MARK: Priority

    @Test("Only one line shows: what a tap did, then done, then a problem, then the step")
    func priority() {
        let all = instruction(step: .camera, completed: .subject, problem: .moreLight, feedback: .cannotMeasure)
        let noFeedback = instruction(step: .camera, completed: .subject, problem: .moreLight)
        let problemOnly = instruction(step: .camera, problem: .moreLight)

        #expect(all.main == "Can't measure that spot")
        #expect(noFeedback.main == "Subject set")
        #expect(problemOnly.main == "More light needed")
        #expect(instruction(step: .camera).main == "Tap the camera")
    }
}
