import StorageCore
import SwiftUI

/// Shown after a simulated cleanup: what was recovered, with undo.
struct CleanupResultView: View {
    @Environment(AppModel.self) private var model
    let result: CleanupResult
    let onDone: () -> Void

    @State private var undone = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                IllustrationView(undone ? .reset : .shieldCheck, size: 112)
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(undone ? "Change undone" : headline)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if !undone {
                        SizeText(bytes: result.bytesRecovered, style: .largeTitle, unitStyle: .title2)
                        Text("recovered in the demo library")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("The demo library is back the way it was.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !undone {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(details, id: \.self) { line in
                            Label(line, systemImage: "checkmark")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                VStack(spacing: 12) {
                    Button("Done", action: onDone)
                        .buttonStyle(.sticker)
                    if !undone && model.canUndo {
                        Button("Undo") {
                            Task {
                                await model.undoLastChange()
                                undone = true
                            }
                        }
                        .buttonStyle(.soft)
                        .disabled(model.isWorking)
                    }
                }
                .padding(.top, 6)

                SafetyNote(text: "This was a simulation. No photos or videos on your iPhone were changed.")
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private var headline: String {
        switch result.kind {
        case .deletion: "Deleted from demo"
        case .compression: "Compressed in demo"
        }
    }

    private var details: [String] {
        switch result.kind {
        case .deletion:
            return ["\(result.itemCount.formatted()) items removed from the sample library"]
        case .compression(let level):
            var lines = ["\(result.itemCount.formatted()) items compressed at \(level.title)"]
            if result.skippedCount > 0 {
                lines.append("\(result.skippedCount.formatted()) items skipped (not supported or already compressed)")
            }
            return lines
        }
    }
}

#Preview {
    CleanupResultView(
        result: CleanupResult(kind: .compression(.balanced), itemCount: 42, bytesRecovered: 3_400_000_000, skippedCount: 3),
        onDone: {}
    )
    .environment(AppModel.preview())
}
