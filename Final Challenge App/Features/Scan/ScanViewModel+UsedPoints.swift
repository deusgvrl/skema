import Foundation
import MeasureKit

/// The "Centres" debug view: for each tapped item and the subject, where the top centre and base centre its results
/// are measured from land.
extension ScanViewModel {
    /// The switch changed: off clears the list; on fills it at once.
    func usedPointsSwitched() {
        lastUsedRefresh = nil
        if showsUsedPoints {
            refreshUsedPoints(at: nil)
        } else {
            usedPoints = []
        }
    }

    /// Rebuilds the list from the collected points. At most twice a second (`time` is the frame's time; nil forces
    /// it), and only while the view is on, because finding the centres sorts every point.
    func refreshUsedPoints(at time: Double?) {
        guard showsUsedPoints else { return }
        if let time {
            guard lastUsedRefresh.map({ time - $0 >= 0.5 }) ?? true else { return }
            lastUsedRefresh = time
        }
        let names = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) })
        usedPoints = UsedPoints.make(centres: measurements.usedCentres(subject: subjectID), names: names,
                                     order: [subjectID] + items.map(\.id), subjectID: subjectID, floorY: floorY)
    }
}
