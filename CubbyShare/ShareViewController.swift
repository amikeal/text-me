import UIKit
import UniformTypeIdentifiers
import CubbyCore

/// The share sheet target. It does one thing: write what was shared into the shared inbox and
/// get out of the way. The app sorts it the next time it opens.
///
/// It never touches the database or the language model: extensions have tight memory limits,
/// and two processes writing one synced store is a recipe for conflicts.
final class ShareViewController: UIViewController {
    private let confirmation = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        confirmation.text = "Saved to Cubby"
        confirmation.font = .preferredFont(forTextStyle: .headline)
        confirmation.adjustsFontForContentSizeCategory = true
        confirmation.textColor = .label
        confirmation.textAlignment = .center
        confirmation.backgroundColor = .secondarySystemBackground
        confirmation.layer.cornerRadius = 18
        confirmation.layer.masksToBounds = true
        confirmation.alpha = 0
        confirmation.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(confirmation)
        NSLayoutConstraint.activate([
            confirmation.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            confirmation.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            confirmation.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            confirmation.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor in
            let text = await sharedText()
            let saved = save(text)
            confirmation.text = saved ? "Saved to Cubby" : "Couldn't save to Cubby"
            UIView.animate(withDuration: 0.2) { self.confirmation.alpha = 1 }
            try? await Task.sleep(for: .milliseconds(saved ? 700 : 1500))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Everything shared, as text: selected text first, then any links, without repeats.
    private func sharedText() async -> String {
        var texts: [String] = []
        var links: [String] = []

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                       !url.isFileURL {
                        links.append(url.absoluteString)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        texts.append(text)
                    }
                }
            }
        }

        var parts: [String] = []
        for part in texts + links {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            // Safari shares the address both as text and as a link; keep one.
            if !trimmed.isEmpty, !parts.contains(where: { $0.contains(trimmed) }) {
                parts.append(trimmed)
            }
        }
        return parts.joined(separator: "\n")
    }

    private func save(_ text: String) -> Bool {
        guard !text.isEmpty, let queue = InboxQueue.shared else { return false }
        do {
            try queue.enqueue(PendingCapture(text: text, source: "shareExtension"))
            return true
        } catch {
            return false
        }
    }
}
