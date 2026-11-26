//
//  ScanViewModel+Planes.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 26/11/26.
//

/// A10-121: ARKit looks for planes only until the floor is found. After that it has less work to do.
extension ScanViewModel {
    /// How long (seconds of frame time) ARKit keeps looking for planes after it found the floor. The extra second lets
    /// the floor plane settle.
    static let planeSearchAfterFloor: Double = 1

    /// Stops ARKit's plane search once `planeSearchAfterFloor` seconds passed since the floor was found. The session
    /// does this only once. Internal so tests can call it.
    func stopPlaneSearchIfDue(at timestamp: Double) {
        guard let floorFoundAt, timestamp - floorFoundAt >= Self.planeSearchAfterFloor else { return }
        scan?.stopPlaneDetection()
    }
}
