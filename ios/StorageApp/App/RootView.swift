import StoreKit
import SwiftUI

/// Tab bar shell, with onboarding over it on first run. Error alerts live
/// here so any tab can raise them.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @AppStorage(OnboardingAnswers.completedKey) private var onboardingDone = false
    @AppStorage(OnboardingAnswers.winPaywallShownKey) private var winPaywallShown = false
    /// The app version the rating prompt was last asked for, so it's asked once per version.
    @AppStorage("reviewAskedVersion") private var reviewAskedVersion = ""
    @Environment(\.requestReview) private var requestReview
    /// The paywall that follows a first free cleanup, once ever.
    @State private var winPaywall: PaywallContext?
    /// What the open other-app guide has measured so far; the model clears it on close.
    @State private var otherAppFreed: Int64 = 0
    /// Home drawing itself in after onboarding; 1 when there's nothing to draw.
    @State private var drawIn: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            tabs
            if showsOnboarding {
                OnboardingFlow(startAt: ScreenshotRoute.current?.onboardingStart ?? .hook,
                               sampleSuggestions: ScreenshotRoute.current?.onboardingStart == nil ? nil : Suggestion.sample) {
                    // Onboarding can be reopened from Settings; always land on Home after it.
                    model.selectedTab = .home
                    withAnimation(.easeInOut(duration: 0.45)) { onboardingDone = true }
                    drawHome()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
        .onAppear { if showsOnboarding { drawIn = 0 } }
        // "Show Onboarding Again" in Settings: blank Home again under it.
        .onChange(of: onboardingDone) { _, done in
            if !done, showsOnboarding { drawIn = 0 }
        }
    }

    /// Draws Home onto the page as onboarding fades off it.
    private func drawHome() {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) { drawIn = 1 }
            return
        }
        Task {
            // Let onboarding start fading so the first strokes are seen.
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.linear(duration: DrawIn.duration)) { drawIn = 1 }
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
                .environment(\.drawInProgress, drawIn)
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
        // Step 9: how to restart, with the baseline taken for the next open.
        .fullScreenCover(isPresented: $model.isShowingRestartGuide) {
            RestartGuideView()
                .environment(model)
                .tint(Theme.accent)
        }
        // WhatsApp, Messages, Settings: steps only the person can do, then a free-space check.
        .fullScreenCover(item: $model.otherAppGuide) { guide in
            OtherAppGuideView(guide: guide)
                .environment(model)
                .tint(Theme.accent)
        }
        // After the first free cleanup, once: "You freed X. Pro gets the other Y."
        // Shown when they've just seen the app work, without blocking anything.
        .fullScreenCover(isPresented: Binding(get: { winPaywall != nil }, set: { if !$0 { winPaywall = nil } })) {
            PaywallFlow(context: winPaywall ?? .generic)
                .environment(purchases)
                .tint(Theme.accent)
        }
        .onChange(of: model.guide?.id) { old, new in
            if old != nil, new == nil { offerAfterWin(freed: model.lastGuide?.expectedBytes ?? 0) }
        }
        .onChange(of: model.guideFreedBytes) { _, bytes in
            if bytes > 0 { otherAppFreed = bytes }
        }
        .onChange(of: model.otherAppGuide) { old, new in
            guard old != nil, new == nil else { return }
            offerAfterWin(freed: otherAppFreed)
            otherAppFreed = 0
        }
        .task {
            ScreenshotRoute.current?.apply(to: model)
            await model.scanIfAllowed()
        }
    }

    /// Opens the paywall once ever, right after a free cleanup gave space back,
    /// if Pro still has something sizeable to offer.
    private func offerAfterWin(freed: Int64) {
        let pro = model.proSaving
        guard purchases.requiresPro, !winPaywallShown, ScreenshotRoute.current == nil, freed > 0, pro > 0 else {
            // No paywall this time, so it's a good moment to ask for a rating.
            askForReview(freed: freed)
            return
        }
        winPaywallShown = true
        Task {
            // Let the guide finish closing first.
            try? await Task.sleep(for: .milliseconds(650))
            winPaywall = PaywallContext(proBytes: pro, freedBytes: freed)
        }
    }

    /// Asks for an App Store rating right after a cleanup gave space back, at
    /// most once per app version. iOS decides whether the prompt appears, and
    /// shows it at most three times a year.
    private func askForReview(freed: Int64) {
        guard freed > 0, ScreenshotRoute.current == nil, reviewAskedVersion != AppInfo.versionString else { return }
        reviewAskedVersion = AppInfo.versionString
        Task {
            // Let the guide finish closing first.
            try? await Task.sleep(for: .milliseconds(900))
            requestReview()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview())
        .environment(PurchaseStore())
        .tint(Theme.accent)
}
