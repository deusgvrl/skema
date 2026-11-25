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
    @ObservationIgnored private let pdfRenderer: PDFRenderer

    // Tab Navigation
    var selectedTab: Int = 0 // 0 = Diagram, 1 = References

    // Presentation Flags
    var isEditingDiagram: Bool = false
    var isEditingProjectDetails: Bool = false
    var selectedEquipment: Equipment?
    var isDeleteAlertPresented: Bool = false
    var isShowSubjectSheet: Bool = false
    var isDeleteImageAlertPresented: Bool = false

    // PDF Share State (A10-99)
    private(set) var isPreparingPDF = false
    /// Setting this shows the QuickLook preview, which has the system share button.
    var pdfURL: URL?
    var isPDFFailedAlertPresented = false

    // References Tab State
    var referenceImages: [UIImage] = []

    /// Deterministically sorted SwiftData models by creation date
    var sortedReferenceImages: [ReferenceImage] {
        setup.referenceImages.sorted(by: { $0.createdAt < $1.createdAt })
    }

    init(
        setup: Setup,
        storageController: StorageController? = nil,
        now: @escaping () -> Date = { Date() },
        pdfRenderer: PDFRenderer = PDFRenderer()
    ) {
        self.pdfRenderer = pdfRenderer
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

    /// "Aesop · November catalog" under the title (Sketch R08); empty when neither is set.
    var formattedSubtitle: String {
        [setup.client, setup.project]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The alert text: saved setups can be recovered for 30 days, drafts cannot (A10-95).
    var deleteMessage: String {
        setup.firstSavedDate == nil
            ? "This draft will be deleted. This can’t be undone."
            : "You can recover it from Recently Deleted for \(RecentlyDeleted.keepDays) days."
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

    private static let pdfFallbackName = "Untitled Setup"
    private static let pdfExtension = "pdf"

    /// The file name the share sheet shows. Slash and colon are not safe in file names, so they become "-".
    static func pdfFileName(for setupName: String) -> String {
        let cleaned = setupName
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(cleaned.isEmpty ? pdfFallbackName : cleaned).\(pdfExtension)"
    }

    /// Makes the PDF, saves it in the temporary folder and sets `pdfURL` to open the preview.
    /// `diagram` is drawn by the view, because the renderer service must not use SwiftUI.
    func shareTapped(diagram: UIImage?) {
        isPreparingPDF = true
        defer { isPreparingPDF = false }

        let data = pdfRenderer.makePDF(for: setup, diagram: diagram)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.pdfFileName(for: setup.setupName))
        do {
            guard !data.isEmpty else { throw CocoaError(.fileWriteUnknown) }
            // .atomic replaces an older file with the same name.
            try data.write(to: url, options: .atomic)
            pdfURL = url
        } catch {
            isPDFFailedAlertPresented = true
        }
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

    func setAsCoverImage(at index: Int) {
        guard sortedReferenceImages.indices.contains(index) else { return }
        let selectedRefImage = sortedReferenceImages[index]

        if let earliestDate = sortedReferenceImages.map(\.createdAt).min() {
            selectedRefImage.createdAt = earliestDate.addingTimeInterval(-1)
        }

        let currentRefs = setup.referenceImages
        setup.referenceImages = currentRefs

        storageController.save()
        loadReferenceImages()
    }
}
