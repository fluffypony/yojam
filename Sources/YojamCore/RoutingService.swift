import CryptoKit
import Foundation

/// Pure decision engine for URL routing. Zero AppKit dependencies.
/// Compiles with APPLICATION_EXTENSION_API_ONLY = YES.
///
/// Input: `IncomingLinkRequest` + `RoutingConfiguration`.
/// Output: `RouteDecision`.
///
/// The caller (AppDelegate) builds the configuration snapshot from its
/// live subsystems, calls `decide()`, then executes the returned decision
/// via app-only executors (picker panel, browser launcher, etc.).
public enum RoutingService {

    // MARK: - Public API

    public static func decide(
        request: IncomingLinkRequest,
        configuration: RoutingConfiguration
    ) -> RouteDecision {
        // Sanitize URL.
        guard let url = sanitize(request.url) else {
            return .openSystemDefault(request.url)
        }

        // If routing is disabled, pass through to system.
        guard configuration.isEnabled else {
            if url.scheme?.lowercased() == "mailto" {
                return .openSystemMailHandler(url)
            }
            return .openSystemDefault(url)
        }

        var processedURL = url

        // Global rewrites.
        processedURL = applyRewrites(configuration.globalRewriteRules, to: processedURL)

        let isMailto = processedURL.scheme?.lowercased() == "mailto"

        // Global UTM stripping (skip for mailto).
        if configuration.globalUTMStrippingEnabled && !isMailto {
            processedURL = stripUTM(processedURL, parameters: configuration.utmStripParameters)
        }

        // Forced browser from yojam:// browser= parameter.
        if let forcedBundleId = request.forcedBrowserBundleId,
           let entry = configuration.browsers.first(where: {
               $0.bundleIdentifier == forcedBundleId
           }) {
            var finalURL = applyRewrites(entry.rewriteRules.filter(\.enabled), to: processedURL)
            if entry.stripUTMParams || configuration.globalUTMStrippingEnabled {
                finalURL = stripUTM(finalURL, parameters: configuration.utmStripParameters)
            }
            let priv = request.forcePrivateWindow || entry.openInPrivateWindow
            return .openDirect(browser: entry, finalURL: finalURL, privateWindow: priv,
                               reason: "Forced browser")
        }

        // Forced picker.
        if request.forcePicker {
            let entries = isMailto ? configuration.emailClients : configuration.browsers
            guard !entries.isEmpty else {
                return isMailto ? .openSystemMailHandler(processedURL) : .openSystemDefault(processedURL)
            }
            let preselected = resolveDefaultIndex(
                entries: entries, url: processedURL, isEmail: isMailto, configuration: configuration)
            return .showPicker(entries: entries, preselectedIndex: preselected,
                               finalURL: processedURL, isEmail: isMailto, reason: nil)
        }

        // Rule evaluation.
        let shiftHeld = (request.modifierFlags & (1 << 17)) != 0

        if let rule = evaluateRules(configuration.rules, url: processedURL,
                                    sourceAppBundleId: request.sourceAppBundleId) {
            processedURL = applyRewrites(rule.rewriteRules.filter(\.enabled), to: processedURL)

            let matchedEntry = configuration.browsers.first {
                $0.bundleIdentifier == rule.targetBundleId
            }
            if rule.stripUTMParams {
                processedURL = stripUTM(processedURL, parameters: configuration.utmStripParameters)
            } else if let entry = matchedEntry, entry.stripUTMParams {
                processedURL = stripUTM(processedURL, parameters: configuration.utmStripParameters)
            }

            let ruleLabel = rule.name.isEmpty ? rule.pattern : rule.name
            let reason = "Matched rule: \(ruleLabel)"

            // For rule targets not in the browser list (e.g. Zoom, Slack, Maps),
            // synthesize a minimal BrowserEntry so the decision can carry
            // the target's bundle ID through to the executor.
            // Use a deterministic UUID so identical inputs yield equal decisions.
            let effectiveEntry = matchedEntry ?? BrowserEntry(
                id: UUID(uuidString: deterministicUUID(for: rule.targetBundleId)) ?? UUID(),
                bundleIdentifier: rule.targetBundleId,
                displayName: rule.targetAppName,
                lastSeenAt: nil
            )

            // Non-browser rule targets (Zoom, Slack, Maps) always open
            // directly — the picker only makes sense for browser targets.
            let isNonBrowserTarget = matchedEntry == nil

            if isNonBrowserTarget {
                let finalURL = applyRewrites(effectiveEntry.rewriteRules.filter(\.enabled), to: processedURL)
                let priv = request.forcePrivateWindow || effectiveEntry.openInPrivateWindow
                return .openDirect(browser: effectiveEntry, finalURL: finalURL,
                                   privateWindow: priv, reason: reason)
            }

            switch configuration.activationMode {
            case .always:
                let entries = configuration.browsers
                guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
                let preselected = entries.firstIndex(where: {
                    $0.bundleIdentifier == rule.targetBundleId
                }) ?? 0
                return .showPicker(entries: entries, preselectedIndex: preselected,
                                   finalURL: processedURL, isEmail: false, reason: reason)

            case .holdShift:
                if shiftHeld {
                    let entries = configuration.browsers
                    guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
                    let preselected = entries.firstIndex(where: {
                        $0.bundleIdentifier == rule.targetBundleId
                    }) ?? 0
                    return .showPicker(entries: entries, preselectedIndex: preselected,
                                       finalURL: processedURL, isEmail: false, reason: reason)
                } else {
                    let finalURL = applyRewrites(effectiveEntry.rewriteRules.filter(\.enabled), to: processedURL)
                    let priv = request.forcePrivateWindow || effectiveEntry.openInPrivateWindow
                    return .openDirect(browser: effectiveEntry, finalURL: finalURL,
                                       privateWindow: priv, reason: reason)
                }

            case .smartFallback:
                let finalURL = applyRewrites(effectiveEntry.rewriteRules.filter(\.enabled), to: processedURL)
                let priv = request.forcePrivateWindow || effectiveEntry.openInPrivateWindow
                return .openDirect(browser: effectiveEntry, finalURL: finalURL,
                                   privateWindow: priv, reason: reason)
            }
        }

        // No rule matched — mailto.
        if isMailto {
            return decideMailto(processedURL, shiftHeld: shiftHeld,
                                forcePrivate: request.forcePrivateWindow,
                                configuration: configuration)
        }

        // No rule matched — http/https.
        switch configuration.activationMode {
        case .always:
            let entries = configuration.browsers
            guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
            let preselected = resolveDefaultIndex(
                entries: entries, url: processedURL, isEmail: false, configuration: configuration)
            return .showPicker(entries: entries, preselectedIndex: preselected,
                               finalURL: processedURL, isEmail: false, reason: nil)

        case .smartFallback:
            let domain = processedURL.host?.lowercased() ?? ""
            if let suggestion = configuration.learnedDomainPreferences[domain],
               let entry = configuration.browsers.first(where: {
                   $0.id.uuidString == suggestion
               }) {
                var finalURL = applyRewrites(entry.rewriteRules.filter(\.enabled), to: processedURL)
                if entry.stripUTMParams || configuration.globalUTMStrippingEnabled {
                    finalURL = stripUTM(finalURL, parameters: configuration.utmStripParameters)
                }
                let priv = request.forcePrivateWindow || entry.openInPrivateWindow
                return .openDirect(browser: entry, finalURL: finalURL, privateWindow: priv,
                                   reason: "Suggested based on history")
            }
            let entries = configuration.browsers
            guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
            let preselected = resolveDefaultIndex(
                entries: entries, url: processedURL, isEmail: false, configuration: configuration)
            return .showPicker(entries: entries, preselectedIndex: preselected,
                               finalURL: processedURL, isEmail: false, reason: nil)

        case .holdShift:
            if shiftHeld {
                let entries = configuration.browsers
                guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
                let preselected = resolveDefaultIndex(
                    entries: entries, url: processedURL, isEmail: false, configuration: configuration)
                return .showPicker(entries: entries, preselectedIndex: preselected,
                                   finalURL: processedURL, isEmail: false, reason: nil)
            }
            return .openSystemDefault(processedURL)
        }
    }

    // MARK: - Mailto

    private static func decideMailto(
        _ url: URL,
        shiftHeld: Bool,
        forcePrivate: Bool,
        configuration: RoutingConfiguration
    ) -> RouteDecision {
        let clients = configuration.emailClients

        if configuration.activationMode == .holdShift && shiftHeld {
            guard !clients.isEmpty else { return .openSystemMailHandler(url) }
            let preselected = resolveDefaultIndex(
                entries: clients, url: url, isEmail: true, configuration: configuration)
            return .showPicker(entries: clients, preselectedIndex: preselected,
                               finalURL: url, isEmail: true, reason: nil)
        }

        if configuration.activationMode == .holdShift && !shiftHeld {
            if let client = clients.first {
                let priv = forcePrivate || client.openInPrivateWindow
                return .openDirect(browser: client, finalURL: url,
                                   privateWindow: priv, reason: "Default email client")
            }
            return .openSystemMailHandler(url)
        }

        if configuration.activationMode != .always, clients.count == 1,
           let client = clients.first {
            let priv = forcePrivate || client.openInPrivateWindow
            return .openDirect(browser: client, finalURL: url,
                               privateWindow: priv, reason: "Only email client")
        }

        guard !clients.isEmpty else { return .openSystemMailHandler(url) }
        let preselected = resolveDefaultIndex(
            entries: clients, url: url, isEmail: true, configuration: configuration)
        return .showPicker(entries: clients, preselectedIndex: preselected,
                           finalURL: url, isEmail: true, reason: nil)
    }

    // MARK: - Rule Evaluation

    private static func evaluateRules(
        _ rules: [Rule], url: URL, sourceAppBundleId: String?
    ) -> Rule? {
        for rule in rules {
            let result = RuleMatcher.evaluate(url: url, against: rule, sourceApp: sourceAppBundleId)
            if result.matched { return rule }
        }
        return nil
    }

    // MARK: - URL Processing

    private static func sanitize(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard url.absoluteString.count <= 32_768 else { return nil }
        switch scheme {
        case "http", "https", "mailto": return url
        default: return nil
        }
    }

    private static func applyRewrites(_ rules: [URLRewriteRule], to url: URL) -> URL {
        var urlString = url.absoluteString
        for rule in rules where rule.enabled {
            if rule.isRegex {
                urlString = RegexMatcher.replaceMatches(
                    in: urlString, pattern: rule.matchPattern,
                    replacement: rule.replacement)
            } else {
                urlString = urlString.replacingOccurrences(
                    of: rule.matchPattern, with: rule.replacement)
            }
        }
        return URL(string: urlString) ?? url
    }

    private static func stripUTM(_ url: URL, parameters: Set<String>) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems, !queryItems.isEmpty else { return url }
        let filtered = queryItems.filter { !parameters.contains($0.name.lowercased()) }
        guard filtered.count < queryItems.count else { return url }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    // MARK: - Default Selection

    private static func resolveDefaultIndex(
        entries: [BrowserEntry], url: URL, isEmail: Bool,
        configuration: RoutingConfiguration
    ) -> Int {
        guard !entries.isEmpty else { return 0 }
        switch configuration.defaultSelectionBehavior {
        case .alwaysFirst:
            return 0
        case .lastUsed:
            let lastId = isEmail ? configuration.lastUsedEmailClientId : configuration.lastUsedBrowserId
            if let lastId, let idx = entries.firstIndex(where: { $0.id == lastId }) {
                return idx
            }
            return 0
        case .smart:
            if let domain = url.host?.lowercased(),
               let suggestedEntryId = configuration.learnedDomainPreferences[domain],
               let idx = entries.firstIndex(where: { $0.id.uuidString == suggestedEntryId }) {
                return idx
            }
            return 0
        }
    }

    /// Produces a valid UUID string deterministically from a bundle ID,
    /// so that synthetic BrowserEntry objects created for the same rule
    /// target across calls are Equatable. Uses MD5 for collision resistance
    /// (non-security usage — just needs uniqueness).
    private static func deterministicUUID(for bundleId: String) -> String {
        var hash = Array(Insecure.MD5.hash(data: Data(bundleId.utf8)))
        hash[6] = (hash[6] & 0x0F) | 0x30  // version 3 (name-based)
        hash[8] = (hash[8] & 0x3F) | 0x80  // RFC 4122 variant
        return String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                      hash[0], hash[1], hash[2], hash[3],
                      hash[4], hash[5], hash[6], hash[7],
                      hash[8], hash[9], hash[10], hash[11],
                      hash[12], hash[13], hash[14], hash[15])
    }
}
