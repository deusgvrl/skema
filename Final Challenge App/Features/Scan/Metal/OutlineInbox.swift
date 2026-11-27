//
//  OutlineInbox.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 26/11/26.
//
//  The hand-over from the main thread to the render thread (A10-121, step 4). SwiftUI puts the newest outlines and
//  the view size in; the renderer reads them at the start of each frame. A `Mutex` guards the data, so neither side
//  waits for long.
//

import CoreGraphics
import Foundation
import MeasureKit
import Synchronization

nonisolated final class OutlineInbox: Sendable {
    /// What the renderer needs for one frame.
    struct Snapshot: Sendable {
        /// The world box of each item to outline, by item id.
        var outlines: [UUID: WorldBox] = [:]
        /// The ids in `outlines` whose item is done (drawn green; the others white).
        var done: Set<UUID> = []
        /// The view size in points (the line thickness is in points).
        var viewSize: CGSize = .zero
    }

    private let data = Mutex(Snapshot())

    /// Replaces the outlines and which of them are done, together, so a frame never mixes new boxes with old
    /// colours. Called on the main thread.
    func setOutlines(_ outlines: [UUID: WorldBox], done: Set<UUID>) {
        data.withLock {
            $0.outlines = outlines
            $0.done = done
        }
    }

    /// Replaces the view size in points. Called on the main thread.
    func setViewSize(_ size: CGSize) {
        data.withLock { $0.viewSize = size }
    }

    /// The newest outlines and view size. Called on the render thread.
    func snapshot() -> Snapshot {
        data.withLock { $0 }
    }
}
