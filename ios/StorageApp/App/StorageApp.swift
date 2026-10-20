import SwiftUI

@main
struct StorageAppEntry: App {
    // Phase 1 runs only in Demo Mode: an in-memory library with no access to Photos.
    @State private var model = AppModel.demo()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
    }
}
