import SwiftUI
import Playgrounds

struct ContentView: View {
    #if DEBUG
    @State private var showsDetectorTest = false
    #endif

    var body: some View {
        SetupsView()
        #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                Button("Detector test") { showsDetectorTest = true }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
            .fullScreenCover(isPresented: $showsDetectorTest) { DetectorDebugView() }
        #endif
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
