//
//  FrameThrottleTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import Testing
@testable import Final_Challenge_App

@Suite("Frame throttle")
struct FrameThrottleTests {
    @Test("The first frame always goes through")
    func firstFrameAccepted() {
        var throttle = FrameThrottle(minimumInterval: 0.1)

        let accepted = throttle.accepts(5.0)

        #expect(accepted)
    }

    @Test("A frame sooner than the interval is dropped")
    func earlyFrameDropped() {
        var throttle = FrameThrottle(minimumInterval: 0.1)
        _ = throttle.accepts(5.0)

        let accepted = throttle.accepts(5.05)

        #expect(!accepted)
    }

    @Test("A frame at the interval goes through, even 0.5 ms early")
    func frameAtIntervalAccepted() {
        var throttle = FrameThrottle(minimumInterval: 0.1)
        _ = throttle.accepts(5.0)

        let accepted = throttle.accepts(5.0995)

        #expect(accepted)
    }

    @Test("60 frames per second become 15")
    func sixtyBecomesFifteen() {
        var throttle = FrameThrottle(minimumInterval: 1.0 / 15.0)

        let accepted = (0..<60).filter { throttle.accepts(Double($0) / 60.0) }

        #expect(accepted.count == 15)
    }

    @Test("A frame older than the last one is dropped")
    func olderFrameDropped() {
        var throttle = FrameThrottle(minimumInterval: 0.1)
        _ = throttle.accepts(5.0)

        let older = throttle.accepts(1.0)
        let next = throttle.accepts(5.1)

        #expect(!older)
        #expect(next)
    }
}
