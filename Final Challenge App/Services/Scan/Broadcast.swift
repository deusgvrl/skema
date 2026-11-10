//
//  Broadcast.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import Synchronization

nonisolated final class Broadcast<Element: Sendable>: Sendable {
    private struct Listeners {
        var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
        var isFinished = false
    }

    private let bufferSize: Int
    private let listeners = Mutex(Listeners())

    init(bufferSize: Int = 1) {
        self.bufferSize = bufferSize
    }

    var listenerCount: Int {
        listeners.withLock { $0.continuations.count }
    }

    func stream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Element.self,
            bufferingPolicy: .bufferingNewest(bufferSize)
        )
        let id = UUID()
        let added = listeners.withLock { current -> Bool in
            guard !current.isFinished else { return false }
            current.continuations[id] = continuation
            return true
        }
        guard added else {
            continuation.finish()
            return stream
        }
        continuation.onTermination = { [weak self] _ in
            self?.listeners.withLock { current in
                current.continuations[id] = nil
            }
        }
        return stream
    }

    func yield(_ value: Element) {
        let continuations = listeners.withLock { Array($0.continuations.values) }
        for continuation in continuations {
            continuation.yield(value)
        }
    }

    func finish() {
        let continuations = listeners.withLock { current in
            current.isFinished = true
            let all = Array(current.continuations.values)
            current.continuations.removeAll()
            return all
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}
