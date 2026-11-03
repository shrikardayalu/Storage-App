import SwiftUI

/// Tab bar shell, with onboarding over it on first run. Error alerts live
/// here so any tab can raise them.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @AppStorage(OnboardingAnswers.completedKey) private var onboardingDone = false

    var body: some View {
        ZStack {
            tabs
            if showsOnboarding {
                OnboardingFlow(startAt: ScreenshotRoute.current?.onboardingStart ?? .hook,
                               sampleReveal: ScreenshotRoute.current?.onboardingStart == nil ? nil : .sample) {
                    withAnimation(.easeInOut(duration: 0.45)) { onboardingDone = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
    }

    /// Screenshot runs show onboarding only when asked for it.
    private var showsOnboarding: Bool {
        if let route = ScreenshotRoute.current { return route.onboardingStart != nil && !onboardingDone }
        return !onboardingDone
    }

    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            NavigationStack { LibraryView() }
                .tabItem { Label("Library", systemImage: "photo.on.rectangle.angled") }
                .tag(AppTab.library)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        // After a delete or Live Photo conversion: help empty Recently Deleted.
        .fullScreenCover(item: $model.guide) { guide in
            RecentlyDeletedGuideView(guide: guide)
                .environment(model)
                .tint(Theme.accent)
        }
        // WhatsApp, Messages, Settings: steps only the person can do, then a free-space check.
        .fullScreenCover(item: $model.otherAppGuide) { guide in
            OtherAppGuideView(guide: guide)
                .environment(model)
                .tint(Theme.accent)
        }
        .task {
            ScreenshotRoute.current?.apply(to: model)
            await model.scanIfAllowed()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview())
        .environment(PurchaseStore())
        .tint(Theme.accent)
}
