//
//  PlaneStoreTests.swift
//  Skema Tests
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import MeasureKit
import Testing
@testable import Final_Challenge_App

@Suite("Plane store")
struct PlaneStoreTests {
    @Test("Planes come back lowest first")
    func sortedLowestFirst() {
        var store = PlaneStore()

        store.upsert([makePlane(worldY: 0.7), makePlane(worldY: -0.1), makePlane(worldY: 0.4)])

        #expect(store.planes.map(\.worldY) == [-0.1, 0.4, 0.7])
    }

    @Test("A plane ARKit grew replaces the old one")
    func upsertReplaces() {
        let id = UUID()
        var store = PlaneStore()
        store.upsert([makePlane(worldY: 0, area: 1, id: id)])

        store.upsert([makePlane(worldY: 0, area: 4, id: id)])

        #expect(store.planes.count == 1)
        #expect(store.planes.first?.area == 4)
    }

    @Test("Removed planes are gone")
    func removeDeletes() {
        let kept = makePlane(worldY: 0)
        let removed = makePlane(worldY: 1)
        var store = PlaneStore()
        store.upsert([kept, removed])

        store.remove([removed.id])

        #expect(store.planes == [kept])
    }

    @Test("A table never stands in for the floor")
    func floorPickerIgnoresTable() {
        var store = PlaneStore()
        store.upsert([makePlane(worldY: 0.7, isFloor: false), makePlane(worldY: -1.2, isFloor: true)])

        let floorY = FloorPicker.floorY(store.planes.map(\.horizontalPlane))

        #expect(floorY == -1.2)
    }
}
