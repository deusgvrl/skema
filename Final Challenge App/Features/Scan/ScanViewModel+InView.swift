//
//  ScanViewModel+InView.swift
//  Final Challenge App
//
//  Created by Amadeus Gavriel on 26/11/26.
//

import MeasureKit

/// A10-121: the scan samples LiDAR only for the items the camera can see.
extension ScanViewModel {
    /// The painted column of an item as a world box: 10 cm around the tapped axis, from 3 cm above the floor up to
    /// 3 m above it. The whole tube counts, not only the tapped point.
    static func columnBox(around anchor: SIMD3<Float>, floorY: Float) -> WorldBox {
        let radius = DepthGrouping.columnRadius
        return WorldBox(min: SIMD3(anchor.x - radius, floorY + DepthGrouping.columnFloorGap, anchor.z - radius),
                        max: SIMD3(anchor.x + radius, floorY + DepthGrouping.columnHeight, anchor.z + radius))
    }

    /// True when the column around `anchor` can be in `camera`'s picture (`FieldOfView.contains`).
    static func isInView(_ anchor: SIMD3<Float>, floorY: Float, camera: CameraModel) -> Bool {
        FieldOfView.contains(Self.columnBox(around: anchor, floorY: floorY), camera: camera)
    }
}
