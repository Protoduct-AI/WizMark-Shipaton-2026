import SwiftUI

// MARK: - NotificationPermissionView

/// Explains push notification benefits and requests system permission.
/// Used in the onboarding flow and as a standalone screen from settings.
///
/// - "Enable" triggers the system permission dialog.
/// - "Skip" dismisses without requesting.
///
/// When used in onboarding, the caller is responsible for advancing to the next step
/// after `onComplete` fires.
struct NotificationPermissionView: View {

    // MARK: - Environment

    @Environment(AppServices.self) private var services

    // MARK: - Callbacks

    /// Called when the user finishes (either by granting, denying, or skipping).
    var onComplete: () -> Void

    // MARK: - State

    @State private var isRequesting: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            illustration

            Spacer()

            buttonSection
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .background(Color.wizmarkBackground)
    }

    // MARK: - Illustration + Copy

    private var illustration: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.wizmarkSurfaceVariant)
                    .frame(width: 128, height: 128)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.wizmarkAccent)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 12) {
                Text(String(localized: "notifications.prompt.title"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.wizmarkText)
                    .multilineTextAlignment(.center)

                Text(String(localized: "notifications.prompt.description"))
                    .font(.body)
                    .foregroundStyle(Color.wizmarkTextMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 12) {
            // Enable Button
            Button {
                Task { await handleAllow() }
            } label: {
                Group {
                    if isRequesting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "notifications.prompt.allow"))
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.wizmarkAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isRequesting)

            // Skip Button
            Button {
                handleSkip()
            } label: {
                Text(String(localized: "notifications.prompt.skip"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.wizmarkTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .disabled(isRequesting)
        }
    }

    // MARK: - Actions

    private func handleAllow() async {
        guard !isRequesting else { return }
        isRequesting = true

        _ = await services.notifications.requestPermission()

        Storage.set(true, for: .notificationPromptDone)
        isRequesting = false
        onComplete()
    }

    private func handleSkip() {
        Storage.set(true, for: .notificationPromptDone)
        onComplete()
    }
}
