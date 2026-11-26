//
//  RenderThread.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  A thread with its own run loop, for drawing the scan view off the main thread (A10-121, step 4). It has one job:
//  own a thread. The display link and the renderer live on it.
//

import Foundation
import Synchronization

/// A thread that runs its own run loop until `stop()`. `start()` returns when the loop is ready, so `perform(_:)`
/// works right away. Call `start()` once.
nonisolated final class RenderThread: Sendable {
    /// `Thread` and `CFRunLoop` are not marked `Sendable`, but the calls made on them across threads here
    /// (`isFinished`, `CFRunLoopPerformBlock`, `CFRunLoopWakeUp`) are meant to be called from any thread, and the
    /// lock guards the stored references.
    private struct State {
        var thread: UncheckedSendable<Thread>?
        var runLoop: UncheckedSendable<CFRunLoop>?
        var isStopRequested = false
    }

    private let state = Mutex(State())

    /// True when the thread was started and its run loop has ended.
    var isFinished: Bool {
        state.withLock { $0.thread?.value.isFinished ?? false }
    }

    /// Starts the thread and waits until its run loop is ready.
    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let runLoop = RunLoop.current
            // A run loop with no source ends at once. An empty port keeps it open until `stop()`.
            runLoop.add(Port(), forMode: .default)
            let loop = UncheckedSendable(runLoop.getCFRunLoop())
            state.withLock { $0.runLoop = loop }
            ready.signal()
            while !state.withLock({ $0.isStopRequested }) {
                runLoop.run(mode: .default, before: .distantFuture)
            }
        }
        thread.name = "ScanRenderThread"
        thread.qualityOfService = .userInteractive
        let stored = UncheckedSendable(thread)
        state.withLock { $0.thread = stored }
        thread.start()
        ready.wait()
    }

    /// Runs `block` on this thread, in the order of calls. It does nothing when the thread is not started or stopped.
    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop = state.withLock({ $0.runLoop?.value }) else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Ends the run loop after the blocks that were queued before this call. The thread then ends.
    func stop() {
        perform { [self] in
            // No run loop any more: a later `perform` does nothing and keeps nothing.
            state.withLock {
                $0.isStopRequested = true
                $0.runLoop = nil
            }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }
}
