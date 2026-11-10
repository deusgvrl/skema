//
//  BroadcastTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Testing
@testable import Final_Challenge_App

@Suite("Broadcast")
struct BroadcastTests {
    @Test("Every listener gets every value")
    func everyListenerGetsValues() async {
        let broadcast = Broadcast<Int>(bufferSize: 8)
        let first = broadcast.stream()
        let second = broadcast.stream()

        broadcast.yield(1)
        broadcast.yield(2)
        broadcast.finish()

        #expect(await collect(first) == [1, 2])
        #expect(await collect(second) == [1, 2])
    }

    @Test("A listener that falls behind keeps only the newest value")
    func slowListenerGetsNewest() async {
        let broadcast = Broadcast<Int>(bufferSize: 1)
        let stream = broadcast.stream()

        broadcast.yield(1)
        broadcast.yield(2)
        broadcast.yield(3)
        broadcast.finish()

        #expect(await collect(stream) == [3])
    }

    @Test("Values sent before a listener joins are not replayed")
    func noReplay() async {
        let broadcast = Broadcast<Int>(bufferSize: 8)
        broadcast.yield(1)
        let stream = broadcast.stream()

        broadcast.yield(2)
        broadcast.finish()

        #expect(await collect(stream) == [2])
    }

    @Test("After finish, new listeners end at once and values are dropped")
    func finishedBroadcast() async {
        let broadcast = Broadcast<Int>(bufferSize: 8)
        broadcast.finish()

        let stream = broadcast.stream()
        broadcast.yield(1)

        #expect(await collect(stream).isEmpty)
        #expect(broadcast.listenerCount == 0)
    }

    @Test("A listener that stops listening is removed")
    func cancelledListenerRemoved() async {
        let broadcast = Broadcast<Int>(bufferSize: 8)
        let task = Task {
            for await _ in broadcast.stream() {}
        }
        while broadcast.listenerCount == 0 {
            await Task.yield()
        }

        task.cancel()
        await task.value

        #expect(broadcast.listenerCount == 0)
    }
}
