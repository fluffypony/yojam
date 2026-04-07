import Foundation

/// Normalizes incoming file URLs and remote URLs into routable targets.
/// Handles `.webloc`, `.inetloc`, and `.url` internet-location files
/// (e.g. from AirDrop), local HTML files from Finder, and pass-through
/// for remote http/https/mailto URLs.
public enum IncomingLinkExtractor {
    /// Maximum size for an internet-location file. Guards against pathological
    /// inputs dropped via AirDrop.
    private static let maxFileSize: Int = 64 * 1024

    /// Normalizes an incoming URL to a routable target.
    /// Returns `nil` if the URL cannot be routed (e.g. arbitrary local files).
    public static func normalize(_ incoming: URL) -> URL? {
        // Pass-through for remote URLs.
        if let scheme = incoming.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            return incoming
        }
        guard incoming.isFileURL else { return incoming }
        let ext = incoming.pathExtension.lowercased()

        // Allowlist of local file extensions we will route.
        switch ext {
        case "html", "xhtml", "htm":
            return incoming  // keep current behavior: open local HTML
        case "webloc", "inetloc":
            return parseInternetLocation(incoming)
        case "url":
            return parseWindowsURLShortcut(incoming)
        default:
            return nil  // fail-fast: do not route arbitrary local files
        }
    }

    private static func parseInternetLocation(_ fileURL: URL) -> URL? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs?[.size] as? Int, size > maxFileSize { return nil }
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String,
              let parsed = URL(string: urlString),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        return parsed
    }

    private static func parseWindowsURLShortcut(_ fileURL: URL) -> URL? {
        // INI format: look for `URL=…` line.
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("URL=") {
                let raw = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = URL(string: raw),
                   let scheme = parsed.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    return parsed
                }
            }
        }
        return nil
    }
}
