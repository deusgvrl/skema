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
    @ObservationIgnored private let now: () -> Date
    
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
    
    /// Deterministically sorted SwiftData models by creation date
    var sortedReferenceImages: [ReferenceImage] {
        setup.referenceImages.sorted(by: { $0.createdAt < $1.createdAt })
    }
    
    init(setup: Setup, storageController: StorageController? = nil, now: @escaping () -> Date = { Date() }) {
        let storage = storageController ?? StorageController.shared
        self.now = now
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
    
    /// The alert text: saved setups can be recovered for 30 days, drafts cannot (A10-95).
    var deleteMessage: String {
        setup.firstSavedDate == nil
            ? "This draft will be deleted. This can't be undone."
            : "This setup will move to Recently Deleted for \(RecentlyDeleted.keepDays) days."
    }

    func deleteSetup(completion: () -> Void) {
        if setup.firstSavedDate == nil {
            // A draft was never saved by the user, so it skips Recently Deleted.
            storageController.deleteSetup(setup)
        } else {
            storageController.moveToRecentlyDeleted(setup, at: now())
        }
        completion()
    }
    
    /// Loads existing ReferenceImage data into UIImages sorted by createdAt
    func loadReferenceImages() {
        self.referenceImages = sortedReferenceImages.compactMap { ref in
            UIImage(data: ref.imageData)
        }
    }
    
    /// Saves a single UIImage to SwiftData using StorageController
    func addReferenceImage(_ image: UIImage) {
        referenceImages.append(image)
        
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
            
            referenceImages.append(image)
            
            let newRefImage = ReferenceImage(imageData: data)
            storageController.addReferenceImage(newRefImage, to: setup)
        }
    }
    
    // MARK: - Delete Reference Image Operations
    
    /// Deletes a specific ReferenceImage model from SwiftData and local array
    func deleteReferenceImage(_ image: ReferenceImage) {
        let sorted = sortedReferenceImages
        if let index = sorted.firstIndex(where: { $0.id == image.id }) {
            if referenceImages.indices.contains(index) {
                referenceImages.remove(at: index)
            }
        }
        storageController.deleteReferenceImage(image)
    }
    
    /// Deletes a single reference image by matching index in sortedReferenceImages
    func deleteReferenceImage(at index: Int) {
        let sorted = sortedReferenceImages
        guard sorted.indices.contains(index) else { return }
        
        let refImageToDelete = sorted[index]
        
        if referenceImages.indices.contains(index) {
            referenceImages.remove(at: index)
        }
        
        storageController.deleteReferenceImage(refImageToDelete)
    }
    
    /// Batch deletes reference images by a set of indices
    func deleteReferenceImages(at indices: Set<Int>) {
        let sorted = sortedReferenceImages
        let sortedIndices = indices.sorted(by: >)
        
        for index in sortedIndices {
            guard sorted.indices.contains(index) else { continue }
            let refImageToDelete = sorted[index]
            
            if referenceImages.indices.contains(index) {
                referenceImages.remove(at: index)
            }
            
            storageController.deleteReferenceImage(refImageToDelete)
        }
    }
}
