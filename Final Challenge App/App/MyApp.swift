import SwiftUI
import TipKit

@main struct MyApp: App {
    
    init() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
