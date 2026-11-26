//
//  OutlineInboxTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  The hand-over from the main thread to the render thread (A10-121, step 4): the render side gets the newest
//  outlines and the newest view size (R10).
//

import CoreGraphics
import Foundation
import MeasureKit
import Testing
@testable import Skema_Photo

@Suite("Outline inbox")
struct OutlineInboxTests {
    @Test("R10: the render side reads the newest outlines and the newest view size")
    func readsTheNewestValues() {
        let inbox = OutlineInbox()
        let older = [UUID(): WorldBox(min: SIMD3(0, 0, 0), max: SIMD3(1, 1, 1))]
        let newer = [UUID(): WorldBox(min: SIMD3(2, 2, 2), max: SIMD3(3, 3, 3))]

        inbox.setOutlines(older)
        inbox.setViewSize(CGSize(width: 390, height: 844))
        inbox.setOutlines(newer)
        inbox.setViewSize(CGSize(width: 844, height: 390))
        let seen = inbox.snapshot()

        #expect(seen.outlines == newer)
        #expect(seen.viewSize == CGSize(width: 844, height: 390))
    }

    @Test("R10: a new inbox has no outlines and a zero view size")
    func startsEmpty() {
        let seen = OutlineInbox().snapshot()

        #expect(seen.outlines.isEmpty)
        #expect(seen.viewSize == .zero)
    }
}
