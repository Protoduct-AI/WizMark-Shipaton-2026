import ClerkKit
import Humation
import SwiftUI

// MARK: - Stored Avatar

/// The avatar the user assembled in the editor, as persisted in `avatar_data`.
///
/// The Humation seeded by the Clerk user id is only a starting point. Rendering
/// that seed on its own silently ignores every edit the user made, which is how
/// the home toolbar and the collection owner row ended up showing a different
/// face from the profile screen. Decoding lives here so there is one copy of it.
struct StoredAvatar: Codable {

    let selections: [String: String]
    let colors: [String: String]
    let background: String

    init(from resolved: ResolvedHumation) {
        self.selections = Dictionary(
            uniqueKeysWithValues: resolved.selections.map { ($0.key.rawValue, $0.value) })
        self.colors = Dictionary(
            uniqueKeysWithValues: resolved.colors.map { ($0.key.rawValue, $0.value) })
        self.background = resolved.background
    }

    func toResolved() -> ResolvedHumation {
        ResolvedHumation(
            selections: Dictionary(uniqueKeysWithValues: selections.compactMap { k, v in
                HumationSelectionSlot(rawValue: k).map { ($0, v) }
            }),
            colors: Dictionary(uniqueKeysWithValues: colors.compactMap { k, v in
                HumationColorSlot(rawValue: k).map { ($0, v) }
            }),
            background: background
        )
    }

    /// Encodes an avatar for `avatar_data`.
    static func encode(_ resolved: ResolvedHumation) -> String? {
        guard let data = try? JSONEncoder().encode(StoredAvatar(from: resolved)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes `avatar_data`, returning nil when nothing has been saved yet.
    static func decode(_ json: String?) -> ResolvedHumation? {
        guard let json,
              let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(StoredAvatar.self, from: data)
        else { return nil }
        return stored.toResolved()
    }

    /// The saved avatar, falling back to the Humation seeded by `seed`.
    static func image(json: String?, seed: String?, pixels: Int) -> UIImage? {
        if let resolved = decode(json),
           let manifest = HumationManifestStore.shared,
           let cg = HumationRenderer.render(resolved: resolved, manifest: manifest, pixels: pixels) {
            return UIImage(cgImage: cg)
        }
        guard let seed else { return nil }
        return Humation.image(seed: seed, pixels: pixels)
    }
}

// MARK: - User Avatar View

/// The signed-in user's avatar. Callers size and clip it themselves, the same
/// way they would an `Image`, so it drops into an existing row unchanged.
struct UserAvatarView: View {

    /// Render size in pixels. Pass roughly twice the on-screen point size.
    var pixels: Int = 96
    /// Shown when there is no avatar to draw at all — typically the first
    /// letter of the display name.
    var fallbackInitial: String?

    @AppStorage("avatar_data") private var avatarData: String?

    var body: some View {
        Group {
            if let image = StoredAvatar.image(
                json: avatarData, seed: Clerk.shared.user?.id, pixels: pixels) {
                Image(uiImage: image)
                    .resizable()
            } else if let fallbackInitial, !fallbackInitial.isEmpty {
                ZStack {
                    Color(.tertiarySystemFill)
                    Text(fallbackInitial.uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
