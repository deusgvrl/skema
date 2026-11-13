import SwiftUI

/// "Export Raw Data" on the Review page after Finish Scan (data-tool branch, not for dev).
/// Writes the scan's `log.json` and `.ply` files into a .zip, then shares it (AirDrop, Save to Files…).
struct RawExportButton: View {
    let viewModel: ScanViewModel
    @State private var file: URL?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        Group {
            if let file {
                ShareLink(item: file) {
                    Label("Export Raw Data", systemImage: "square.and.arrow.up")
                }
            } else if failed {
                Button("Retry Raw Export", systemImage: "arrow.clockwise") {
                    attempt += 1
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing raw data…")
                        .font(.footnote)
                }
            }
        }
        .task(id: attempt) {
            await prepare()
        }
    }

    private func prepare() async {
        failed = false
        do {
            file = try await viewModel.exportRawData()
        } catch {
            failed = true
        }
    }
}

extension ScanViewModel {
    /// Writes the raw-data folder (`log.json` + `.ply` files) and zips it. Returns the file to share.
    func exportRawData() async throws -> URL {
        try await RawDataExporter.export(rawLog, createdAt: .now)
    }
}
