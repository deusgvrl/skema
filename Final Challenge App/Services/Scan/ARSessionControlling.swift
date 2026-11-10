//
//  ARSessionControlling.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import ARKit

nonisolated protocol ARSessionControlling: AnyObject {
    var delegate: (any ARSessionDelegate)? { get set }
    var delegateQueue: DispatchQueue? { get set }
    func run(_ configuration: ARConfiguration, options: ARSession.RunOptions)
    func pause()
}

nonisolated extension ARSession: ARSessionControlling {}
