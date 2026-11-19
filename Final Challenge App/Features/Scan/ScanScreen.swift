//
//  ScanScreen.swift
//  Final Challenge App
//
//  What the scan screen shows: the camera (starting, scanning) or a message instead of it.
//

/// What the scan screen shows.
enum ScanScreen: Equatable {
    case starting
    case scanning
    case cameraDenied
    case lidarUnsupported
    case failed(String)
}

extension ScanScreen {
    /// The camera screens are dark-only (Sketch R03); the message screens follow the
    /// system appearance (Sketch R02c and its Light pair).
    var usesCameraAppearance: Bool {
        switch self {
        case .starting, .scanning: true
        case .cameraDenied, .lidarUnsupported, .failed: false
        }
    }
}
