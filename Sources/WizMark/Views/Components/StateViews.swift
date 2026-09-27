import SwiftUI

// MARK: - LoadingView

struct LoadingView: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(subtitle)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}

// MARK: - ErrorView

struct ErrorView: View {
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "error.title", defaultValue: "Something went wrong"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
            }
        }
    }
}
