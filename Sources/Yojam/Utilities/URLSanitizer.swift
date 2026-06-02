import Foundation

enum URLSanitizer {
    /// Validates a URL for routing. Only accepts http, https, mailto, and tel schemes.
    /// File URLs are handled upstream by IncomingLinkExtractor before reaching
    /// the routing pipeline, so they are no longer accepted here.
    static func sanitize(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard url.absoluteString.count <= 32_768 else { return nil }
        switch scheme {
        case "http", "https", "mailto", "tel":
            return url
        default:
            return nil
        }
    }
}
