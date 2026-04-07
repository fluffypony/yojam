import Foundation

/// Parses and builds `yojam://` URLs.
///
/// Supported grammar:
/// ```
/// yojam://route?url=<percent-encoded>&source=<bundle-id>&browser=<bundle-id>&pick=1&private=1
/// yojam://open?url=<percent-encoded>           // alias for route
/// yojam://settings                             // open Preferences window
/// ```
private extension CharacterSet {
    /// URL query value safe characters — like .urlQueryAllowed but also encodes `+`
    /// so it doesn't round-trip to space.
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove("+")
        cs.remove("&")
        cs.remove("=")
        return cs
    }()
}

public enum YojamCommand: Sendable {
    case route(IncomingLinkRequest)
    case openSettings

    /// Parse a `yojam://` URL into a command.
    /// Returns `nil` for malformed or unrecognized commands.
    public static func parse(_ url: URL) -> YojamCommand? {
        guard url.scheme?.lowercased() == "yojam" else { return nil }
        let host = url.host?.lowercased() ?? ""

        switch host {
        case "settings":
            return .openSettings

        case "route", "open":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems,
                  let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
                  let targetURL = URL(string: urlParam)
            else { return nil }

            // Reject recursive yojam:// URLs.
            guard targetURL.scheme?.lowercased() != "yojam" else { return nil }

            // Only route http, https, mailto.
            guard let scheme = targetURL.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme)
            else { return nil }

            let rawSource = queryItems.first(where: { $0.name == "source" })?.value
            // Only trusted sentinels pass through; untrusted input falls back
            // to .urlScheme to prevent source spoofing from external callers.
            let source: String
            if let rawSource, SourceAppSentinel.all.contains(rawSource) {
                source = rawSource
            } else {
                source = SourceAppSentinel.urlScheme
            }
            let browser = queryItems.first(where: { $0.name == "browser" })?.value
            let pick = queryItems.first(where: { $0.name == "pick" })?.value == "1"
            let priv = queryItems.first(where: { $0.name == "private" })?.value == "1"

            let request = IncomingLinkRequest(
                url: targetURL,
                sourceAppBundleId: source,
                origin: .urlScheme,
                forcedBrowserBundleId: browser,
                forcePicker: pick,
                forcePrivateWindow: priv
            )
            return .route(request)

        default:
            return nil
        }
    }

    /// Build a `yojam://route?...` URL for forwarding a link to the main app.
    /// Used by the Share Extension, browser extensions, and automation.
    public static func buildRoute(
        target: URL,
        source: String? = nil,
        browser: String? = nil,
        pick: Bool = false,
        privateWindow: Bool = false
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "yojam"
        components.host = "route"
        // R6: URLQueryItem doesn't encode `+` as `%2B`, which round-trips to space.
        // Use stricter percent-encoding for the URL value.
        let encodedTarget = target.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed)
            ?? target.absoluteString
        var items: [URLQueryItem] = [
            URLQueryItem(name: "url", value: encodedTarget)
        ]
        if let source { items.append(URLQueryItem(name: "source", value: source)) }
        if let browser { items.append(URLQueryItem(name: "browser", value: browser)) }
        if pick { items.append(URLQueryItem(name: "pick", value: "1")) }
        if privateWindow { items.append(URLQueryItem(name: "private", value: "1")) }
        components.queryItems = items
        return components.url
    }
}
