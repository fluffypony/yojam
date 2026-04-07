import Foundation
import Combine
import YojamCore

@MainActor
final class URLRewriter: ObservableObject {
    private let settingsStore: SettingsStore
    // §30: Cache global rewrite rules to avoid JSON deserialization on every URL
    private var cachedGlobalRules: [URLRewriteRule]?
    private var cancellable: AnyCancellable?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.cancellable = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.cachedGlobalRules = nil
        }
    }

    func applyGlobalRewrites(to url: URL) -> URL {
        let rules: [URLRewriteRule]
        if let cached = cachedGlobalRules {
            rules = cached
        } else {
            let loaded = settingsStore.loadGlobalRewriteRules().filter {
                $0.enabled && $0.scope == .global
            }
            cachedGlobalRules = loaded
            rules = loaded
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
