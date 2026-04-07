import Foundation

enum URLSanitizer {
    static func sanitize(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard url.absoluteString.count <= 32_768 else { return nil }
        switch scheme {
        case "http", "https", "mailto":
            return url
        case "file":
            // Local files opened from Finder (e.g. .html, .xhtml).
            // Require an actual file URL with a non-empty path so a malformed
            // string can't sneak through as `file:` with no target.
            guard url.isFileURL, !url.path.isEmpty else { return nil }
            return url
        default:
            return nil
        }
    }
}
