//
//  RoomScanView.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 11/11/26.
//

import Foundation
import ARKit
import SwiftUI

struct RoomScanView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}
}
