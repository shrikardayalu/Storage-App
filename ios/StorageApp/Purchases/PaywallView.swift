import StorageCore
import SwiftUI

/// What the paywall knows about this person's library, so it can lead with
/// their own number instead of a generic pitch.
struct PaywallContext: Equatable {
    /// What the Pro tools could save in the scanned album, if a scan ran.
    var proBytes: Int64?
    /// Set when the paywall follows a free cleanup: what that cleanup freed.
    var freedBytes: Int64? = nil

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
        // One fixed composition: pitch, benefits, plans and buy all fit without scrolling.
        VStack(alignment: .leading, spacing: 10) {
            header
            features
            planPicker
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 6)
        .overlay(alignment: .topTrailing) {
            CloseButton(action: onClose)
                .disabled(purchases.isPurchasing)
                .opacity(showsClose ? 1 : 0)
                .padding(.trailing, 16)
                .padding(.top, 8)
        }
        .drawing($progress, duration: 1.8)
        .task {
            // Short enough that App Review doesn't read it as a hidden close.
            try? await Task.sleep(for: .seconds(0.5))
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
        VStack(alignment: .leading, spacing: 4) {
            if let bytes = context.proBytes, bytes > 0 {
                Text(eyebrow)
                    .font(.hand(16))
                    .foregroundStyle(Theme.accent)
                    .handwritten(progress, start: 0, length: 0.15)
                Text(ByteFormatter.string(bytes, precision: .twoDecimals))
                    .font(.display(42))
                    .monospacedDigit()
                    .boiling()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .overlay(alignment: .bottomLeading) {
                        InkUnderline(progress: progress, start: 0.12)
                            .frame(height: 10)
                            .offset(y: 8)
                    }
                Text(context.freedBytes == nil ? "more you can get back with Pro." : "more waiting for Pro.")
                    .font(.display(20))
                    .boiling()
                    .padding(.top, 2)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Text("Shrink it.\nDon't delete it.")
                        .font(.display(32))
                        .boiling()
                    Spacer(minLength: 0)
                    IllustrationView(.compress, size: 56)
                        .rotationEffect(.degrees(-8))
                        .boilingShape(seed: 3)
                        .stamped(progress, at: 0.1)
                }
            }
        }
    }

    private var eyebrow: String {
        guard let freed = context.freedBytes, freed > 0 else { return "your scan found" }
        return "you just freed \(ByteFormatter.string(freed, precision: .twoDecimals)). nice. there's"
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(Plan.proFeatures.enumerated()), id: \.element.text) { index, feature in
                HStack(spacing: 12) {
                    InkCheck(isOn: progress > 0.22 + Double(index) * 0.05, size: 22)
                    Text(feature.text)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            DashedRule().padding(.vertical, 2)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Theme.accent)
                Text("Deleting, duplicates and junk stay free.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // Grows the receipt into leftover height so plans stay tight underneath.
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onReceipt(padding: 16)
    }

    private var planPicker: some View {
        VStack(spacing: 8) {
            ForEach(Array(Plan.paywallPlans.enumerated()), id: \.element.id) { index, plan in
                PlanOption(plan: plan, price: purchases.displayPrice(plan), annualPerWeek: purchases.annualPerWeek,
                           savingsPercent: purchases.annualSavingsPercent, isSelected: plan == selected) {
                    selected = plan
                }
                // Outline then ink-wash, same sticker draw-in as the rest of the app.
                .inkedIn(progress, start: 0.52 + CGFloat(index) * 0.14, length: 0.28,
                         seed: 40 &+ UInt64(index) &* 7)
            }
        }
        // Room for the annual "save %" stamp that sits above the card.
        .padding(.top, 12)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button(action: buy) {
                if purchases.isPurchasing {
                    ProgressView()
                } else {
                    Text(selected == .annual ? "Get Pro for the year" : "Get Pro")
                }
            }
            .buttonStyle(.sticker)
            .disabled(purchases.isPurchasing)
            .inkedIn(progress, start: 0.78, length: 0.2, seed: 61)

            Text(termsLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .settlesIn(progress, start: 0.9, length: 0.1)

            LegalLinks(onRestore: restore)
                .disabled(purchases.isPurchasing)
                .settlesIn(progress, start: 0.92, length: 0.08)
        }
    }

    private var termsLine: String {
        purchases.disclosure(selected)
    }

    private func buy() {
        Task {
            let outcome = await purchases.purchase(selected)
            handle(outcome, onPurchased: onPurchased, boughtTick: &boughtTick, message: &message)
        }
    }

    private func restore() {
        restorePurchases(purchases, onPurchased: onPurchased, boughtTick: $boughtTick, message: $message)
    }
}

/// Restore from either paywall screen: Pro found closes the flow, nothing found says so.
@MainActor
private func restorePurchases(_ purchases: PurchaseStore, onPurchased: @escaping () -> Void,
                              boughtTick: Binding<Int>, message: Binding<PaywallMessage?>) {
    Task {
        if await purchases.restore() {
            boughtTick.wrappedValue += 1
            onPurchased()
        } else {
            message.wrappedValue = PaywallMessage(title: "Restore Purchases", body: "No earlier purchase was found for this Apple ID.")
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
    /// Both from the storefront's prices once products load.
    let annualPerWeek: String
    let savingsPercent: Int
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
        .sticker(fill: isSelected ? Theme.mintSoft : Theme.surface, padding: 12)
        .overlay(alignment: .topTrailing) {
            if plan == .annual {
                RubberStamp(top: "save", main: "\(savingsPercent)%", color: Theme.tomato, angle: 8)
                    .scaleEffect(0.62)
                    .offset(x: 6, y: -14)
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
        case .annual: "Just \(annualPerWeek)/week, billed yearly"
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

                Text(purchases.disclosure(.lifetime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Restore has to be reachable from every screen that sells (Guideline 3.1.1).
                LegalLinks {
                    restorePurchases(purchases, onPurchased: onPurchased, boughtTick: $boughtTick, message: $message)
                }
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
