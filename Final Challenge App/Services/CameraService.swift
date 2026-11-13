//
//  CameraService.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 14/11/26.
//

import UIKit
import AVFoundation

final class CameraService {
    static let shared = CameraService()
    
    // Integrates with your existing CameraPermission in Services
    private let permission: CameraPermission
    
    init(permission: CameraPermission = SystemCameraPermission()) {
        self.permission = permission
    }
    
    /// Whether the device has a physical camera available (false on Simulator)
    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    
    /// Current permission status from existing CameraPermission service
    var permissionStatus: CameraPermissionStatus {
        permission.status
    }
    
    /// Request camera access asynchronously
    func requestPermission() async -> Bool {
        await permission.request()
    }
    
    /// Converts a picked UIImage to optimized JPEG Data for SwiftData's ReferenceImage
    func prepareImageData(from image: UIImage, quality: CGFloat = 0.8) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
