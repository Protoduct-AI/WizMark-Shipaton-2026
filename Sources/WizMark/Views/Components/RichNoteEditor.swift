import SwiftUI
import RichTextKit

struct RichNoteEditor: View {
    @Binding var text: String?
    var richData: Binding<Data?>?
    var onSave: (() -> Void)?

    @State private var isEditing = false
    @StateObject private var context = RichTextContext()
    @State private var attributedText = NSAttributedString()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(String(localized: "richNoteEditor.header", defaultValue: "メモ"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isEditing {
                    Button(String(localized: "richNoteEditor.done", defaultValue: "完了")) {
                        save()
                        isEditing = false
                    }
                    .font(.subheadline.bold())
                }
            }

            if isEditing {
                RichTextEditor(text: $attributedText, context: context)
                    .foregroundColor(.white)
                    .frame(minHeight: 150)
                    .clipShape(.rect(cornerRadius: 10))
            } else {
                Button { loadAndEdit() } label: {
                    if attributedText.length > 0 {
                        Text(AttributedString(fixColors(attributedText)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle").font(.system(size: 14))
                            Text(String(localized: "richNoteEditor.placeholder", defaultValue: "タップしてメモを追加...")).font(.subheadline)
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { loadFromStorage() }
    }

    private func fixColors(_ attr: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: attr)
        m.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: m.length)) { val, range, _ in
            if let color = val as? UIColor {
                let (r, g, b, _) = color.rgbaComponents
                if r < 0.15 && g < 0.15 && b < 0.15 {
                    m.addAttribute(.foregroundColor, value: UIColor.label, range: range)
                }
            } else {
                m.addAttribute(.foregroundColor, value: UIColor.label, range: range)
            }
        }
        return m
    }

    private func loadFromStorage() {
        if let data = richData?.wrappedValue,
           let attr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil
           ) {
            attributedText = fixColors(attr)
        } else if let plain = text, !plain.isEmpty {
            attributedText = NSAttributedString(
                string: plain,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline),
                    .foregroundColor: UIColor.label
                ]
            )
        }
    }

    private func loadAndEdit() {
        loadFromStorage()
        isEditing = true
    }

    private func save() {
        if let data = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ) {
            richData?.wrappedValue = data
        }
        text = attributedText.string.isEmpty ? nil : attributedText.string
        onSave?()
    }
}

private extension UIColor {
    var rgbaComponents: (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
