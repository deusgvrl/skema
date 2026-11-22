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
                .task {
                    // Setups past their 30 days are removed on the first launch after their last day.
                    StorageController.shared.purgeExpiredSetups(now: Date())
                }
        }
    }
}
