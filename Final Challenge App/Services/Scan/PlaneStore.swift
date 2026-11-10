//
//  PlaneStore.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation

nonisolated struct PlaneStore {
    private var planesByID: [UUID: ScanPlane] = [:]

    var planes: [ScanPlane] {
        planesByID.values.sorted { $0.worldY < $1.worldY }
    }

    mutating func upsert(_ planes: [ScanPlane]) {
        for plane in planes {
            planesByID[plane.id] = plane
        }
    }

    mutating func remove(_ ids: [UUID]) {
        for id in ids {
            planesByID[id] = nil
        }
    }

    mutating func removeAll() {
        planesByID.removeAll()
    }
}
