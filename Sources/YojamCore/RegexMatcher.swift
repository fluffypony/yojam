import Foundation
import os

/// Cached regex matching for rule evaluation and URL rewriting.
/// Extension-safe: no AppKit dependencies.
public enum RegexMatcher: Sendable {
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSRegularExpression> = {
        let c = NSCache<NSString, NSRegularExpression>()
        c.countLimit = 256
        return c
    }()

    private static let logger = os.Logger(subsystem: "com.yojam.core", category: "regex")

    private static func cachedRegex(pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return nil }
        cache.setObject(regex, forKey: key)
        return regex
    }

    public static func matches(_ input: String, pattern: String) -> Bool {
        guard input.count < 8192 else { return false }
        guard let regex = cachedRegex(pattern: pattern) else {
            logger.warning("Invalid regex: \(pattern)")
            return false
        }
        return regex.firstMatch(
            in: input, range: NSRange(input.startIndex..., in: input)
        ) != nil
    }

    public static func isValid(pattern: String) -> Bool {
        cachedRegex(pattern: pattern) != nil
    }

    public static func replaceMatches(in input: String, pattern: String, replacement: String) -> String {
        guard input.count < 8192 else { return input }
        guard let regex = cachedRegex(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}
