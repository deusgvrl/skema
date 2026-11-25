//
//  ScanInstructionTests.swift
//  Skema Tests
//
//  The scan screen's one instruction (layout A, copy decided 24 Nov 2026): what a tap did, a problem, a done line,
//  the item being scanned, or the current step; one at a time, in that order of priority.
//

import Testing
@testable import Skema_Photo

@MainActor
@Suite("Scan instruction")
struct ScanInstructionTests {
    private func instruction(step: ScanStep = .floor, done: ScanDone? = nil, problem: ScanGuidance? = nil,
                             feedback: ScanFeedback? = nil, scanning: ScanScanning? = nil) -> ScanInstruction {
        ScanInstruction.current(step: step, done: done, problem: problem, feedback: feedback, scanning: scanning)
    }

    // MARK: Steps

    @Test("Each step has its line and a small line saying why", arguments: [
        (ScanStep.floor, "Point at the floor", "Heights are measured from it"),
        (.subject, "Tap the subject", "Walk up to it first"),
        (.camera, "Tap the camera", "Walk up to it first"),
        (.light, "Tap a light", "Walk up to it first"),
        (.finish, "Tap the next light", "Or tap Finish Scan if that’s all")
    ])
    func steps(step: ScanStep, main: String, detail: String) {
        #expect(instruction(step: step) == ScanInstruction(main: main, detail: detail, style: .step))
    }

    // MARK: The item being scanned

    @Test("After a tap, the item being scanned asks to walk around it until it is done")
    func scanning() {
        let shown = instruction(step: .light, scanning: ScanScanning(name: "Light 1", isTooFar: false))

        #expect(shown == ScanInstruction(main: "Walk around Light 1",
                                         detail: "Keep it in view until its tag turns green", style: .step))
        #expect(instruction(scanning: ScanScanning(name: "the camera", isTooFar: false)).main
            == "Walk around the camera")
    }

    @Test("While the item is only seen beyond 5 m, it asks to walk closer")
    func scanningTooFar() {
        let shown = instruction(scanning: ScanScanning(name: "Light 1", isTooFar: true))

        #expect(shown.main == "Walk closer to Light 1" && shown.detail == "It’s more than 5 m away")
        #expect(!shown.isBlocking)
    }

    // MARK: Done

    @Test("An item that was just done says so", arguments: [
        (ScanDone.floor, "Floor found"), (.subject, "Subject done"), (.item("Camera"), "Camera done"),
        (.item("Light 2"), "Light 2 done")
    ])
    func done(done: ScanDone, main: String) {
        #expect(instruction(step: .finish, done: done) == ScanInstruction(main: main, detail: nil, style: .done))
    }

    // MARK: Problems

    @Test("Each problem has its lines", arguments: [
        (ScanGuidance.moreLight, ["More light needed", "Turn on more lights in the room"]),
        (.moveCloser, ["Move closer", "Everything is more than 5 m away"]),
        (.floorNotFound, ["Floor not found yet", "Tilt down and move closer to it"])
    ])
    func problems(problem: ScanGuidance, lines: [String]) {
        let shown = instruction(problem: problem)

        #expect(shown.main == lines[0] && shown.detail == lines.dropFirst().first && shown.style == .problem)
    }

    // MARK: After a tap

    @Test("What a tap did has its lines", arguments: [
        (ScanFeedback.pointAtFloorFirst, ["Point at the floor first"]),
        (.cannotMeasure, ["Can’t measure that spot", "Tap a spot nearer to you"]),
        (.alreadyAdded(light: 1), ["Light 1 already added"]),
        (.alreadyAdded(light: 3), ["Light 3 already added"]),
        (.finishFirst("Light 1"), ["Finish Light 1 first", "Walk around it until its tag turns green"]),
        (.finishFirst("the subject"), ["Finish the subject first", "Walk around it until its tag turns green"]),
        (.addFirst(.subject), ["Add the subject first"]),
        (.addFirst(.camera), ["Add the camera first"]),
        (.addFirst(.light), ["Add a light first"])
    ])
    func feedback(feedback: ScanFeedback, lines: [String]) {
        let shown = instruction(feedback: feedback)

        #expect(shown.main == lines[0] && shown.detail == lines.dropFirst().first && shown.style == .feedback)
    }

    // MARK: Measure's look

    @Test("Problems and what a tap did block: the camera dims; steps, done and scanning lines do not")
    func blocking() {
        #expect(instruction(problem: .moreLight).isBlocking)
        #expect(instruction(feedback: .cannotMeasure).isBlocking)
        #expect(!instruction(step: .camera).isBlocking)
        #expect(!instruction(step: .camera, done: .subject).isBlocking)
        #expect(!instruction(scanning: ScanScanning(name: "the camera", isTooFar: false)).isBlocking)
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
        (.alreadyAdded(light: 2), "checkmark.circle.fill"), (.finishFirst("Light 1"), "figure.walk"),
        (.addFirst(.camera), "plus.circle.fill")
    ])
    func feedbackSymbols(feedback: ScanFeedback, symbol: String) {
        #expect(instruction(feedback: feedback).symbol == symbol)
        #expect(instruction(step: .light).symbol == nil)
        #expect(instruction(step: .finish, done: .item("Light 1")).symbol == nil)
    }

    // MARK: Priority

    @Test("Only one line shows: tap message, problem, done line, item being scanned, step (24 Nov ladder)")
    func priority() {
        let scanning = ScanScanning(name: "the camera", isTooFar: false)
        let all = instruction(step: .camera, done: .subject, problem: .moreLight, feedback: .cannotMeasure,
                              scanning: scanning)
        let noFeedback = instruction(step: .camera, done: .subject, problem: .moreLight, scanning: scanning)
        let noProblem = instruction(step: .camera, done: .subject, scanning: scanning)

        #expect(all.main == "Can’t measure that spot")
        #expect(noFeedback.main == "More light needed")
        #expect(noProblem.main == "Subject done")
        #expect(instruction(step: .camera, scanning: scanning).main == "Walk around the camera")
        #expect(instruction(step: .camera).main == "Tap the camera")
    }
}
