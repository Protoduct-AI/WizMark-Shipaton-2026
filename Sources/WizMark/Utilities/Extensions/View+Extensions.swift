import SwiftUI

// MARK: - Loading Overlay

extension View {

    /// Displays a translucent overlay with a `ProgressView` when `isLoading` is `true`.
    func loadingOverlay(isLoading: Bool) -> some View {
        overlay {
            if isLoading {
                ZStack {
                    Color.wizmarkOverlay
                        .ignoresSafeArea()

                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
    }
}

// MARK: - Error Alert

extension View {

    /// Presents an alert driven by an optional `Error`.
    /// The alert is shown when `error` is non-nil and dismissed when the user taps OK,
    /// which also calls `onDismiss`.
    func errorAlert(
        error: Binding<(any Error)?>,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        alert(
            String(localized: "error.title"),
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            ),
            actions: {
                Button(String(localized: "common.cancel"), role: .cancel) {
                    error.wrappedValue = nil
                    onDismiss()
                }
            },
            message: {
                Text(error.wrappedValue?.localizedDescription ?? "")
            }
        )
    }
}

// MARK: - Dismiss Keyboard

extension View {

    /// Adds a tap gesture outside interactive controls to dismiss the keyboard.
    func dismissKeyboard() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }
}

// MARK: - Card Style

extension View {

    /// Applies a consistent card appearance: surface background, rounded corners,
    /// subtle border, and a soft shadow.
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color.wizmarkSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.wizmarkBorder, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Empty State

extension View {

    /// Conditionally replaces the receiver with an empty-state placeholder.
    ///
    /// When `isEmpty` is `true`, a centered column with the given SF Symbol and message
    /// is displayed instead of the original content.
    @ViewBuilder
    func emptyState(isEmpty: Bool, message: String, icon: String = "tray") -> some View {
        if isEmpty {
            ContentUnavailableView {
                Label(message, systemImage: icon)
                    .foregroundStyle(Color.wizmarkTextSecondary)
            }
        } else {
            self
        }
    }
}
