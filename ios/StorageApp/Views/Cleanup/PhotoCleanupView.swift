import StorageCore
import SwiftUI

/// Pro: one tap turns every Live Photo into a still, removes the extra
/// copies of each duplicate (the best copy stays) and clears the blurry,
/// black and old shots. Receipts and documents are left alone, in case
/// they're still needed. It shows exactly what will happen first, and
/// everything removed waits in Recently Deleted for 30 days.
struct PhotoCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var blocked: Set<MediaItem.ID>?
    @State private var error: PhotoChangeError?
    @State private var confirming = false
    /// Old screenshots are the one group people often still want (tickets,
    /// codes, things to remember), so they get their own switch.
    @AppStorage("photoCleanup.oldScreenshots") private var includeScreenshots = true

    private var plan: PhotoCleanupPlan? {
        guard let report = model.junkReport else { return nil }
        return PhotoCleanupPlan(report: report, livePhotos: model.suggestedLivePhotos ?? [], blocked: blocked ?? [],
                                includeOldScreenshots: includeScreenshots)
    }

    /// Something to show: a cleanup, or old screenshots that are switched off.
    private func hasFindings(_ plan: PhotoCleanupPlan) -> Bool {
        !plan.isEmpty || plan.oldScreenshotCount > 0
    }

    /// Said in the confirmation, so old screenshots never go unmentioned.
    private var screenshotClause: String {
        guard let plan, plan.includesOldScreenshots, plan.oldScreenshotCount > 0 else { return "" }
        return plan.oldScreenshotCount == 1 ? ", along with 1 old screenshot" : ", along with \(plan.oldScreenshotCount) old screenshots"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.isAnalyzing || plan == nil {
                    PhotoAnalysisLoader(caption: "Checking each photo, on this iPhone. Nothing leaves it.")
                }
                if let plan, !hasFindings(plan), !model.isAnalyzing {
                    EmptyStateView(
                        illustration: .shieldCheck,
                        title: "Already tidy",
                        message: "No Live Photos, duplicates or junk to clean in your library."
                    )
                } else if let plan, hasFindings(plan) {
                    summary(plan)
                }
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.tomatoInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 130)
        }
        .background(PaperBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let plan, !plan.isEmpty { actionBar(plan) }
        }
        .overlay {
            if model.isChanging { WorkingOverlay(message: "Cleaning up your photos…") }
        }
        .confirmationDialog("Clean up your photos?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clean up \(plan.map { ByteFormatter.string($0.totalBytes, precision: .twoDecimals) } ?? "")", role: .destructive) {
                Task { await cleanUp() }
            }
        } message: {
            Text("Live Photos become stills, extra copies and junk are removed\(screenshotClause). Everything replaced or removed goes to Recently Deleted, where you can recover it for 30 days. iOS may ask you to confirm each part.")
        }
        .task {
            await model.findJunk()
            await runCheck()
        }
        .onChange(of: model.libraryScan) { _, _ in Task { await runCheck() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("one tap, every photo checked")
                .font(.hand(20))
                .foregroundStyle(Theme.accent)
            Text("Photo Cleanup")
                .font(.display(32))
                .boiling()
                .accessibilityAddTraits(.isHeader)
            if let plan, !plan.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Frees about")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SizeText(bytes: plan.totalBytes, style: .title, unitStyle: .headline, precision: .twoDecimals)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.top, 8)
    }

    private func summary(_ plan: PhotoCleanupPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                if plan.stillCount > 0 {
                    line("Live Photos \u{2192} stills", count: plan.stillCount, bytes: plan.convertBytes, note: "ones that don't need to move")
                }
                if plan.copyCount > 0 {
                    line("Extra copies", count: plan.copyCount, bytes: plan.copyBytes, note: "the best copy of each stays")
                }
                if plan.blurryCount > 0 {
                    line("Blurry and black shots", count: plan.blurryCount, bytes: plan.blurryBytes, note: "out of focus, or nearly all black")
                }
                if plan.oldScreenshotCount > 0 {
                    Toggle(isOn: $includeScreenshots) {
                        line("Old screenshots", count: plan.oldScreenshotCount,
                             bytes: includeScreenshots ? plan.oldScreenshotBytes : 0,
                             note: includeScreenshots ? "every screenshot over a month old" : "left alone")
                    }
                    .tint(Theme.accent)
                    .disabled(model.isChanging)
                }
            }
            .onReceipt()
            Text("Favorites, photos you edited, people, pets and scenery are left alone, and so are receipts and documents. To pick one by one, use Duplicates and junk or Live Photos \u{2192} stills instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ title: String, count: Int, bytes: Int64, note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("×\(count)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\u{2212}" + ByteFormatter.string(bytes, precision: .twoDecimals))
                .font(.metric(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionBar(_ plan: PhotoCleanupPlan) -> some View {
        VStack(spacing: 6) {
            Button("Clean up \(ByteFormatter.string(plan.totalBytes, precision: .twoDecimals))") { confirming = true }
                .buttonStyle(.sticker)
                .disabled(model.isChanging || model.isAnalyzing || blocked == nil)
            Text("Everything goes to Recently Deleted first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    /// Checks every photo the cleanup would touch, so blocked ones are skipped.
    private func runCheck() async {
        guard let report = model.junkReport else { return }
        let all = Set(report.findings.map(\.id))
            .union(report.duplicates.flatMap(\.items).map(\.id))
            .union((model.suggestedLivePhotos ?? []).map(\.id))
        guard !all.isEmpty else { blocked = []; return }
        switch await model.albumCheck(all) {
        case .success(let check):
            blocked = check.missing
            error = nil
        case .failure(let failure):
            blocked = nil
            error = failure
        }
    }

    private func cleanUp() async {
        guard let plan, !plan.isEmpty else { return }
        if let failure = await model.cleanUpPhotos(plan) {
            await runCheck()
            // After the check: a successful re-check used to clear this message.
            error = failure
        }
    }
}

#Preview {
    NavigationStack { PhotoCleanupView() }
        .environment(AppModel.preview())
}
