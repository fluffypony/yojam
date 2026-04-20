import Foundation

/// Canonical URL-to-rule matcher. All callers (RoutingService, RuleEngine,
/// Preferences URL Tester, decision previews) must go through this type so
/// semantics never drift between the real routing pipeline and diagnostic
/// surfaces.
public enum RuleMatcher {

    /// Evaluate a `Rule` against a URL with an optional source-app context.
    /// Returns a structured result that describes both whether the rule matched
    /// and why.
    public static func evaluate(url: URL, against rule: Rule, sourceApp: String? = nil) -> RuleMatchResult {
        let urlString = url.absoluteString
        let normalizedURL = normalizeURL(urlString)

        // Source-app filter. Must match exactly when set.
        if let requiredSource = rule.sourceAppBundleId, sourceApp != requiredSource {
            return RuleMatchResult(
                matched: false,
                matcherFired: nil,
                normalizedURL: normalizedURL,
                explanation: "Source-app filter requires \(requiredSource); got \(sourceApp ?? "<none>")."
            )
        }

        let host = url.host?.lowercased() ?? ""
        let pattern = rule.pattern
        let patternLower = pattern.lowercased()

        switch rule.matchType {
        case .domain:
            let matched = host == patternLower
            let explanation = matched
                ? "Host \"\(host)\" equals \"\(patternLower)\"."
                : "Host \"\(host)\" does not equal \"\(patternLower)\"."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .domain : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)

        case .domainSuffix:
            let matched = host == patternLower || host.hasSuffix(".\(patternLower)")
            let explanation = matched
                ? "Host \"\(host)\" matches suffix \"\(patternLower)\"."
                : "Host \"\(host)\" does not end with \".\(patternLower)\"."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .domainSuffix : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)

        case .urlPrefix:
            let normalizedPattern = stripScheme(patternLower)
            let trimmedPattern = normalizedPattern.hasSuffix("/")
                ? String(normalizedPattern.dropLast()) : normalizedPattern
            let matched = normalizedURL.hasPrefix(trimmedPattern)
            let explanation = matched
                ? "Normalized URL starts with \"\(trimmedPattern)\"."
                : "Normalized URL \"\(normalizedURL)\" does not start with \"\(trimmedPattern)\"."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .urlPrefix : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)

        case .urlContains:
            let matched = urlString.lowercased().contains(patternLower)
            let explanation = matched
                ? "URL contains \"\(patternLower)\"."
                : "URL does not contain \"\(patternLower)\"."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .urlContains : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)

        case .hostPathPrefix:
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = components?.path ?? ""
            let hostPath = (host + path).lowercased()
            let trimmedHostPath = hostPath.hasSuffix("/") ? String(hostPath.dropLast()) : hostPath
            let normalizedPattern = stripScheme(patternLower)
            let trimmedPattern = normalizedPattern.hasSuffix("/")
                ? String(normalizedPattern.dropLast()) : normalizedPattern
            let matched = trimmedHostPath.hasPrefix(trimmedPattern)
            let explanation = matched
                ? "Host+path \"\(trimmedHostPath)\" starts with \"\(trimmedPattern)\"."
                : "Host+path \"\(trimmedHostPath)\" does not start with \"\(trimmedPattern)\"."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .hostPathPrefix : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)

        case .regex:
            let matched = RegexMatcher.matches(urlString, pattern: pattern)
            let explanation = matched
                ? "Regex \"\(pattern)\" matched."
                : "Regex \"\(pattern)\" did not match."
            return RuleMatchResult(matched: matched, matcherFired: matched ? .regex : nil,
                                   normalizedURL: normalizedURL, explanation: explanation)
        }
    }

    /// Convenience used by the URL Tester — evaluates against every rule in
    /// order and returns the first match, or the last non-match for feedback.
    public static func firstMatch(url: URL, rules: [Rule], sourceApp: String? = nil) -> (rule: Rule, result: RuleMatchResult)? {
        for rule in rules {
            let result = evaluate(url: url, against: rule, sourceApp: sourceApp)
            if result.matched { return (rule, result) }
        }
        return nil
    }

    // MARK: - Normalization helpers

    /// Normalizes a URL string by stripping scheme for display/prefix matching.
    /// Preserves path case; only the scheme and host are lowercased.
    public static func normalizeURL(_ urlString: String) -> String {
        var s = urlString
        if s.lowercased().hasPrefix("https://") { s = String(s.dropFirst(8)) }
        else if s.lowercased().hasPrefix("http://") { s = String(s.dropFirst(7)) }
        // Lowercase the host portion (everything before the first slash or end).
        if let slashIdx = s.firstIndex(of: "/") {
            let hostPart = s[..<slashIdx].lowercased()
            let rest = s[slashIdx...]
            s = hostPart + rest
        } else {
            s = s.lowercased()
        }
        return s
    }

    private static func stripScheme(_ pattern: String) -> String {
        if pattern.hasPrefix("https://") { return String(pattern.dropFirst(8)) }
        if pattern.hasPrefix("http://") { return String(pattern.dropFirst(7)) }
        return pattern
    }
}
