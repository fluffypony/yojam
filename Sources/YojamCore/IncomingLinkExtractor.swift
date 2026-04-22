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
        // Reject non-file, non-routable remote URLs (e.g. ftp://, data://)
        guard incoming.isFileURL else { return nil }
        let ext = incoming.pathExtension.lowercased()

        // Allowlist of local file extensions we will route. Yojam registers
        // itself as the default handler for public.html / public.xhtml, so
        // these file URLs reach us and must be passed through to a browser;
        // otherwise double-clicking a local HTML file is silently dropped.
        switch ext {
        case "html", "xhtml", "htm":
            return incoming
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
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Post-read size guard in case attributesOfItem failed (permission denied)
        guard data.count <= maxFileSize else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let urlString = plist["URL"] as? String,
              let parsed = URL(string: urlString),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        return parsed
    }

    private static func parseWindowsURLShortcut(_ fileURL: URL) -> URL? {
        // Size guard: same limit as internet-location files
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attrs?[.size] as? Int, size > maxFileSize { return nil }
        // Try multiple encodings: Windows .url files are typically Windows-1252 or UTF-8
        let contents: String
        if let utf8 = try? String(contentsOf: fileURL, encoding: .utf8) {
            contents = utf8
        } else if let latin1 = try? String(contentsOf: fileURL, encoding: .windowsCP1252) {
            contents = latin1
        } else if let utf16 = try? String(contentsOf: fileURL, encoding: .utf16) {
            contents = utf16
        } else {
            return nil
        }
        guard contents.count <= maxFileSize else { return nil }
        // INI format: look for `URL=…` line, strip `;` comments
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(";") { continue }
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
