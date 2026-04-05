import Foundation

enum RegexMatcher {
    private static let cache = NSCache<NSString, NSRegularExpression>()

    private static func cachedRegex(pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return nil }
        cache.setObject(regex, forKey: key)
        return regex
    }

    static func matches(_ input: String, pattern: String) -> Bool {
        guard input.count < 8192 else { return false }
        guard let regex = cachedRegex(pattern: pattern) else {
            YojamLogger.shared.log("Invalid regex: \(pattern)")
            return false
        }
        return regex.firstMatch(
            in: input, range: NSRange(input.startIndex..., in: input)
        ) != nil
    }

    static func isValid(pattern: String) -> Bool {
        cachedRegex(pattern: pattern) != nil
    }

    static func replaceMatches(in input: String, pattern: String, replacement: String) -> String {
        guard input.count < 8192 else { return input }
        guard let regex = cachedRegex(pattern: pattern) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}
