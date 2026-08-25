import Foundation

public enum URLRewriteEngine {
    public static func apply(_ rules: [URLRewriteRule], to url: URL) -> URL {
        var urlString = url.absoluteString
        for rule in rules where rule.enabled {
            let input = rule.urlNormalization.normalize(urlString)
            let output: String
            if rule.isRegex {
                output = RegexMatcher.replaceMatches(
                    in: input,
                    pattern: rule.matchPattern,
                    replacement: rule.replacement
                )
            } else {
                output = input.replacingOccurrences(
                    of: rule.matchPattern,
                    with: rule.replacement
                )
            }
            urlString = rule.urlNormalization.normalize(output)
        }
        return URL(string: urlString) ?? url
    }
}
