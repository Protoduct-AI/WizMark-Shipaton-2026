import ClerkKit
import Humation
import SwiftUI
import os

struct ProfileEditView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @AppStorage("avatar_data") private var avatarData: String?
    @State private var displayName: String = ""
    @State private var showAvatarEditor = false
    @State private var isSaving = false
    @State private var saveError: String?

    private var seed: String {
        Clerk.shared.user?.id ?? "default"
    }

    private var avatarImage: UIImage? {
        StoredAvatar.image(json: avatarData, seed: seed, pixels: 192)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let img = avatarImage {
                            Image(uiImage: img)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                        }
                        Button(String(localized: "profile.edit.avatar", defaultValue: "アバターを編集")) {
                            showAvatarEditor = true
                        }
                        .font(.subheadline)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField(String(localized: "profile.edit.nickname", defaultValue: "ニックネーム"), text: $displayName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text(String(localized: "profile.edit.displayName", defaultValue: "表示名"))
            } footer: {
                Text(String(localized: "profile.edit.displayName.footer", defaultValue: "他のユーザーに表示される名前です"))
            }

            if let email = Clerk.shared.user?.primaryEmailAddress?.emailAddress {
                Section {
                    HStack {
                        Text(String(localized: "profile.edit.email", defaultValue: "メール"))
                        Spacer()
                        Text(email)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "profile.edit.title", defaultValue: "プロフィールを編集"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save", defaultValue: "保存")) {
                    save()
                }
                .bold()
                .disabled(isSaving)
            }
        }
        .sheet(isPresented: $showAvatarEditor) {
            NavigationStack {
                AvatarEditorView(currentSeed: seed, currentData: avatarData) { resolved in
                    avatarData = StoredAvatar.encode(resolved)
                    uploadAvatarToConvex(resolved)
                }
            }
        }
        .onAppear {
            let user = Clerk.shared.user
            let first = user?.firstName ?? ""
            let last = user?.lastName ?? ""
            let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            displayName = full.isEmpty ? (user?.username ?? "") : full
        }
        .alert(String(localized: "profile.edit.saveError", defaultValue: "保存エラー"), isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            if let saveError { Text(saveError) }
        }
    }

    private func save() {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        Task {
            let logger = Logger(subsystem: "com.protoductai.wizmark", category: "ProfileEdit")
            do {
                logger.info("Save started, updating Clerk")
                // The nickname is one display name, not a first/last pair.
                // Store it whole and clear lastName explicitly: splitting it and
                // passing nil for a missing surname left the previous surname in
                // place, which then reappeared appended to the new name.
                try await Clerk.shared.user?.update(.init(
                    firstName: trimmed,
                    lastName: ""
                ))
                logger.info("Clerk update finished")

                // Clerk owns the display name; Convex only mirrors it. The mirror
                // must never hold the save open: a stalled mutation used to leave
                // this screen frozen with the button disabled and no feedback,
                // which read as "saving does nothing".
                if let userService = services.user {
                    // Dispatched, not awaited. A Convex mutation that never
                    // returns would otherwise keep this screen open forever with
                    // the save button disabled.
                    Task {
                        try? await userService.updateProfile(displayName: trimmed)
                        logger.info("Convex mirror finished")
                    }
                    logger.info("Convex mirror dispatched")
                } else {
                    logger.info("Convex service unavailable, skipping mirror")
                }

                isSaving = false
                dismiss()
            } catch {
                logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func uploadAvatarToConvex(_ resolved: ResolvedHumation) {
        guard let manifest = HumationManifestStore.shared,
              let cg = HumationRenderer.render(resolved: resolved, manifest: manifest, pixels: 512),
              let jpegData = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { return }

        // The avatar is already stored locally by the caller. Mirroring it to
        // Convex is best-effort: without a running Convex service there is
        // nothing to upload to, and the local avatar still applies.
        guard let userService = services.user else { return }

        Task {
            do {
                let storageId = try await userService.uploadAvatar(imageData: jpegData)
                try await userService.updateProfile(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    avatarStorageId: ConvexId(storageId)
                )
            } catch {
                saveError = String(localized: "profile.edit.avatarUploadFailed", defaultValue: "アバターのアップロードに失敗しました")
            }
        }
    }

}

// MARK: - Avatar Editor

private struct AvatarEditorView: View {

    let currentSeed: String
    let currentData: String?
    let onSave: (ResolvedHumation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ResolvedHumation?
    @State private var slot: HumationSelectionSlot = .head

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        Group {
            if let manifest = HumationManifestStore.shared, let draft {
                editorContent(manifest: manifest, draft: draft)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "profile.avatarEditor.title", defaultValue: "アバター編集"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel", defaultValue: "キャンセル")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.save", defaultValue: "保存")) {
                    if let draft { onSave(draft) }
                    dismiss()
                }
                .bold()
            }
        }
        .onAppear {
            if draft == nil, let manifest = HumationManifestStore.shared {
                if let saved = StoredAvatar.decode(currentData) {
                    draft = saved
                } else {
                    draft = HumationTraits(seed: currentSeed).resolved(against: manifest)
                }
            }
        }
    }

    @ViewBuilder
    private func editorContent(manifest: HumationManifest, draft: ResolvedHumation) -> some View {
        VStack(spacing: 16) {
            HumationAvatarView(resolved: draft, size: 120)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.quaternary))

            Button {
                randomize(manifest: manifest)
            } label: {
                Label(String(localized: "profile.avatarEditor.random", defaultValue: "ランダム"), systemImage: "dice")
            }
            .buttonStyle(.bordered)

            Picker(String(localized: "profile.avatarEditor.parts", defaultValue: "パーツ"), selection: $slot) {
                ForEach(HumationSelectionSlot.allCases, id: \.self) { s in
                    Text(slotName(s)).tag(s)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(manifest.parts(in: slot), id: \.id) { part in
                        partCell(part: part, draft: draft, manifest: manifest)
                    }
                }

                colorRows(draft: draft)
                    .padding(.top, 16)
            }
        }
        .padding()
    }

    private func partCell(part: HumationManifest.Part, draft: ResolvedHumation, manifest: HumationManifest) -> some View {
        var variant = draft
        variant.selections[slot] = part.id
        variant.background = "transparent"
        let isSelected = draft.selections[slot] == part.id
        return Button {
            self.draft?.selections[slot] = part.id
        } label: {
            HumationAvatarView(resolved: variant, size: 88)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                                      lineWidth: isSelected ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func colorRows(draft: ResolvedHumation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(HumationColorSlot.allCases, id: \.self) { colorSlot in
                VStack(alignment: .leading, spacing: 6) {
                    Text(colorSlotName(colorSlot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.palette[colorSlot] ?? [], id: \.self) { hex in
                                colorDot(colorSlot: colorSlot, hex: hex, draft: draft)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func colorDot(colorSlot: HumationColorSlot, hex: String, draft: ResolvedHumation) -> some View {
        let current = colorSlot == .background ? draft.background : draft.colors[colorSlot]
        let isSelected = current?.caseInsensitiveCompare(hex) == .orderedSame
        return Circle()
            .fill(hexColor(hex))
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(.quaternary))
            .padding(4)
            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3))
            .onTapGesture {
                if colorSlot == .background {
                    self.draft?.background = HumationEngine.normalizeHex(hex)
                } else {
                    self.draft?.colors[colorSlot] = HumationEngine.normalizeHex(hex)
                }
            }
    }

    private func randomize(manifest: HumationManifest) {
        for s in HumationSelectionSlot.allCases {
            if let pick = manifest.parts(in: s).randomElement() {
                draft?.selections[s] = pick.id
            }
        }
    }

    private func slotName(_ slot: HumationSelectionSlot) -> String {
        switch slot {
        case .head: String(localized: "profile.avatarEditor.slot.head", defaultValue: "顔")
        case .body: String(localized: "profile.avatarEditor.slot.body", defaultValue: "体")
        case .bottom: String(localized: "profile.avatarEditor.slot.bottom", defaultValue: "下")
        case .item: String(localized: "profile.avatarEditor.slot.item", defaultValue: "小物")
        case .glasses: String(localized: "profile.avatarEditor.slot.glasses", defaultValue: "メガネ")
        }
    }

    private func colorSlotName(_ slot: HumationColorSlot) -> String {
        switch slot {
        case .background: String(localized: "profile.avatarEditor.color.background", defaultValue: "背景")
        case .stroke: String(localized: "profile.avatarEditor.color.stroke", defaultValue: "線")
        case .hair: String(localized: "profile.avatarEditor.color.hair", defaultValue: "髪")
        case .skin: String(localized: "profile.avatarEditor.color.skin", defaultValue: "肌")
        case .clothes: String(localized: "profile.avatarEditor.color.clothes", defaultValue: "服")
        case .bottom: String(localized: "profile.avatarEditor.color.bottom", defaultValue: "ボトムス")
        }
    }

    private func hexColor(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    private static let palette: [HumationColorSlot: [String]] = [
        .background: ["F6F5F4", "FFFFFF", "FFE5EC", "E6F4EA", "E3F2FD", "EDE7F6", "FFF3E0", "263238"],
        .stroke: ["000000", "3A2E2E", "2B2D42", "4A4A4A"],
        .hair: ["000000", "3A2E2E", "5B3A1E", "8B4513", "C8843C", "D4A017", "BFBFBF", "B23A48", "E91E63", "4CAF50"],
        .skin: ["FFFFFF", "FFDCB8", "F1C27D", "E0AC69", "C68642", "8D5524", "5C3A21"],
        .clothes: ["FFFFFF", "2A2A2A", "E63946", "F4A261", "2A9D8F", "457B9D", "6A4C93", "FF6B6B", "4ECDC4"],
        .bottom: ["000000", "2B2D42", "3A5F8A", "556B2F", "8B0000", "1A237E", "4A148C"],
    ]
}
