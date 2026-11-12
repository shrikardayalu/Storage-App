import SwiftUI

@main
struct StorageAppEntry: App {
    // Reads real device storage and the photo library. Changes only what the person approves.
    @State private var model = AppModel.live()
    @State private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(purchases)
                .tint(Theme.accent)
                .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .system).colorScheme)
                .task { await purchases.start() }
        }
        // Reads device storage on launch and each time the app returns to the foreground.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await model.refreshDeviceStorage() }
                // Picks up a subscription cancelled, renewed or refunded while away.
                Task { await purchases.refreshEntitlements() }
            }
        }
    }
}
