import PhotosUI
import SwiftUI

// MARK: - ProfileSetupView

/// First-time profile setup after sign-up.
/// Collects an avatar and display name, then marks the profile as complete
/// so the user can proceed to the main app.
struct ProfileSetupView: View {

    // MARK: - Environment

    @Environment(AppServices.self) private var services

    // MARK: - State

    @State private var viewModel: ProfileSetupViewModel?
    @State private var avatarPickerItem: PhotosPickerItem?

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                setupForm(viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.wizmarkBackground)
            }
        }
        .task {
            guard let userService = services.user else { return }
            viewModel = ProfileSetupViewModel(userService: userService)
        }
    }

    // MARK: - Setup Form

    @ViewBuilder
    private func setupForm(_ vm: ProfileSetupViewModel) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "profile.title"))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.wizmarkText)

                    Text(String(localized: "profile.subtitle"))
                        .font(.body)
                        .foregroundStyle(Color.wizmarkTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 32)

                // Avatar Section
                avatarSection(vm)
                    .padding(.bottom, 32)

                // Display Name
                displayNameSection(vm)
                    .padding(.bottom, 32)

                // Continue Button
                continueButton(vm)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.wizmarkBackground)
        .onChange(of: avatarPickerItem) { _, newItem in
            Task { await vm.handleAvatarSelection(newItem) }
        }
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(
                get: { vm.showError },
                set: { vm.showError = $0 }
            ),
            actions: {
                Button(String(localized: "common.ok"), role: .cancel) {}
            },
            message: {
                Text(vm.error?.localizedDescription ?? "")
            }
        )
    }

    // MARK: - Avatar Section

    @ViewBuilder
    private func avatarSection(_ vm: ProfileSetupViewModel) -> some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                ZStack {
                    if let localImage = vm.localAvatarImage {
                        Image(uiImage: localImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 112, height: 112)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.wizmarkBorder, lineWidth: 1)
                            )
                    } else {
                        Circle()
                            .fill(Color.wizmarkSurfaceVariant)
                            .frame(width: 112, height: 112)
                            .overlay(
                                Image(systemName: "camera")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.wizmarkTextMuted)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.wizmarkBorder, lineWidth: 1)
                            )
                    }

                    // Camera badge
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.wizmarkAccent)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.wizmarkBackground, lineWidth: 2)
                        )
                        .offset(x: 38, y: 38)
                }
            }
            .disabled(vm.isUploadingAvatar || vm.isSubmitting)

            Text(avatarLabel(vm))
                .font(.subheadline)
                .foregroundStyle(Color.wizmarkAccent)
        }
    }

    private func avatarLabel(_ vm: ProfileSetupViewModel) -> String {
        if vm.isUploadingAvatar {
            return String(localized: "profile.saving")
        }
        if vm.localAvatarImage != nil {
            return String(localized: "profile.changePhoto")
        }
        return String(localized: "profile.choosePhoto")
    }

    // MARK: - Display Name Section

    @ViewBuilder
    private func displayNameSection(_ vm: ProfileSetupViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.displayName"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.wizmarkText)

            TextField(
                String(localized: "profile.displayNamePlaceholder"),
                text: Binding(
                    get: { vm.displayName },
                    set: { vm.displayName = $0 }
                )
            )
            .textInputAutocapitalization(.words)
            .textContentType(.name)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.wizmarkFieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.wizmarkBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Continue Button

    @ViewBuilder
    private func continueButton(_ vm: ProfileSetupViewModel) -> some View {
        Button {
            Task { await vm.completeSetup() }
        } label: {
            Group {
                if vm.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(String(localized: "profile.continue"))
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(vm.canSubmit ? Color.wizmarkAccent : Color.wizmarkAccent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(!vm.canSubmit)
    }
}
