import SwiftUI

struct BrandIcon: View {
    let brand: Brand
    var size: CGFloat = 24

    enum Brand: String, Hashable {
        case instagram, x, tiktok, youtube
    }

    var body: some View {
        switch brand {
        case .instagram: instagramIcon
        case .x: xIcon
        case .tiktok: tiktokIcon
        case .youtube: youtubeIcon
        }
    }

    private var instagramIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.51, green: 0.23, blue: 0.71),
                            Color(red: 0.83, green: 0.18, blue: 0.42),
                            Color(red: 0.99, green: 0.44, blue: 0.15),
                            Color(red: 1.0, green: 0.73, blue: 0.19),
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )

            Circle()
                .strokeBorder(.white, lineWidth: size * 0.08)
                .frame(width: size * 0.46, height: size * 0.46)

            Circle()
                .fill(.white)
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.17, y: -size * 0.17)
        }
        .frame(width: size, height: size)
    }

    private var xIcon: some View {
        ZStack {
            Circle()
                .fill(.black)

            Text("𝕏")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var tiktokIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(.black)

            Image(systemName: "music.note")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.02, y: size * 0.02)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(Color(red: 0.0, green: 0.96, blue: 0.88))
                        .offset(x: -size * 0.03, y: -size * 0.02)
                        .blendMode(.screen)
                }
        }
        .frame(width: size, height: size)
    }

    private var youtubeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color(red: 1.0, green: 0.0, blue: 0.0))

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.35))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
