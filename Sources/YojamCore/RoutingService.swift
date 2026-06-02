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
            if url.scheme?.lowercased() == "tel" {
                return .openSystemPhoneHandler(url)
            }
            return .openSystemDefault(url)
        }

        let originalScheme = url.scheme?.lowercased()
        let isMailto = originalScheme == "mailto"
        let isTel = originalScheme == "tel"
        var processedURL = url

        // Global rewrites are for web/mail URLs; phone links should stay intact.
        if !isTel {
            processedURL = applyRewrites(configuration.globalRewriteRules, to: processedURL)
        }

        // Global UTM stripping is web-only.
        if configuration.globalUTMStrippingEnabled && !isMailto && !isTel {
            processedURL = stripUTM(processedURL, parameters: configuration.utmStripParameters)
        }
        let shiftHeld = (request.modifierFlags & (1 << 17)) != 0

        // Forced browser from yojam:// browser= parameter. Phone links stay in
        // the phone-client flow even if a stale browser override is present.
        if !isTel,
           let forcedBundleId = request.forcedBrowserBundleId,
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
            let entries = pickerEntries(
                isMailto: isMailto, isTel: isTel, configuration: configuration)
            guard !entries.isEmpty else {
                if isMailto { return .openSystemMailHandler(processedURL) }
                if isTel { return .openSystemPhoneHandler(processedURL) }
                return .openSystemDefault(processedURL)
            }
            let preselected = resolveDefaultIndex(
                entries: entries, url: processedURL,
                kind: linkKind(isMailto: isMailto, isTel: isTel),
                configuration: configuration)
            return .showPicker(entries: entries, preselectedIndex: preselected,
                               finalURL: processedURL, isEmail: isMailto, reason: nil)
        }

        // Phone links are routed through the phone-client path, not generic
        // web rules like "All URLs -> Work Browser".
        if isTel {
            return decidePhone(processedURL, shiftHeld: shiftHeld,
                               forcePrivate: request.forcePrivateWindow,
                               configuration: configuration)
        }

        // Rule evaluation.
        if let rule = evaluateRules(configuration.rules, url: processedURL,
                                    sourceAppBundleId: request.sourceAppBundleId,
                                    machineIdentifier: configuration.currentMachineIdentifier) {
            processedURL = applyRewrites(rule.rewriteRules.filter(\.enabled), to: processedURL)

            let matchedEntry = matchedBrowserEntry(for: rule, in: configuration.browsers)
            if !isTel && rule.stripUTMParams {
                processedURL = stripUTM(processedURL, parameters: configuration.utmStripParameters)
            } else if !isTel, let entry = matchedEntry, entry.stripUTMParams {
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

            if configuration.activationMode == .holdShift && shiftHeld {
                let entries = configuration.browsers
                guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
                let preselected = preselectedRuleTargetIndex(rule: rule, entries: entries) ?? 0
                return .showPicker(entries: entries, preselectedIndex: preselected,
                                   finalURL: processedURL, isEmail: false, reason: reason)
            }

            let finalURL = applyRewrites(effectiveEntry.rewriteRules.filter(\.enabled), to: processedURL)
            let priv = request.forcePrivateWindow || effectiveEntry.openInPrivateWindow
            return .openDirect(browser: effectiveEntry, finalURL: finalURL,
                               privateWindow: priv, reason: reason)
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
                entries: entries, url: processedURL, kind: .browser, configuration: configuration)
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
                entries: entries, url: processedURL, kind: .browser, configuration: configuration)
            return .showPicker(entries: entries, preselectedIndex: preselected,
                               finalURL: processedURL, isEmail: false, reason: nil)

        case .holdShift:
            if shiftHeld {
                let entries = configuration.browsers
                guard !entries.isEmpty else { return .openSystemDefault(processedURL) }
                let preselected = resolveDefaultIndex(
                    entries: entries, url: processedURL, kind: .browser, configuration: configuration)
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
                entries: clients, url: url, kind: .email, configuration: configuration)
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
            entries: clients, url: url, kind: .email, configuration: configuration)
        return .showPicker(entries: clients, preselectedIndex: preselected,
                           finalURL: url, isEmail: true, reason: nil)
    }

    // MARK: - Tel

    private static func decidePhone(
        _ url: URL,
        shiftHeld: Bool,
        forcePrivate: Bool,
        configuration: RoutingConfiguration
    ) -> RouteDecision {
        let clients = configuration.phoneClients

        if configuration.activationMode == .holdShift && shiftHeld {
            guard !clients.isEmpty else { return .openSystemPhoneHandler(url) }
            let preselected = resolveDefaultIndex(
                entries: clients, url: url, kind: .phone, configuration: configuration)
            return .showPicker(entries: clients, preselectedIndex: preselected,
                               finalURL: url, isEmail: false, reason: nil)
        }

        if configuration.activationMode == .holdShift && !shiftHeld {
            if let client = clients.first {
                let priv = forcePrivate || client.openInPrivateWindow
                return .openDirect(browser: client, finalURL: url,
                                   privateWindow: priv, reason: "Default phone client")
            }
            return .openSystemPhoneHandler(url)
        }

        if configuration.activationMode != .always, clients.count == 1,
           let client = clients.first {
            let priv = forcePrivate || client.openInPrivateWindow
            return .openDirect(browser: client, finalURL: url,
                               privateWindow: priv, reason: "Only phone client")
        }

        guard !clients.isEmpty else { return .openSystemPhoneHandler(url) }
        let preselected = resolveDefaultIndex(
            entries: clients, url: url, kind: .phone, configuration: configuration)
        return .showPicker(entries: clients, preselectedIndex: preselected,
                           finalURL: url, isEmail: false, reason: nil)
    }

    // MARK: - Rule Evaluation

    private static func evaluateRules(
        _ rules: [Rule],
        url: URL,
        sourceAppBundleId: String?,
        machineIdentifier: String?
    ) -> Rule? {
        for rule in rules {
            let result = RuleMatcher.evaluate(
                url: url,
                against: rule,
                sourceApp: sourceAppBundleId,
                machineIdentifier: machineIdentifier
            )
            if result.matched { return rule }
        }
        return nil
    }

    private static func matchedBrowserEntry(
        for rule: Rule,
        in entries: [BrowserEntry]
    ) -> BrowserEntry? {
        if let targetId = rule.targetBrowserEntryId,
           let entry = entries.first(where: { $0.id == targetId }) {
            return entry
        }
        return entries.first { $0.bundleIdentifier == rule.targetBundleId }
    }

    private static func preselectedRuleTargetIndex(
        rule: Rule,
        entries: [BrowserEntry]
    ) -> Int? {
        if let targetId = rule.targetBrowserEntryId,
           let index = entries.firstIndex(where: { $0.id == targetId }) {
            return index
        }
        return entries.firstIndex { $0.bundleIdentifier == rule.targetBundleId }
    }

    // MARK: - URL Processing

    private static func sanitize(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        guard url.absoluteString.count <= 32_768 else { return nil }
        switch scheme {
        case "http", "https", "mailto", "tel": return url
        case "file":
            // Local files (HTML/XHTML/HTM) reach here when Yojam is the
            // registered default handler. Require a real file URL with a
            // non-empty path so a malformed `file:` string can't sneak through.
            guard url.isFileURL, !url.path.isEmpty else { return nil }
            return url
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

    private enum LinkKind {
        case browser, email, phone
    }

    private static func pickerEntries(
        isMailto: Bool,
        isTel: Bool,
        configuration: RoutingConfiguration
    ) -> [BrowserEntry] {
        if isMailto { return configuration.emailClients }
        if isTel { return configuration.phoneClients }
        return configuration.browsers
    }

    private static func linkKind(isMailto: Bool, isTel: Bool) -> LinkKind {
        if isMailto { return .email }
        if isTel { return .phone }
        return .browser
    }

    private static func resolveDefaultIndex(
        entries: [BrowserEntry], url: URL, kind: LinkKind,
        configuration: RoutingConfiguration
    ) -> Int {
        guard !entries.isEmpty else { return 0 }
        switch configuration.defaultSelectionBehavior {
        case .alwaysFirst:
            return 0
        case .lastUsed:
            let lastId: UUID?
            switch kind {
            case .browser: lastId = configuration.lastUsedBrowserId
            case .email: lastId = configuration.lastUsedEmailClientId
            case .phone: lastId = configuration.lastUsedPhoneClientId
            }
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
