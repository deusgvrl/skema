//
//  ScanViewModel+Progress.swift
//  Final Challenge App
//
//  Scan screen phase 3 (decided 24 Nov 2026): one item at a time. An item is done once it is saved (enough points,
//  measured against the subject) and the phone has seen it from two spots at least 45° apart (`ViewSpread`). Until
//  then it is "being scanned": the instruction asks to walk around it, its tag shows a ring, and the next tap waits.
//

import Foundation
import MeasureKit

extension ScanViewModel {
    /// Saved and seen from far enough around.
    func isDone(_ item: ScanItem) -> Bool {
        isSaved(item) && viewSpreads[item.id]?.isEnough == true
    }

    var subjectIsDone: Bool {
        subjectIsSaved && viewSpreads[subjectID]?.isEnough == true
    }

    /// The subject's and the items' ids that are done: their tags show a tick and their outlines turn green.
    var doneItemIDs: Set<UUID> {
        var done = Set(items.filter(isDone).map(\.id))
        if subjectIsDone { done.insert(subjectID) }
        return done
    }

    /// How many items of `kind` are done.
    func doneCount(of kind: ScanTapKind) -> Int {
        items.count { $0.kind == kind && isDone($0) }
    }

    /// The subject or the item tapped but not done yet (at most one, because of the gate), for the instruction and
    /// the gate. Nil when nothing is being scanned.
    var scanning: ScanScanning? {
        if subject != nil, !subjectIsDone {
            return ScanScanning(name: "the subject", isTooFar: subjectResult?.status == .outOfRange)
        }
        guard let item = items.first(where: { !isDone($0) }) else { return nil }
        return ScanScanning(name: item.kind == .camera ? "the camera" : item.name,
                            isTooFar: item.result?.status == .outOfRange)
    }

    /// The tag's ring: half for enough points, half for the walk around it; full only once done.
    func progress(of item: ScanItem) -> Double {
        Self.progress(points: item.result?.pointCount ?? 0, spread: viewSpreads[item.id], isDone: isDone(item))
    }

    var subjectProgress: Double {
        Self.progress(points: subjectResult?.pointCount ?? 0, spread: viewSpreads[subjectID], isDone: subjectIsDone)
    }

    private static func progress(points: Int, spread: ViewSpread?, isDone: Bool) -> Double {
        if isDone { return 1 }
        let pointsPart = min(Double(points) / Double(Geometry.minPointCount), 1)
        let walkPart = min(Double(spread?.degrees ?? 0) / Double(ViewSpread.doneDegrees), 1)
        // Never full before it is done (for example walked around but not measured against the subject yet).
        return min(0.5 * pointsPart + 0.5 * walkPart, 0.95)
    }
}
