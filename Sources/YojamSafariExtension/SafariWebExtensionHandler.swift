import AppKit
import SafariServices
import YojamCore

/// Handles messages from the Yojam Safari Web Extension's background script.
/// Supports `route` (forward to main app) and `preview` (return routing decision).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        guard let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let action = message["action"] as? String
        else {
            sendError(context, message: "Invalid message")
            return
        }

        switch action {
        case "route":
            handleRoute(message: message, context: context)
        case "preview":
            handlePreview(message: message, context: context)
        default:
            sendError(context, message: "Unknown action: \(action)")
        }
    }

    private func handleRoute(message: [String: Any], context: NSExtensionContext) {
        guard let urlString = message["url"] as? String,
              let targetURL = URL(string: urlString)
        else {
            sendError(context, message: "Invalid URL")
            return
        }

        // Always use Safari sentinel — shared background.js sends Chrome sentinel.
        let source = SourceAppSentinel.safariExtension

        guard let yojamURL = YojamCommand.buildRoute(target: targetURL, source: source) else {
            sendError(context, message: "Failed to build route")
            return
        }

        // Use context.open instead of NSWorkspace — sandboxed extension.
        // NSExtensionContext isn't Sendable but open's completion is @Sendable in
        // macOS 26 SDK; this completion is dispatched on the main thread at runtime.
        nonisolated(unsafe) let ctx = context
        context.open(yojamURL) { success in
            let response = NSExtensionItem()
            if success {
                response.userInfo = [SFExtensionMessageKey: ["status": "ok"]]
            } else {
                response.userInfo = [SFExtensionMessageKey: ["status": "error", "message": "Failed to open URL"]]
            }
            ctx.completeRequest(returningItems: [response])
        }
    }

    private func handlePreview(message: [String: Any], context: NSExtensionContext) {
        guard let urlString = message["url"] as? String,
              let targetURL = URL(string: urlString),
              let scheme = targetURL.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else {
            sendError(context, message: "Invalid URL")
            return
        }

        let store = SharedRoutingStore()
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: store) else {
            sendError(context, message: "Cannot load config")
            return
        }

        let request = IncomingLinkRequest(
            url: targetURL,
            sourceAppBundleId: SourceAppSentinel.safariExtension,
            origin: .safariExtension
        )
        let decision = RoutingService.decide(request: request, configuration: config)
        let preview = RouteDecisionPreview.from(decision)

        let encoder = JSONEncoder()
        if let previewData = try? encoder.encode(preview),
           let previewDict = try? JSONSerialization.jsonObject(with: previewData) as? [String: Any] {
            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: [
                "status": "ok",
                "preview": previewDict
            ]]
            context.completeRequest(returningItems: [response])
        } else {
            sendError(context, message: "Failed to encode preview")
        }
    }

    private func sendError(_ context: NSExtensionContext, message: String) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["status": "error", "message": message]]
        context.completeRequest(returningItems: [response])
    }
}
