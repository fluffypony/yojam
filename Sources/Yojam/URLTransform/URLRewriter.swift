import Foundation

@MainActor
final class URLRewriter: ObservableObject {
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) { self.settingsStore = settingsStore }

    func applyGlobalRewrites(to url: URL) -> URL {
        let rules = settingsStore.loadGlobalRewriteRules().filter {
            $0.enabled && $0.scope == .global
        }
        return applyRewrites(rules, to: url)
    }

    func applyBrowserRewrites(to url: URL, browser: BrowserEntry) -> URL {
        applyRewrites(browser.rewriteRules.filter(\.enabled), to: url)
    }

    func applyRuleRewrites(to url: URL, rule: Rule) -> URL {
        applyRewrites(rule.rewriteRules.filter(\.enabled), to: url)
    }

    func testRewrite(_ url: URL, with rule: URLRewriteRule) -> URL {
        applyRewrites([rule], to: url)
    }

    private func applyRewrites(_ rules: [URLRewriteRule], to url: URL) -> URL {
        var urlString = url.absoluteString
        for rule in rules where rule.enabled {
            if rule.isRegex {
                urlString = RegexMatcher.replaceMatches(
                    in: urlString, pattern: rule.matchPattern,
                    replacement: rule.replacement
                )
            } else {
                urlString = urlString.replacingOccurrences(
                    of: rule.matchPattern, with: rule.replacement
                )
            }
        }
        return URL(string: urlString) ?? url
    }
}
