import SwiftUI

@main
struct StorageAppEntry: App {
    // Phase 1 runs only in Demo Mode: an in-memory library with no access to Photos.
    @State private var model = AppModel.demo()
    @State private var purchases = PurchaseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(purchases)
                .tint(Theme.accent)
        }
    }
}
