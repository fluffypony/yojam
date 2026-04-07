import AppKit
import SafariServices
import YojamCore

/// Handles messages from the Yojam Safari Web Extension's background script.
/// Receives a URL from the extension, builds a `yojam://route?...` URL,
/// and opens it to forward to the main app.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        guard let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let urlString = message["url"] as? String,
              let targetURL = URL(string: urlString)
        else {
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: ["status": "error", "message": "Invalid URL"]]
            context.completeRequest(returningItems: [response])
            return
        }

        let source = (message["source"] as? String) ?? SourceAppSentinel.safariExtension

        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL,
            source: source
        ) else {
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: ["status": "error", "message": "Failed to build route"]]
            context.completeRequest(returningItems: [response])
            return
        }

        NSWorkspace.shared.open(yojamURL)

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
        context.completeRequest(returningItems: [response])
    }
}
