import Foundation

enum RegexMatcher {
    static func matches(_ input: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else {
            YojamLogger.shared.log("Invalid regex: \(pattern)")
            return false
        }
        return regex.firstMatch(
            in: input, range: NSRange(input.startIndex..., in: input)
        ) != nil
    }

    static func isValid(pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    static func replaceMatches(in input: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: replacement
        )
    }
}
