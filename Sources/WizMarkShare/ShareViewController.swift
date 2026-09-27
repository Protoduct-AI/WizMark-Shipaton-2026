import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        extractURL { [weak self] url in
            DispatchQueue.main.async {
                if let url {
                    self?.showShareUI(url: url)
                } else {
                    self?.close()
                }
            }
        }
    }

    private func extractURL(completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completion(nil)
            return
        }

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                    completion((data as? URL)?.absoluteString)
                }
                return
            }
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                    if let text = data as? String, text.hasPrefix("http") {
                        completion(text)
                    } else {
                        completion(nil)
                    }
                }
                return
            }
        }
        completion(nil)
    }

    private func showShareUI(url: String) {
        let schema = Schema([Bookmark.self, BookmarkCollection.self])
        let config = ModelConfiguration(
            "WizMark",
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            close()
            return
        }

        let shareView = ShareSheetView(
            sharedURL: url,
            onDismiss: { [weak self] in self?.close() }
        )

        let host = UIHostingController(rootView: shareView.modelContainer(container))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
