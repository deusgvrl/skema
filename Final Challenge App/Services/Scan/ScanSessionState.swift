//
//  ScanSessionState.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import Foundation
import ARKit

nonisolated enum ScanSessionState: Equatable, Sendable {
    case idle
    case running
    case interrupted
    case stopped
    case discarded
    case failed(ScanSessionError)

    var isFinished: Bool {
        switch self {
        case .stopped, .discarded, .failed: true
        case .idle, .running, .interrupted: false
        }
    }
}

nonisolated enum ScanSessionError: Error, Equatable, Sendable {

    case lidarUnsupported
    case alreadyStarted
    case cameraDenied
    case sessionFailed(String)

    init(_ error: any Error) {
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            self = .cameraDenied
        } else {
            self = .sessionFailed(error.localizedDescription)
        }
    }
}
