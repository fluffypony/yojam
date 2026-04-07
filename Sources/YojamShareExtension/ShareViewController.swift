import AppKit
import UniformTypeIdentifiers
import YojamCore

/// A thin, silent Share Extension that forwards a shared URL to the main
/// Yojam app via the `yojam://route?url=...` scheme. No routing logic
/// lives here — the main app is the single place where decisions happen.
@MainActor
final class ShareViewController: NSViewController {
    override func loadView() { view = NSView(frame: .zero) }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(); return
        }
        extractFirstURL(from: items) { [weak self] url in
            guard let self, let url else { self?.finish(); return }
            self.forwardToYojam(url)
        }
    }

    private func extractFirstURL(
        from items: [NSExtensionItem],
        completion: @escaping @Sendable (URL?) -> Void
    ) {
        let providers = items.flatMap { $0.attachments ?? [] }
        // 1. Prefer explicit URL attachments.
        if let p = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            p.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                DispatchQueue.main.async {
                    if let u = item as? URL { completion(u) }
                    else if let s = item as? String { completion(URL(string: s)) }
                    else { completion(nil) }
                }
            }
            return
        }
        // 2. Fall back to plain text and run NSDataDetector.
        if let p = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            p.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                DispatchQueue.main.async {
                    guard let text = item as? String else { completion(nil); return }
                    let detector = try? NSDataDetector(
                        types: NSTextCheckingResult.CheckingType.link.rawValue)
                    let match = detector?.firstMatch(
                        in: text, range: NSRange(text.startIndex..., in: text))
                    completion(match?.url)
                }
            }
            return
        }
        completion(nil)
    }

    private func forwardToYojam(_ url: URL) {
        guard let yojamURL = YojamCommand.buildRoute(
            target: url,
            source: SourceAppSentinel.shareExtension
        ) else { finish(); return }
        // extensionContext.open(_:) is the supported path from an extension sandbox.
        extensionContext?.open(yojamURL) { [weak self] _ in self?.finish() }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(
                returningItems: nil, completionHandler: nil)
        }
    }
}
