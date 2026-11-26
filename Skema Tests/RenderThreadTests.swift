//
//  RenderThreadTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  The render thread (A10-121, step 4): a block runs on it and not on the main thread (R8), and stop() ends it
//  (R9).
//

import Foundation
import Synchronization
import Testing
@testable import Skema_Photo

/// Waits until `condition` is true, at most `timeout` seconds. Returns whether it became true.
func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let end = Date.now.addingTimeInterval(timeout)
    while Date.now < end {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return condition()
}

/// A value one thread writes and the test reads after a semaphore tells it the write is done.
private final class Recorded<Value: Sendable>: Sendable {
    private let value = Mutex<Value?>(nil)
    func set(_ newValue: Value) { value.withLock { $0 = newValue } }
    var current: Value? { value.withLock { $0 } }
}

private final class Capture: Sendable {}

@Suite("Render thread")
struct RenderThreadTests {
    @Test("R8: a block runs on the render thread, not on the main thread")
    func blockRunsOffTheMainThread() {
        let thread = RenderThread()
        thread.start()
        defer { thread.stop() }
        let ranOnMain = Recorded<Bool>()
        let done = DispatchSemaphore(value: 0)

        thread.perform {
            ranOnMain.set(Thread.isMainThread)
            done.signal()
        }

        #expect(done.wait(timeout: .now() + 2) == .success, "The block did not run within 2 seconds")
        #expect(ranOnMain.current == false)
    }

    @Test("R9b: after the thread ended, perform does nothing and keeps nothing")
    func performAfterStopDoesNothing() throws {
        let thread = RenderThread()
        thread.start()
        thread.stop()
        try #require(waitUntil(timeout: 1) { thread.isFinished }, "The thread did not end within 1 second")
        let ran = Recorded<Bool>()
        weak var weakCapture: Capture?

        do {
            let capture = Capture()
            weakCapture = capture
            thread.perform {
                _ = capture
                ran.set(true)
            }
        }

        Thread.sleep(forTimeInterval: 0.05)
        #expect(ran.current == nil)
        // A block queued on the dead run loop would keep what it captured.
        #expect(weakCapture == nil, "The block was kept after stop()")
    }

    @Test("R9: stop() ends the thread within 1 second")
    func stopEndsTheThread() throws {
        let thread = RenderThread()
        thread.start()
        try #require(!thread.isFinished, "The thread must be running before stop()")

        thread.stop()

        #expect(waitUntil(timeout: 1) { thread.isFinished }, "The thread did not end within 1 second")
    }
}
