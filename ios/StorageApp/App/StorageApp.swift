import SwiftUI

@main
struct StorageAppEntry: App {
    // Reads real device storage and, in Test Mode, only the "Storage App Test" album.
    @State private var model = AppModel.live()
    @State private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(purchases)
                .tint(Theme.accent)
        }
        // Reads device storage on launch and each time the app returns to the foreground.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await model.refreshDeviceStorage() }
            }
        }
    }
}
