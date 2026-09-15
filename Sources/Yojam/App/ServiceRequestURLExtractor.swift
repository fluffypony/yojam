import AppKit

/// Reads the link destination when a browser supplies its title as plain text
/// and its hyperlink as RTF through the Services menu.
enum ServiceRequestURLExtractor {
    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        let objects = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if !objects.isEmpty { return objects }

        if let items = pasteboard.pasteboardItems, !items.isEmpty {
            return items.flatMap { urls(rtf: $0.data(forType: .rtf), text: $0.string(forType: .string)) }
        }
        return urls(rtf: pasteboard.data(forType: .rtf), text: pasteboard.string(forType: .string))
    }

    private static func urls(rtf: Data?, text: String?) -> [URL] {
        guard let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return urls(in: text)
        }

        var result: [URL] = []
        attributed.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed.length)) {
            link, range, _ in
            if let url = link as? URL {
                result.append(url)
            } else if let link = link as? String, let url = URL(string: link) {
                result.append(url)
            } else {
                result.append(contentsOf: urls(in: attributed.attributedSubstring(from: range).string))
            }
        }
        return result
    }

    /// Detects links in selected text, including bare hosts such as `example.com`.
    static func urls(in text: String?) -> [URL] {
        guard let text else { return [] }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let detected = detector?.matches(in: text, range: range).compactMap(\.url) ?? []
        if !detected.isEmpty { return detected }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("."), !trimmed.contains(" "), !trimmed.contains("://"),
              let url = URL(string: "https://" + trimmed) else { return [] }
        return [url]
    }
}
