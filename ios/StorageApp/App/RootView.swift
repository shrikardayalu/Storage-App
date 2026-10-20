import SwiftUI

/// Tab bar shell. The cleanup review sheet and error alerts live here so any
/// tab can open them.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
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
        .sheet(isPresented: $model.isReviewPresented) {
            CleanupReviewView()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.loadIfNeeded()
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel.preview())
        .tint(Theme.accent)
}
