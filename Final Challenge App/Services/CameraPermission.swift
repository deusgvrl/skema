//
//  CameraPermission.swift
//  Final Challenge App
//
//  Created by Muhammad Dzakki Abdullah on 10/11/26.
//

import AVFoundation

enum CameraPermissionStatus: Equatable {

    case notDetermined
    case authorized
    case denied
}

protocol CameraPermission {
    var status: CameraPermissionStatus { get }
    func request() async -> Bool
}

struct SystemCameraPermission: CameraPermission {
    var status: CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

struct FixedCameraPermission: CameraPermission {
    let status: CameraPermissionStatus

    func request() async -> Bool {
        status == .authorized
    }
}
