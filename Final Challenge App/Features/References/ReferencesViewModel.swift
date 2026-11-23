//
//  ReferencesViewModel.swift
//  Final Challenge App
//
//  Created by Satriya Handha Wibowo on 23/11/26.
//

import SwiftUI
import PhotosUI

@Observable
final class ReferencesViewModel {
    var showCamera = false
    var showPhotoPicker = false
    var photoPickerSelection: [PhotosPickerItem] = []

    var showCameraDenied = false
    var openLibraryAfterDenied = false
    let cameraPermission: CameraPermission

    var selectedPreviewIndex: Int = 0
    var showReferenceDetail: Bool = false
    var imageIndexToDelete: Int?
    var isDeleteImageAlertPresented: Bool = false

    init(cameraPermission: CameraPermission = SystemCameraPermission()) {
        self.cameraPermission = cameraPermission
    }

    func takePhotoTapped() {
        guard CameraService.shared.isCameraAvailable else {
            showCamera = true
            return
        }

        switch cameraPermission.status {
        case .authorized:
            showCamera = true
        case .denied:
            showCameraDenied = true
        case .notDetermined:
            Task { @MainActor in
                if await cameraPermission.request() {
                    showCamera = true
                } else {
                    showCameraDenied = true
                }
            }
        }
    }
}
