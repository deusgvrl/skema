//
//  OutlineBuffers.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 24/11/26.
//
//  The GPU buffers for the outline boxes (Metal renderer, part 1). Each box has one vertex buffer and one index
//  buffer, built from `OutlineMesh`. A box that did not really move keeps its buffers, so the GPU data is not
//  rebuilt every frame.
//

import Foundation
import MeasureKit
import Metal
import simd

/// Used on the render thread only, so it is not on the main actor.
nonisolated final class OutlineBuffers {
    /// The GPU data of one box. `box` is the box these buffers were built from.
    struct Entry {
        let box: WorldBox
        let vertexBuffer: any MTLBuffer
        let indexBuffer: any MTLBuffer
        let vertexCount: Int
        let indexCount: Int
    }

    private(set) var entries: [UUID: Entry] = [:]
    private let device: any MTLDevice

    init(device: any MTLDevice) {
        self.device = device
    }

    /// Keeps exactly the given boxes: new ones get buffers, ones that moved 1 cm or more get new buffers, ones that
    /// are missing are removed. `radius` gives the line thickness for a box, and is asked only when buffers are built.
    func update(_ boxes: [UUID: WorldBox], radius: (WorldBox) -> Float) {
        for id in entries.keys where boxes[id] == nil {
            entries[id] = nil
        }
        for (id, box) in boxes {
            if let old = entries[id], !Self.hasMoved(from: old.box, to: box) { continue }
            let lineRadius = radius(box)
            // A radius that is not finite or not above 0 (for example, a focal length of 0 before the first
            // frame) would give NaN positions. Keep no entry, so the box builds later with a good radius.
            guard lineRadius.isFinite, lineRadius > 0 else {
                entries[id] = nil
                continue
            }
            // A box with no triangles, or a failed buffer, keeps its old entry (if it has one).
            guard let entry = makeEntry(for: box, radius: lineRadius) else { continue }
            entries[id] = entry
        }
    }

    /// The same rule as `ScanOutlines`: moved by `rebuildStep` or more on any side.
    private static func hasMoved(from old: WorldBox, to new: WorldBox) -> Bool {
        simd_reduce_max(simd_abs(old.min - new.min)) >= ScanOutlines.rebuildStep
            || simd_reduce_max(simd_abs(old.max - new.max)) >= ScanOutlines.rebuildStep
    }

    private func makeEntry(for box: WorldBox, radius: Float) -> Entry? {
        let geometry = OutlineMesh.geometry(of: box, radius: radius)
        guard !geometry.indices.isEmpty else { return nil }
        // Packed: 3 floats (12 bytes) per vertex. A SIMD3<Float> would take 16 bytes.
        let floats = geometry.positions.flatMap { [$0.x, $0.y, $0.z] }
        guard let vertexBuffer = device.makeBuffer(
            bytes: floats, length: floats.count * MemoryLayout<Float>.stride, options: .storageModeShared
        ), let indexBuffer = device.makeBuffer(
            bytes: geometry.indices, length: geometry.indices.count * MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else { return nil }
        return Entry(
            box: box, vertexBuffer: vertexBuffer, indexBuffer: indexBuffer,
            vertexCount: geometry.positions.count, indexCount: geometry.indices.count
        )
    }
}
