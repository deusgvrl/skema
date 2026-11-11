import SwiftUI
import Playgrounds

struct ContentView: View {
    #if DEBUG
    @State private var isShowingMeasureDebug = false
    #endif

    var body: some View {
        SetupsView()
        #if DEBUG
            // Temporary (A10-41): opens the measure debug screen on a LiDAR iPhone. Not in release builds.
            .overlay(alignment: .bottomLeading) {
                Button("Measure debug") { isShowingMeasureDebug = true }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
            .fullScreenCover(isPresented: $isShowingMeasureDebug) {
                MeasureDebugView()
            }
        #endif
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}
