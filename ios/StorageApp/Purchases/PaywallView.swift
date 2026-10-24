import SwiftUI

/// The whole upgrade flow, presented full screen: the main paywall (weekly
/// and annual), then, if someone closes it without buying,
/// a one-time lifetime offer. Dismisses itself when done.
struct PaywallFlow: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .paywall

    private enum Stage {
        case paywall
        case lifetimeOffer
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch stage {
            case .paywall:
                PaywallView(onClose: closePaywall, onPurchased: { dismiss() })
                    .transition(.opacity)
            case .lifetimeOffer:
                LifetimeOfferView(onClose: { dismiss() }, onPurchased: { dismiss() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: stage)
        .interactiveDismissDisabled(purchases.isPurchasing)
    }

    private func closePaywall() {
        if purchases.canShowLifetimeOffer {
            purchases.markLifetimeOfferShown()
            stage = .lifetimeOffer
        } else {
            dismiss()
        }
    }
}

/// Main paywall: Pro features and the two recurring plans.
struct PaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @State private var selected: Plan = .annual
    @State private var restoreMessage: String?

    let onClose: () -> Void
    let onPurchased: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    features
                    VStack(spacing: 12) {
                        ForEach(Plan.paywallPlans) { plan in
                            PlanOption(plan: plan, isSelected: plan == selected) { selected = plan }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 20)
            }

            footer
        }
        .overlay(alignment: .topTrailing) {
            CloseButton(action: onClose)
                .disabled(purchases.isPurchasing)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .alert(
            "Restore Purchases",
            isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            IllustrationView(.compress, size: 84)
                .rotationEffect(.degrees(-6))
            Text("Shrink it.\nDon't delete it.")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("Pro makes your photos and videos smaller, so you get the space back and keep the memories.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Plan.proFeatures, id: \.text) { feature in
                Label {
                    Text(feature.text)
                } icon: {
                    Image(systemName: feature.symbol)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 26)
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .card()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await purchases.purchase(selected)
                    onPurchased()
                }
            } label: {
                if purchases.isPurchasing {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.sticker)
            .disabled(purchases.isPurchasing)

            Text(termsLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Restore Purchases") {
                Task {
                    restoreMessage = await purchases.restore()
                        ? "Your purchase has been restored."
                        : "No previous purchase was found."
                }
            }
            .font(.footnote.weight(.medium))
            .disabled(purchases.isPurchasing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background)
    }

    private var termsLine: String {
        "\(selected.displayPrice)\(selected.cadence), renews automatically. Cancel anytime in Settings."
    }
}

/// One selectable plan row on the paywall.
private struct PlanOption: View {
    let plan: Plan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.mint, in: Capsule())
                                .foregroundStyle(Color(hex: 0x1A1A17))
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(plan.displayPrice)
                        .font(.metric(.headline))
                    Text(plan.cadence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sticker(fill: isSelected ? Theme.mintSoft : Theme.surface, padding: 16)
        .opacity(isSelected ? 1 : 0.85)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badge: String? {
        switch plan {
        case .weekly: nil
        case .annual: "SAVE \(Plan.annualSavingsPercent)%"
        case .lifetime: nil
        }
    }

    private var subtitle: String {
        switch plan {
        case .weekly: "Billed weekly, cancel anytime"
        case .annual: "Just \(Plan.annualPerWeek)/week, billed yearly"
        case .lifetime: "Pay once"
        }
    }
}

/// Shown once, after someone closes the paywall without buying.
struct LifetimeOfferView: View {
    @Environment(PurchaseStore.self) private var purchases

    let onClose: () -> Void
    let onPurchased: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            IllustrationView(.piggy, size: 120)
                .rotationEffect(.degrees(8))

            VStack(spacing: 10) {
                Text("ONE-TIME OFFER")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                Text("Not into subscriptions?\nPay once. Keep Pro forever.")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                Text("Every Pro feature, every future update, no renewals. You won't see this offer again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text(Plan.lifetime.displayPrice)
                    .font(.metric(.largeTitle))
                Text("one payment")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .sticker(fill: Theme.mintSoft, padding: 20)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button {
                    Task {
                        await purchases.purchase(.lifetime)
                        onPurchased()
                    }
                } label: {
                    if purchases.isPurchasing {
                        ProgressView()
                    } else {
                        Text("Get Lifetime for \(Plan.lifetime.displayPrice)")
                    }
                }
                .buttonStyle(.sticker)

                Button("No thanks", action: onClose)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .disabled(purchases.isPurchasing)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Theme.well, in: Circle())
        }
        .accessibilityLabel("Close")
    }
}

#Preview("Paywall") {
    PaywallFlow()
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}

#Preview("Lifetime offer") {
    LifetimeOfferView(onClose: {}, onPurchased: {})
        .background(Theme.background)
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}
