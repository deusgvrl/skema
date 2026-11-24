//
//  OutlineBuffersTests.swift
//  Skema Tests
//
//  Created by Amadeus Gavriel on 24/11/26.
//

import Foundation
import Metal
import MeasureKit
import Testing
@testable import Skema_Photo

@MainActor
@Suite(
    "Outline buffers",
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "No Metal device here: the GPU buffer tests are skipped.")
)
struct OutlineBuffersTests {
    private let radius: Float = 0.005
    private let cube = WorldBox(min: .zero, max: SIMD3<Float>(repeating: 1))

    /// A device is there: the suite is skipped when it is not (see the trait above).
    private func makeBuffers() throws -> OutlineBuffers {
        let device = try #require(MTLCreateSystemDefaultDevice(), "No Metal device")
        return OutlineBuffers(device: device)
    }

    private func shifted(_ box: WorldBox, by offset: Float) -> WorldBox {
        WorldBox(min: box.min + SIMD3<Float>(repeating: offset), max: box.max + SIMD3<Float>(repeating: offset))
    }

    @Test("M14: a box gets vertex and index buffers with the OutlineMesh data")
    func boxGetsBuffersWithTheMeshData() throws {
        let buffers = try makeBuffers()
        let id = UUID()
        buffers.update([id: cube]) { _ in radius }

        let geometry = OutlineMesh.geometry(of: cube, radius: radius)
        let entry = try #require(buffers.entries[id])
        #expect(entry.box == cube)
        #expect(entry.vertexCount == geometry.positions.count)
        #expect(entry.indexCount == geometry.indices.count)
        #expect(entry.vertexBuffer.length == geometry.positions.count * 3 * MemoryLayout<Float>.stride)
        #expect(entry.indexBuffer.length == geometry.indices.count * MemoryLayout<UInt32>.stride)

        let floats = entry.vertexBuffer.contents().bindMemory(to: Float.self, capacity: entry.vertexCount * 3)
        let expectedFloats = geometry.positions.flatMap { [$0.x, $0.y, $0.z] }
        #expect(Array(UnsafeBufferPointer(start: floats, count: entry.vertexCount * 3)) == expectedFloats)

        let indices = entry.indexBuffer.contents().bindMemory(to: UInt32.self, capacity: entry.indexCount)
        #expect(Array(UnsafeBufferPointer(start: indices, count: entry.indexCount)) == geometry.indices)
    }

    @Test("M15: a box that moved 0.5 cm keeps its buffers")
    func smallMoveKeepsTheBuffers() throws {
        let buffers = try makeBuffers()
        let id = UUID()
        buffers.update([id: cube]) { _ in radius }
        let before = try #require(buffers.entries[id])

        buffers.update([id: shifted(cube, by: 0.005)]) { _ in radius }

        let after = try #require(buffers.entries[id])
        #expect(after.vertexBuffer === before.vertexBuffer)
        #expect(after.indexBuffer === before.indexBuffer)
    }

    @Test("M15: a box that moved 1 cm gets new buffers")
    func bigMoveBuildsNewBuffers() throws {
        let buffers = try makeBuffers()
        let id = UUID()
        buffers.update([id: cube]) { _ in radius }
        let before = try #require(buffers.entries[id])
        let moved = shifted(cube, by: 0.011)

        buffers.update([id: moved]) { _ in radius }

        let after = try #require(buffers.entries[id])
        #expect(after.vertexBuffer !== before.vertexBuffer)
        #expect(after.indexBuffer !== before.indexBuffer)
        #expect(after.box == moved)
    }

    @Test("M17: a box with a radius that is not finite or not above 0 gets no entry, and builds later with a good one")
    func badRadiusGivesNoEntry() throws {
        let buffers = try makeBuffers()
        let infinite = UUID()
        let zero = UUID()
        let other = WorldBox(min: SIMD3<Float>(2, 0, 0), max: SIMD3<Float>(3, 1, 1))
        buffers.update([infinite: cube, zero: other]) { $0 == cube ? .infinity : 0 }

        #expect(buffers.entries[infinite] == nil)
        #expect(buffers.entries[zero] == nil)

        buffers.update([infinite: cube, zero: other]) { _ in radius }

        #expect(buffers.entries[infinite] != nil)
        #expect(buffers.entries[zero] != nil)
    }

    @Test("M17: a box that gets a bad radius loses its old entry, so it rebuilds later")
    func badRadiusRemovesTheOldEntry() throws {
        let buffers = try makeBuffers()
        let id = UUID()
        buffers.update([id: cube]) { _ in radius }
        #expect(buffers.entries[id] != nil)

        buffers.update([id: shifted(cube, by: 0.05)]) { _ in .nan }
        #expect(buffers.entries[id] == nil)

        buffers.update([id: shifted(cube, by: 0.05)]) { _ in radius }
        #expect(buffers.entries[id] != nil)
    }

    @Test("M16: a box that is not in the update is removed")
    func missingBoxIsRemoved() throws {
        let buffers = try makeBuffers()
        let kept = UUID()
        let gone = UUID()
        let other = WorldBox(min: SIMD3<Float>(2, 0, 0), max: SIMD3<Float>(3, 1, 1))
        buffers.update([kept: cube, gone: other]) { _ in radius }
        #expect(buffers.entries.count == 2)

        buffers.update([kept: cube]) { _ in radius }

        #expect(buffers.entries[gone] == nil)
        #expect(buffers.entries[kept] != nil)
        #expect(buffers.entries.count == 1)
    }
}
