import SwiftData
import SwiftUI

/// Shows that AI enrichment is running, or that it failed and why.
///
/// Extraction takes long enough that a bookmark saved without one looks broken:
/// the card sits there with no summary and no tags, and nothing says whether
/// anything is coming. This is the only signal the user gets, so it stays
/// visible for the whole request rather than flashing once at the start.
///
/// Renders nothing once enrichment has finished — the extracted fields are the
/// success state, and a badge on top of them would only add noise.
struct AIStatusBadge: View {

    let bookmark: Bookmark
    var style: Style = .full

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @State private var isRetrying = false

    enum Style {
        /// Icon, wording, and a way to try again. For a detail screen.
        case full
        /// Icon only. For a row, where horizontal space is contested.
        case compact
    }

    var body: some View {
        if bookmark.isEnriching || isRetrying {
            running
        } else if bookmark.isEnrichmentFailed {
            failed
        }
    }

    private var running: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini)
            if style == .full {
                Text(String(localized: "ai.status.analyzing", defaultValue: "AI が解析中"))
                    .font(.caption)
            }
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, style == .full ? 8 : 0)
        .padding(.vertical, style == .full ? 4 : 0)
        .background {
            if style == .full {
                Capsule().fill(Color.accentColor.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "ai.status.analyzing", defaultValue: "AI が解析中"))
    }

    @ViewBuilder
    private var failed: some View {
        if style == .compact {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    String(localized: "ai.status.failed", defaultValue: "AI 解析に失敗")
                )
        } else {
            // The reason matters more than the fact: waiting, reconnecting and
            // subscribing are different actions, and "failed" points at none of
            // them.
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(bookmark.aiError ?? String(
                        localized: "ai.status.failed",
                        defaultValue: "AI 解析に失敗"
                    ))
                    .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .foregroundStyle(.orange)

                Button {
                    retry()
                } label: {
                    Label(
                        String(localized: "ai.status.retry", defaultValue: "もう一度試す"),
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Queues the bookmark again and starts a pass immediately.
    ///
    /// Marking it pending alone would leave the user waiting for whatever
    /// triggers the next sweep, which from their side is indistinguishable from
    /// the button doing nothing.
    private func retry() {
        isRetrying = true
        bookmark.aiStatus = "pending"
        bookmark.aiError = nil
        try? modelContext.save()

        let context = modelContext
        Task {
            await AIExtractionService.shared.process(bookmark: bookmark, context: context)
            isRetrying = false
        }
    }
}
