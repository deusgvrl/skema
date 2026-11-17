import LinkPresentation
import SwiftUI
import UIKit

/// The system share sheet for a setup's PDF (Sketch R15): header "<name>.pdf" with
/// "PDF · Diagram, equipment & references" underneath; tapping it opens Quick Look (R15p).
struct ExportView: UIViewControllerRepresentable {
    let fileURL: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [PDFShareItem(fileURL: fileURL)],
                                                  applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Gives the share sheet the file plus a title and subtitle for its header.
private final class PDFShareItem: NSObject, UIActivityItemSource {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = fileURL.lastPathComponent
        // The share sheet shows a file URL's path as the subtitle line.
        metadata.originalURL = URL(fileURLWithPath: "PDF · Diagram, equipment & references")
        metadata.iconProvider = NSItemProvider(contentsOf: fileURL)
        return metadata
    }
}
