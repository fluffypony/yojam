import Foundation

enum URLSanitizer {
    static func sanitize(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        guard url.absoluteString.count <= 32_768 else { return nil }
        return url
    }
}
