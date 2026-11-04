import StorageCore
import StoreKit
import SwiftUI
import UIKit

/// Test Mode status, Photos access, the cleanup guide, debug readings, and version.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false
    @AppStorage(RecentlyDeletedGuideView.showStepsKey) private var showGuideSteps = true

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    IllustrationView(.shieldCheck, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Test Mode is on")
                            .font(.headline)
                        Text("Storage App sees only the \u{201C}\(TestMode.albumName)\u{201D} album and your free space. It changes only items in that album that you approve on a review screen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Album", value: TestMode.albumName)
                LabeledContent("Photos access", value: photoAccessText)
                if model.photoAccess == .limited {
                    Button("Change Selected Photos") {
                        Task {
                            await LimitedPhotoPicker.present()
                            await model.scanTestAlbum()
                        }
                    }
                }
                if model.photoAccess == .limited || model.photoAccess == .denied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Change Access in Settings") { openURL(url) }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text(photoFooter)
            }

            Section {
                Toggle("Step-by-Step Guide", isOn: $showGuideSteps)
            } header: {
                Text("After a Cleanup")
            } footer: {
                Text(showGuideSteps
                     ? "Walks you through emptying Recently Deleted one step at a time."
                     : "Shows a one-page summary instead. The full steps are still one tap away.")
            }

            if PaywallConfig.isEnabled {
                ProSection(showingPaywall: $showingPaywall)
            }

            #if DEBUG
            StorageHistoryDebugSection()
            Section {
                Button("Show Onboarding Again") {
                    UserDefaults.standard.set(false, forKey: OnboardingAnswers.completedKey)
                }
            } footer: {
                Text("Debug builds only. Onboarding opens over the app straight away.")
            }
            #endif

            Section("About") {
                LabeledContent("Version", value: AppInfo.versionString)
                LabeledContent("Mode", value: "Test Mode (test album only)")
                Link("Support", destination: PaywallConfig.supportURL)
                Link("Privacy Policy", destination: PaywallConfig.privacyURL)
                Link("Terms of Use", destination: PaywallConfig.termsURL)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallFlow()
        }
        .task { await model.refreshPhotoAccess() }
    }

    private var photoAccessText: String {
        switch model.photoAccess {
        case .notDetermined: "Not asked yet"
        case .granted: "Full"
        case .limited: "Selected photos"
        case .denied: "Not allowed"
        }
    }

    private var photoFooter: String {
        switch model.photoAccess {
        case .limited:
            "With selected-photos access, iOS hides albums, so the scan reads exactly the photos you picked. Pick everything in \u{201C}\(TestMode.albumName)\u{201D}."
        default:
            "With full access, the scan still reads only the \u{201C}\(TestMode.albumName)\u{201D} album. Nothing else in Photos is read."
        }
    }
}

/// Pro status, the way into the paywall, restore, and managing the
/// subscription. Only shown while the paywall is enabled.
private struct ProSection: View {
    @Environment(PurchaseStore.self) private var purchases
    @Binding var showingPaywall: Bool
    @State private var showingManage = false
    @State private var restoreMessage: String?

    var body: some View {
        Section {
            if let plan = purchases.activePlan {
                LabeledContent("Plan", value: plan.title)
                // Also shown with Lifetime, so a subscription bought earlier can still be cancelled.
                if purchases.hasActiveSubscription && !purchases.isSimulated {
                    Button("Manage Subscription") { showingManage = true }
                }
            } else {
                Button("Upgrade to Pro") { showingPaywall = true }
            }
            Button("Restore Purchases") {
                Task {
                    restoreMessage = await purchases.restore()
                        ? "Pro is active on this iPhone."
                        : "No earlier purchase was found for this Apple ID."
                }
            }
            .disabled(purchases.isPurchasing)
            #if DEBUG
            if purchases.isSimulated {
                Button("Reset Simulated Purchase", role: .destructive) { purchases.resetSimulation() }
            }
            #endif
        } header: {
            Text("Pro")
        } footer: {
            Text(footer)
        }
        .manageSubscriptionsSheet(isPresented: $showingManage)
        .alert(
            "Restore Purchases",
            isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var footer: String {
        if purchases.isSimulated {
            return "This build can't reach the App Store, so purchases are simulated. Nothing is charged; resetting also brings back the one-time lifetime offer."
        }
        if purchases.activePlan == .lifetime && purchases.hasActiveSubscription {
            return "You have Lifetime, and a subscription that still renews. Cancel it in Manage Subscription so you aren't charged again. Pro stays on either way."
        }
        return "Subscriptions renew automatically until cancelled. Cancel anytime in Manage Subscription; Pro stays on until the end of the period you paid for."
    }
}

#if DEBUG
/// The last 20 saved storage readings, newest first, for checking the meter on
/// a real phone. Debug builds only; the purgeable figure isn't shown to people.
private struct StorageHistoryDebugSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            let recent = Array(model.storageHistory.snapshots.suffix(20).reversed())
            if recent.isEmpty {
                Text("No readings yet").foregroundStyle(.secondary)
            }
            ForEach(recent, id: \.date) { snapshot in
                HStack {
                    Text(snapshot.date.formatted(date: .abbreviated, time: .standard))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(ByteFormatter.string(snapshot.availableBytes, precision: .twoDecimals)) free")
                        Text("purgeable ~\(ByteFormatter.string(snapshot.purgeableEstimateBytes, precision: .twoDecimals))")
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                .font(.caption)
            }
        } header: {
            Text("Debug: Storage Readings")
        } footer: {
            Text("\(model.storageHistory.snapshots.count) saved. A new reading is saved on each open, at most one per minute.")
        }
    }
}
#endif

enum AppInfo {
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppModel.preview())
        .environment(PurchaseStore())
}
