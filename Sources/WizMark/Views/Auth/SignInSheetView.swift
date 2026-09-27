import ClerkKit
import ClerkKitUI
import SwiftUI

struct SignInSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var clerkLoaded = Clerk.shared.isLoaded
    @State private var timedOut = false

    var body: some View {
        Group {
            if clerkLoaded {
                AuthView()
                    .environment(Clerk.shared)
            } else if timedOut {
                errorView
            } else {
                loadingView
            }
        }
        .onAppear { waitForClerk() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "signIn.loading", defaultValue: "読み込み中..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(String(localized: "signIn.connectionError", defaultValue: "接続できませんでした"))
                .font(.headline)

            Text(String(localized: "signIn.checkNetwork", defaultValue: "ネットワーク接続を確認してください"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                timedOut = false
                waitForClerk()
            } label: {
                Label(String(localized: "signIn.retry", defaultValue: "再試行"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)

            Button(String(localized: "common.close", defaultValue: "閉じる")) {
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
    }

    private func waitForClerk() {
        Task { @MainActor in
            for _ in 0..<100 {
                if Clerk.shared.isLoaded {
                    clerkLoaded = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            timedOut = true
        }
    }
}
