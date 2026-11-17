import Observation
import SwiftUI

/// ••• → Share: builds the setup's A4 PDF and hands it to the share sheet (Sketch R14 → R15),
/// or shows "Couldn't Create PDF" (R15f).
@MainActor
@Observable
final class ExportViewModel {
    /// A built PDF waiting in the share sheet.
    struct SharedPDF: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var sharedPDF: SharedPDF?
    var showsFailure = false

    @ObservationIgnored private let setup: Setup
    @ObservationIgnored private let makeFile: (Setup) throws -> URL

    init(setup: Setup, makeFile: ((Setup) throws -> URL)? = nil) {
        self.setup = setup
        self.makeFile = makeFile ?? { try ExportViewModel.makePDFFile(for: $0) }
    }

    /// Share / Try Again.
    func share() {
        do {
            sharedPDF = SharedPDF(url: try makeFile(setup))
            showsFailure = false
        } catch {
            sharedPDF = nil
            showsFailure = true
        }
    }

    // MARK: - Building the file

    struct EmptyPDFError: Error {}

    /// The diagram box on page 1, in points.
    static let diagramBox = CGSize(width: 515, height: 380)

    static func makePDFFile(for setup: Setup) throws -> URL {
        let content = SetupPDFContent(setup: setup)
        let renderer = PDFRenderer()
        let data = renderer.render(content, diagram: diagramImage(for: setup))
        guard !data.isEmpty else { throw EmptyPDFError() }
        return try renderer.writeFile(data, named: content.fileName)
    }

    /// The lighting diagram as it looks in the app in light mode, zoomed to fit the PDF box.
    static func diagramImage(for setup: Setup) -> UIImage? {
        let zoom = SetupPDFContent.diagramZoom(for: setup.nodes.map(\.position), in: diagramBox)
        let diagram = LightingDiagramView(
            viewModel: ReviewViewModel(setup: setup),
            isReadOnly: true,
            initialZoomScale: zoom
        )
        .frame(width: diagramBox.width, height: diagramBox.height)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: diagram)
        renderer.scale = 2
        return renderer.uiImage
    }
}
