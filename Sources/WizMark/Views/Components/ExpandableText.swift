import SwiftUI

struct ExpandableText: View {

    let text: String
    var lineLimit: Int = 3

    @State private var isExpanded = false

    private var shouldTruncate: Bool {
        text.count > 100 || text.filter({ $0 == "\n" }).count >= lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : lineLimit)

            if shouldTruncate {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? String(localized: "expandableText.collapse", defaultValue: "折りたたむ") : String(localized: "expandableText.showMore", defaultValue: "もっと見る"))
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
