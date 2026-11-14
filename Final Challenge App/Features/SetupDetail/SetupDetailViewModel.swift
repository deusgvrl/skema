import Observation
import SwiftUI
import PhotosUI

/// State and actions for SetupDetailView.
/// Reads and writes data only through StorageController, and reloads on appear and after every change.

@MainActor
@Observable
final class SetupDetailViewModel {
    let setup: Setup
    let reviewViewModel: ReviewViewModel
    @ObservationIgnored private let storageController: StorageController
    
    // Tab Navigation
    var selectedTab: Int = 0 // 0 = Diagram, 1 = References
    
    // Presentation Flags
    var isEditingDiagram: Bool = false
    var isEditingProjectDetails: Bool = false
    var selectedEquipment: Equipment? = nil
    var isDeleteAlertPresented: Bool = false
    var isShowSubjectSheet: Bool = false
    
    // References Tab State
    var isSelectionMode: Bool = false
    var referenceImages: [UIImage] = []
    
    init(setup: Setup, storageController: StorageController? = nil) {
        let storage = storageController ?? StorageController.shared
        self.setup = setup
        self.storageController = storage
        self.reviewViewModel = ReviewViewModel(setup: setup, storageController: storage)
        self.loadReferenceImages()
    }
    
    
    var setupName: String {
        setup.setupName.isEmpty ? "Untitled Setup" : setup.setupName
    }
    
    var formattedSubtitle: String {
        let components = [setup.client, setup.project].filter { !$0.isEmpty }
        return components.isEmpty ? "No Details" : components.joined(separator: " › ")
    }
    
    
    func deleteSetup(completion: () -> Void) {
        storageController.deleteSetup(setup)
        completion()
    }
    
    /// Loads existing ReferenceImage data into UIImages
    func loadReferenceImages() {
        self.referenceImages = setup.referenceImages.compactMap { ref in
            UIImage(data: ref.imageData)
        }
    }
    
    /// Saves a single UIImage to SwiftData using StorageController
    func addReferenceImage(_ image: UIImage) {
        // Update in-memory array for instant UI update
        referenceImages.append(image)
        
        // Convert to Data and persist via StorageController
        if let data = image.jpegData(compressionQuality: 0.8) {
            let newRefImage = ReferenceImage(imageData: data)
            storageController.addReferenceImage(newRefImage, to: setup)
        }
    }
    
    /// Loads PhotosPickerItem data asynchronously and saves each image to SwiftData
    func addReferenceImages(from items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            
            // Update in-memory array for instant UI update
            referenceImages.append(image)
            
            // Save original Data directly — no re-encoding needed
            let newRefImage = ReferenceImage(imageData: data)
            storageController.addReferenceImage(newRefImage, to: setup)
        }
    }
    
    /// Deletes a single reference image by its array index
    func deleteReferenceImage(at index: Int) {
        guard setup.referenceImages.indices.contains(index) else { return }
        
        let refImageToDelete = setup.referenceImages[index]
        
        if referenceImages.indices.contains(index) {
            referenceImages.remove(at: index)
        }
        
        storageController.deleteReferenceImage(refImageToDelete)
    }
    
    /// Batch deletes reference images by a set of indices (used in multiselect deletion)
    func deleteReferenceImages(at indices: Set<Int>) {
        let sortedIndices = indices.sorted(by: >)
        
        for index in sortedIndices {
            guard setup.referenceImages.indices.contains(index) else { continue }
            
            let refImageToDelete = setup.referenceImages[index]
            
            if referenceImages.indices.contains(index) {
                referenceImages.remove(at: index)
            }
            
            storageController.deleteReferenceImage(refImageToDelete)
        }
    }
}
