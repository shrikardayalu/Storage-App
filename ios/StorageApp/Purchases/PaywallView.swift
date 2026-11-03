import StorageCore
import SwiftUI

/// What the paywall knows about this person's library, so it can lead with
/// their own number instead of a generic pitch.
struct PaywallContext: Equatable {
    /// What the shrink tools could save in the scanned album, if a scan ran.
    var proBytes: Int64?

    static let generic = PaywallContext(proBytes: nil)
}

/// The whole upgrade flow: the main paywall (weekly and annual), then, if
/// someone closes it without buying, a one-time lifetime offer. Calls
/// `onDone` when finished, or dismisses itself when presented on its own.
struct PaywallFlow: View {
    var context: PaywallContext = .generic
    var onDone: (() -> Void)?

    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .paywall

    private enum Stage {
        case paywall
        case lifetimeOffer
    }

    var body: some View {
        ZStack {
            PaperBackground()
            switch stage {
            case .paywall:
                PaywallView(context: context, onClose: closePaywall, onPurchased: finish)
                    .transition(.paperSwap)
            case .lifetimeOffer:
                LifetimeOfferView(onClose: finish, onPurchased: finish)
                    .transition(.paperSwap)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: stage)
        .interactiveDismissDisabled(purchases.isPurchasing)
    }

    private func closePaywall() {
        if purchases.canShowLifetimeOffer {
            purchases.markLifetimeOfferShown()
            stage = .lifetimeOffer
        } else {
            finish()
        }
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }
}

/// Main paywall: the person's own saving, what Pro does, and the two recurring plans.
struct PaywallView: View {
    let context: PaywallContext
    let onClose: () -> Void
    let onPurchased: () -> Void

    @Environment(PurchaseStore.self) private var purchases
    @State private var selected: Plan = .annual
    @State private var message: PaywallMessage?
    @State private var progress: CGFloat = 0
    @State private var showsClose = false
    @State private var boughtTick = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    features
                    VStack(spacing: 12) {
                        ForEach(Plan.paywallPlans) { plan in
                            PlanOption(plan: plan, price: purchases.displayPrice(plan), isSelected: plan == selected) {
                                selected = plan
                            }
                        }
                    }
                    .opacity(sketchStep(progress, start: 0.55, length: 0.2))
                    .offset(y: 16 * (1 - sketchStep(progress, start: 0.55, length: 0.2)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .overlay(alignment: .topTrailing) {
            CloseButton(action: onClose)
                .disabled(purchases.isPurchasing)
                .opacity(showsClose ? 1 : 0)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .drawing($progress, duration: 1.8)
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) { showsClose = true }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.success, trigger: boughtTick)
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bytes = context.proBytes, bytes > 0 {
                Text("your scan found")
                    .font(.hand(20))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.15)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(ByteFormatter.string(bytes, precision: .twoDecimals))
                        .font(.display(58))
                        .monospacedDigit()
                        .boiling()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .overlay(alignment: .bottomLeading) {
                    InkUnderline(progress: progress, start: 0.12)
                        .frame(height: 12)
                        .offset(y: 10)
                }
                Text("you can get back by shrinking, not deleting.")
                    .font(.display(24))
                    .boiling()
                    .padding(.top, 6)
            } else {
                HStack(alignment: .top) {
                    Text("Shrink it.\nDon't delete it.")
                        .font(.display(40))
                        .boiling()
                    Spacer(minLength: 0)
                    IllustrationView(.compress, size: 76)
                        .rotationEffect(.degrees(-8))
                        .boilingShape(seed: 3)
                        .stamped(progress, at: 0.1)
                }
            }
            Text("Pro makes your photos and videos smaller, so you get the space back and keep every memory.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Array(Plan.proFeatures.enumerated()), id: \.element.text) { index, feature in
                HStack(spacing: 12) {
                    InkCheck(isOn: progress > 0.25 + Double(index) * 0.07, size: 24)
                    Text(feature.text)
                        .font(.subheadline.weight(.semibold))
                }
            }
            DashedRule().padding(.vertical, 2)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Theme.accent)
                Text("Deleting, duplicates and junk stay free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceipt(padding: 18)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: buy) {
                if purchases.isPurchasing {
                    ProgressView()
                } else {
                    Text(selected == .annual ? "Get Pro for the year" : "Get Pro")
                }
            }
            .buttonStyle(.sticker)
            .disabled(purchases.isPurchasing)

            Text(termsLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LegalLinks(onRestore: restore)
                .disabled(purchases.isPurchasing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background.opacity(0.96))
    }

    private var termsLine: String {
        "\(purchases.displayPrice(selected))\(selected.cadence), renews automatically. Cancel anytime in Settings."
    }

    private func buy() {
        Task {
            let outcome = await purchases.purchase(selected)
            handle(outcome, onPurchased: onPurchased, boughtTick: &boughtTick, message: &message)
        }
    }

    private func restore() {
        Task {
            if await purchases.restore() {
                boughtTick += 1
                onPurchased()
            } else {
                message = PaywallMessage(title: "Restore Purchases", body: "No earlier purchase was found for this Apple ID.")
            }
        }
    }
}

/// An alert on the paywall.
struct PaywallMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

@MainActor
private func handle(_ outcome: PurchaseStore.Outcome, onPurchased: () -> Void, boughtTick: inout Int, message: inout PaywallMessage?) {
    switch outcome {
    case .purchased:
        boughtTick += 1
        onPurchased()
    case .cancelled:
        break
    case .pending:
        message = PaywallMessage(title: "Waiting for approval", body: "Pro turns on by itself as soon as the purchase is approved.")
    case .failed(let reason):
        message = PaywallMessage(title: "Purchase didn't go through", body: reason)
    }
}

/// Restore, Terms and Privacy, in one quiet row.
private struct LegalLinks: View {
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button("Restore", action: onRestore)
            Text("·").foregroundStyle(.tertiary)
            Link("Terms", destination: PaywallConfig.termsURL)
            Text("·").foregroundStyle(.tertiary)
            Link("Privacy", destination: PaywallConfig.privacyURL)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

/// A hand-drawn underline that draws itself in under a big number.
struct InkUnderline: View {
    let progress: CGFloat
    var start: CGFloat = 0
    private static let design = CGSize(width: 200, height: 12)

    var body: some View {
        BoilPoseReader { pose in
            DrawnStroke(
                path: Sketch.boil(Sketch.curve([CGPoint(x: 2, y: 8), CGPoint(x: 70, y: 4), CGPoint(x: 140, y: 7), CGPoint(x: 198, y: 3)], wobble: 1.4, seed: 70), pose: pose, amount: 0.8),
                design: Self.design, progress: progress, start: start, length: 0.2, showsPenTip: false
            )
            .stroke(Theme.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// One selectable plan row on the paywall.
private struct PlanOption: View {
    let plan: Plan
    let price: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                InkCheck(isOn: isSelected, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
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
        .overlay(alignment: .topTrailing) {
            if plan == .annual {
                RubberStamp(top: "save", main: "\(Plan.annualSavingsPercent)%", color: Theme.tomato, angle: 8)
                    .scaleEffect(0.72)
                    .offset(x: 8, y: -20)
                    .boilingShape(0.35, seed: 9)
            }
        }
        .scaleEffect(isSelected ? 1 : 0.98)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @State private var progress: CGFloat = 0
    @State private var message: PaywallMessage?
    @State private var boughtTick = 0

    let onClose: () -> Void
    let onPurchased: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            IllustrationView(.piggy, size: 128)
                .rotationEffect(.degrees(8))
                .boilingShape(seed: 5)
                .stamped(progress, at: 0.05)

            VStack(spacing: 10) {
                Text("one-time offer")
                    .font(.hand(20))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0.12, length: 0.15)
                Text("Not into subscriptions?\nPay once. Keep Pro forever.")
                    .font(.display(32))
                    .multilineTextAlignment(.center)
                    .boiling()
                Text("Every Pro feature, every future update, no renewals. You won't see this offer again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text(purchases.displayPrice(.lifetime))
                    .font(.display(44))
                    .monospacedDigit()
                    .boiling()
                Text("one payment")
                    .font(.hand(18))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .onReceipt(padding: 18)
            .stamped(progress, at: 0.35)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button {
                    Task {
                        let outcome = await purchases.purchase(.lifetime)
                        handle(outcome, onPurchased: onPurchased, boughtTick: &boughtTick, message: &message)
                    }
                } label: {
                    if purchases.isPurchasing {
                        ProgressView()
                    } else {
                        Text("Get Lifetime for \(purchases.displayPrice(.lifetime))")
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
        .drawing($progress, duration: 1.4)
        .sensoryFeedback(.success, trigger: boughtTick)
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
        }
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
    PaywallFlow(context: PaywallContext(proBytes: 3_420_000_000))
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}

#Preview("Lifetime offer") {
    LifetimeOfferView(onClose: {}, onPurchased: {})
        .background(PaperBackground())
        .environment(PurchaseStore(defaults: UserDefaults(suiteName: "preview")!))
        .tint(Theme.accent)
}
