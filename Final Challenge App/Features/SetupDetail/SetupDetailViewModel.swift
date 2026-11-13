import Observation
import SwiftUI

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
}
