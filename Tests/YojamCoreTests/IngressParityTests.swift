import XCTest
@testable import YojamCore

/// Verifies that the same target URL produces structurally equivalent
/// IncomingLinkRequests regardless of the ingress path. The routing
/// pipeline only examines the URL, sourceAppBundleId, modifiers, and
/// force flags — so parity means the URL arrives intact through each path.
final class IngressParityTests: XCTestCase {
    let targetURL = URL(string: "https://example.com/page?q=search")!

    // MARK: - All origins produce the same URL

    func testAllOriginsPreserveTargetURL() {
        let origins: [(IngressOrigin, String?)] = [
            (.defaultHandler, nil),
            (.handoff, SourceAppSentinel.handoff),
            (.airdrop, SourceAppSentinel.airdrop),
            (.shareExtension, SourceAppSentinel.shareExtension),
            (.safariExtension, SourceAppSentinel.safariExtension),
            (.chromeExtension, SourceAppSentinel.chromeExtension),
            (.firefoxExtension, SourceAppSentinel.firefoxExtension),
            (.servicesMenu, SourceAppSentinel.servicesMenu),
            (.urlScheme, SourceAppSentinel.urlScheme),
            (.intent, nil),
            (.fileOpen, nil),
            (.clipboard, nil),
        ]

        for (origin, sentinel) in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                sourceAppBundleId: sentinel,
                origin: origin
            )
            XCTAssertEqual(
                request.url.absoluteString, targetURL.absoluteString,
                "URL should be preserved for origin: \(origin)")
        }
    }

    // MARK: - yojam:// round-trip preserves URL

    func testYojamSchemeRoundTripPreservesURL() {
        // Build a yojam:// URL the way the Share Extension would
        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL,
            source: SourceAppSentinel.shareExtension
        ) else {
            XCTFail("buildRoute should succeed")
            return
        }

        // Parse it back the way AppDelegate would
        guard let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should round-trip through yojam:// scheme")
            return
        }

        XCTAssertEqual(request.url.absoluteString, targetURL.absoluteString)
        XCTAssertEqual(request.sourceAppBundleId, SourceAppSentinel.shareExtension)
    }

    // MARK: - Internet-location file normalization produces same URL

    func testWeblocExtractionProducesHTTPURL() {
        // IncomingLinkExtractor.normalize passes through http/https URLs
        let normalized = IncomingLinkExtractor.normalize(targetURL)
        XCTAssertEqual(normalized?.absoluteString, targetURL.absoluteString)
    }

    func testHTTPPassthroughMatchesHandoff() {
        let normalized = IncomingLinkExtractor.normalize(targetURL)
        let handoffRequest = IncomingLinkRequest(
            url: targetURL,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff
        )
        XCTAssertEqual(normalized?.absoluteString, handoffRequest.url.absoluteString,
                       "File-open normalized URL should match Handoff URL")
    }

    // MARK: - Force flags default to false across all origins

    func testDefaultForceFlags() {
        let origins: [IngressOrigin] = [
            .defaultHandler, .handoff, .airdrop, .shareExtension,
            .safariExtension, .chromeExtension, .firefoxExtension,
            .servicesMenu, .urlScheme, .intent, .fileOpen, .clipboard,
        ]
        for origin in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                origin: origin
            )
            XCTAssertFalse(request.forcePicker,
                          "forcePicker should default to false for \(origin)")
            XCTAssertFalse(request.forcePrivateWindow,
                          "forcePrivateWindow should default to false for \(origin)")
            XCTAssertNil(request.forcedBrowserBundleId,
                        "forcedBrowserBundleId should default to nil for \(origin)")
        }
    }

    // MARK: - yojam:// with force flags

    func testYojamSchemeForceFlags() {
        guard let yojamURL = YojamCommand.buildRoute(
            target: targetURL,
            browser: "com.google.Chrome",
            pick: true,
            privateWindow: true
        ),
        let command = YojamCommand.parse(yojamURL),
        case .route(let request) = command else {
            XCTFail("Should parse with flags")
            return
        }

        XCTAssertTrue(request.forcePicker)
        XCTAssertTrue(request.forcePrivateWindow)
        XCTAssertEqual(request.forcedBrowserBundleId, "com.google.Chrome")
    }

    // MARK: - Mailto parity

    func testMailtoPreservedAcrossOrigins() {
        let mailtoURL = URL(string: "mailto:test@example.com?subject=Hello")!
        let origins: [IngressOrigin] = [
            .defaultHandler, .servicesMenu, .urlScheme, .intent,
        ]
        for origin in origins {
            let request = IncomingLinkRequest(
                url: mailtoURL,
                origin: origin
            )
            XCTAssertEqual(request.url.scheme, "mailto",
                          "mailto should be preserved for \(origin)")
            XCTAssertEqual(request.url.absoluteString, mailtoURL.absoluteString,
                          "Full mailto URL should be preserved for \(origin)")
        }
    }

    func testMailtoThroughYojamScheme() {
        let mailtoURL = URL(string: "mailto:test@example.com")!
        guard let yojamURL = YojamCommand.buildRoute(target: mailtoURL),
              let command = YojamCommand.parse(yojamURL),
              case .route(let request) = command else {
            XCTFail("Should handle mailto through yojam://")
            return
        }
        XCTAssertEqual(request.url.scheme, "mailto")
    }

    // MARK: - RouteDecision parity via RoutingService

    /// A minimal configuration with one browser and no rules,
    /// used to verify that RoutingService produces identical decisions
    /// for the same URL regardless of ingress origin.
    private var parityConfig: RoutingConfiguration {
        let browser = BrowserEntry(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        )
        return RoutingConfiguration(
            browsers: [browser],
            emailClients: [],
            rules: [],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .always,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )
    }

    func testRouteDecisionIdenticalAcrossOrigins() {
        let config = parityConfig
        // All origins with their typical sentinels
        let origins: [(IngressOrigin, String?)] = [
            (.defaultHandler, nil),
            (.handoff, SourceAppSentinel.handoff),
            (.airdrop, SourceAppSentinel.airdrop),
            (.shareExtension, SourceAppSentinel.shareExtension),
            (.safariExtension, SourceAppSentinel.safariExtension),
            (.chromeExtension, SourceAppSentinel.chromeExtension),
            (.firefoxExtension, SourceAppSentinel.firefoxExtension),
            (.servicesMenu, SourceAppSentinel.servicesMenu),
            (.urlScheme, SourceAppSentinel.urlScheme),
            (.intent, nil),
            (.fileOpen, nil),
            (.clipboard, nil),
        ]

        var decisions: [RouteDecision] = []
        for (origin, sentinel) in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                sourceAppBundleId: sentinel,
                origin: origin
            )
            let decision = RoutingService.decide(request: request, configuration: config)
            decisions.append(decision)
        }

        // All decisions should be identical (same URL, no source-specific rules)
        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "Decision for origin \(origins[i].0) should match defaultHandler")
        }

        // Verify the actual decision type: always mode + 1 browser = showPicker
        if case .showPicker(let entries, let preselected, let finalURL, let isEmail, _) = first {
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(preselected, 0)
            XCTAssertEqual(finalURL, targetURL)
            XCTAssertFalse(isEmail)
        } else {
            XCTFail("Expected showPicker in always mode with browsers available")
        }
    }

    func testRouteDecisionWithRuleIdenticalAcrossOrigins() {
        let browser = BrowserEntry(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Chrome"
        )
        let rule = Rule(
            name: "Example",
            matchType: .domain,
            pattern: "example.com",
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome"
        )
        let config = RoutingConfiguration(
            browsers: [browser],
            emailClients: [],
            rules: [rule],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .smartFallback,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )

        // Test with origins that have no source-specific rule filter
        let origins: [IngressOrigin] = [
            .defaultHandler, .handoff, .shareExtension, .servicesMenu, .intent,
        ]

        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(
                url: targetURL,
                origin: origin
            )
            let decision = RoutingService.decide(request: request, configuration: config)
            decisions.append(decision)
        }

        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "Rule-matched decision for \(origins[i]) should be identical")
        }

        // Should be openDirect with Chrome in smartFallback mode
        if case .openDirect(let entry, _, _, let reason) = first {
            XCTAssertEqual(entry.bundleIdentifier, "com.google.Chrome")
            XCTAssertTrue(reason.contains("Example"))
        } else {
            XCTFail("Expected openDirect for rule match in smartFallback mode")
        }
    }

    func testMailtoDecisionIdenticalAcrossOrigins() {
        let mailClient = BrowserEntry(
            bundleIdentifier: "com.apple.mail",
            displayName: "Mail"
        )
        let config = RoutingConfiguration(
            browsers: [],
            emailClients: [mailClient],
            rules: [],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .smartFallback,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )

        let mailtoURL = URL(string: "mailto:test@example.com")!
        let origins: [IngressOrigin] = [.defaultHandler, .servicesMenu, .intent]

        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(url: mailtoURL, origin: origin)
            decisions.append(RoutingService.decide(request: request, configuration: config))
        }

        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "Mailto decision for \(origins[i]) should be identical")
        }

        // Single email client in smartFallback → openDirect
        if case .openDirect(let entry, _, _, _) = first {
            XCTAssertEqual(entry.bundleIdentifier, "com.apple.mail")
        } else {
            XCTFail("Expected openDirect for single mailto client in smartFallback")
        }
    }

    func testDisabledRoutingIdenticalAcrossOrigins() {
        var config = parityConfig
        // Rebuild with isEnabled = false
        let disabledConfig = RoutingConfiguration(
            browsers: config.browsers,
            emailClients: config.emailClients,
            rules: config.rules,
            globalRewriteRules: config.globalRewriteRules,
            utmStripParameters: config.utmStripParameters,
            globalUTMStrippingEnabled: config.globalUTMStrippingEnabled,
            activationMode: config.activationMode,
            defaultSelectionBehavior: config.defaultSelectionBehavior,
            isEnabled: false,
            learnedDomainPreferences: config.learnedDomainPreferences,
            lastUsedBrowserId: config.lastUsedBrowserId,
            lastUsedEmailClientId: config.lastUsedEmailClientId
        )

        let origins: [IngressOrigin] = [.defaultHandler, .handoff, .shareExtension]
        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(url: targetURL, origin: origin)
            decisions.append(RoutingService.decide(request: request, configuration: disabledConfig))
        }

        for decision in decisions {
            if case .openSystemDefault(let url) = decision {
                XCTAssertEqual(url, targetURL)
            } else {
                XCTFail("Expected openSystemDefault when routing is disabled")
            }
        }
    }

    func testHoldShiftModeParityWithoutShift() {
        let browser = BrowserEntry(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        )
        let config = RoutingConfiguration(
            browsers: [browser],
            emailClients: [],
            rules: [],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .holdShift,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )

        // Without shift held, holdShift mode opens system default
        let origins: [IngressOrigin] = [.defaultHandler, .handoff, .servicesMenu]
        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(url: targetURL, origin: origin)
            decisions.append(RoutingService.decide(request: request, configuration: config))
        }

        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "holdShift decision for \(origins[i]) should be identical")
        }
        if case .openSystemDefault = first {
            // correct
        } else {
            XCTFail("Expected openSystemDefault in holdShift without shift")
        }
    }

    func testHoldShiftModeParityWithShift() {
        let browser = BrowserEntry(
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari"
        )
        let config = RoutingConfiguration(
            browsers: [browser],
            emailClients: [],
            rules: [],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .holdShift,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )

        let shiftFlag: UInt = 1 << 17
        let origins: [IngressOrigin] = [.defaultHandler, .handoff, .servicesMenu]
        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(
                url: targetURL, origin: origin, modifierFlags: shiftFlag)
            decisions.append(RoutingService.decide(request: request, configuration: config))
        }

        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "holdShift+shift decision for \(origins[i]) should be identical")
        }
        if case .showPicker = first {
            // correct
        } else {
            XCTFail("Expected showPicker in holdShift with shift held")
        }
    }

    func testNonBrowserRuleTargetProducesOpenDirect() {
        // Rules can target non-browser apps (Zoom, Slack). RoutingService
        // should synthesize a BrowserEntry and produce openDirect.
        let rule = Rule(
            name: "Zoom",
            matchType: .domain,
            pattern: "zoom.us",
            targetBundleId: "us.zoom.xos",
            targetAppName: "Zoom"
        )
        let config = RoutingConfiguration(
            browsers: [], // no browsers at all
            emailClients: [],
            rules: [rule],
            globalRewriteRules: [],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .smartFallback,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil
        )

        let zoomURL = URL(string: "https://zoom.us/j/123456")!
        let origins: [IngressOrigin] = [.defaultHandler, .handoff, .servicesMenu]
        var decisions: [RouteDecision] = []
        for origin in origins {
            let request = IncomingLinkRequest(url: zoomURL, origin: origin)
            decisions.append(RoutingService.decide(request: request, configuration: config))
        }

        let first = decisions[0]
        for (i, decision) in decisions.enumerated() {
            XCTAssertEqual(decision, first,
                           "Non-browser rule target decision for \(origins[i]) should be identical")
        }

        if case .openDirect(let entry, _, _, let reason) = first {
            XCTAssertEqual(entry.bundleIdentifier, "us.zoom.xos")
            XCTAssertTrue(reason.contains("Zoom"))
        } else {
            XCTFail("Expected openDirect for non-browser rule target, got: \(first)")
        }
    }
}
