import XCTest
@testable import YojamCore

/// Tests for RoutingService.decide covering activation mode × rule match ×
/// source-app filter × mailto × forced browser × picker fallback.
/// Uses JSON-style inline fixture data.
final class RoutingServiceDecisionTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(
        browsers: [BrowserEntry] = [],
        emailClients: [BrowserEntry] = [],
        phoneClients: [BrowserEntry] = [],
        rules: [Rule] = [],
        activationMode: ActivationMode = .always,
        defaultSelection: DefaultSelectionBehavior = .alwaysFirst,
        isEnabled: Bool = true,
        globalRewriteRules: [URLRewriteRule] = [],
        globalUTMStripping: Bool = false,
        utmParams: Set<String> = [],
        currentMachineIdentifier: String? = nil
    ) -> RoutingConfiguration {
        RoutingConfiguration(
            browsers: browsers, emailClients: emailClients,
            phoneClients: phoneClients,
            rules: rules, globalRewriteRules: globalRewriteRules,
            utmStripParameters: utmParams,
            globalUTMStrippingEnabled: globalUTMStripping,
            activationMode: activationMode,
            defaultSelectionBehavior: defaultSelection,
            isEnabled: isEnabled,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil,
            lastUsedPhoneClientId: nil,
            shortlinkResolutionEnabled: false,
            currentMachineIdentifier: currentMachineIdentifier
        )
    }

    private let chrome = BrowserEntry(
        bundleIdentifier: "com.google.Chrome", displayName: "Chrome")
    private let firefox = BrowserEntry(
        bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox")
    private let mail = BrowserEntry(
        bundleIdentifier: "com.apple.mail", displayName: "Mail")
    private let faceTime = BrowserEntry(
        bundleIdentifier: "com.apple.FaceTime", displayName: "FaceTime")

    // MARK: - Disabled routing

    func testDisabledRoutingPassesThrough() {
        let config = makeConfig(browsers: [chrome], isEnabled: false)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemDefault = decision {} else {
            XCTFail("Disabled routing should pass through to system default")
        }
    }

    func testDisabledRoutingMailtoUsesSystemMail() {
        let config = makeConfig(emailClients: [mail], isEnabled: false)
        let request = IncomingLinkRequest(
            url: URL(string: "mailto:test@example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemMailHandler = decision {} else {
            XCTFail("Disabled routing with mailto should use system mail handler")
        }
    }

    // MARK: - Always mode

    func testAlwaysModeShowsPicker() {
        let config = makeConfig(browsers: [chrome, firefox], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(let entries, _, _, _, _, _, _) = decision {
            XCTAssertEqual(entries.count, 2)
        } else {
            XCTFail("Always mode should show picker")
        }
    }

    // MARK: - HoldShift mode

    func testHoldShiftWithoutShiftOpensDefault() {
        let config = makeConfig(browsers: [chrome, firefox], activationMode: .holdShift)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler,
            modifierFlags: 0)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemDefault = decision {} else {
            XCTFail("HoldShift without shift held should open system default")
        }
    }

    func testHoldShiftWithShiftShowsPicker() {
        let config = makeConfig(browsers: [chrome, firefox], activationMode: .holdShift)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler,
            modifierFlags: 1 << 17)  // shift flag
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker = decision {} else {
            XCTFail("HoldShift with shift held should show picker")
        }
    }

    // MARK: - Rule matching

    func testDomainRuleMatchesAndOpensDirect() {
        let rule = Rule(
            name: "Zoom", matchType: .domain, pattern: "zoom.us",
            targetBundleId: "us.zoom.xos", targetAppName: "Zoom")
        let config = makeConfig(
            browsers: [chrome], rules: [rule], activationMode: .smartFallback)
        let request = IncomingLinkRequest(
            url: URL(string: "https://zoom.us/j/123")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "us.zoom.xos")
            XCTAssert(reason.contains("Zoom"))
        } else {
            XCTFail("Domain rule should match and open directly in smartFallback mode")
        }
    }

    func testWhatWGRuleNormalizesTheFinalBrowserURL() throws {
        let rule = Rule(
            name: "Imported Finicky route",
            matchType: .all,
            pattern: "",
            urlNormalization: .whatwg,
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome"
        )
        let config = makeConfig(
            browsers: [chrome],
            rules: [rule],
            activationMode: .smartFallback
        )
        let cases = [
            ("https://EXAMPLE.com", "https://example.com/"),
            ("https://EXAMPLE.com:443/path", "https://example.com/path"),
            ("https://example.com/a/%2e%2e/b", "https://example.com/b"),
        ]

        for (input, expected) in cases {
            let request = IncomingLinkRequest(
                url: try XCTUnwrap(URL(string: input)),
                origin: .defaultHandler
            )
            let decision = RoutingService.decide(
                request: request,
                configuration: config
            )

            guard case .openDirect(_, let finalURL, _, _, _) = decision else {
                XCTFail("The imported route should open directly for \(input)")
                continue
            }
            XCTAssertEqual(finalURL.absoluteString, expected)
        }
    }

    func testWhatWGRuleNormalizesAConstantRewriteResult() throws {
        let rewrite = URLRewriteRule(
            name: "Imported constant rewrite",
            matchPattern: "(?s:^.*$)",
            replacement: "https://DEST.example:443/a/%2e%2e/final",
            urlNormalization: .whatwg
        )
        let rule = Rule(
            name: "Imported Finicky route",
            matchType: .all,
            pattern: "",
            urlNormalization: .whatwg,
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome",
            rewriteRules: [rewrite]
        )
        let config = makeConfig(
            browsers: [chrome],
            rules: [rule],
            activationMode: .smartFallback
        )
        let request = IncomingLinkRequest(
            url: try XCTUnwrap(URL(string: "https://source.example")),
            origin: .defaultHandler
        )

        let decision = RoutingService.decide(request: request, configuration: config)

        guard case .openDirect(_, let finalURL, _, _, _) = decision else {
            return XCTFail("The imported route should open directly")
        }
        XCTAssertEqual(finalURL.absoluteString, "https://dest.example/final")
    }

    func testExactFinickyRuleDoesNotInheritBrowserEntryTransforms() throws {
        let entry = BrowserEntry(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Chrome",
            stripUTMParams: true,
            openInPrivateWindow: true,
            rewriteRules: [URLRewriteRule(
                name: "Entry rewrite",
                matchPattern: "example.com",
                replacement: "wrong.example")]
        )
        let rule = Rule(
            name: "Imported Finicky route",
            matchType: .all,
            pattern: "",
            urlNormalization: .whatwg,
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome",
            metadata: ["finickyExactBrowserAction": "true"]
        )
        let config = makeConfig(
            browsers: [entry],
            rules: [rule],
            activationMode: .smartFallback,
            utmParams: ["oauth"]
        )
        let request = IncomingLinkRequest(
            url: try XCTUnwrap(URL(
                string: "https://EXAMPLE.com:443/callback?oauth=keep")),
            origin: .defaultHandler
        )

        let decision = RoutingService.decide(request: request, configuration: config)

        guard case .openDirect(_, let finalURL, let privateWindow, _, _) = decision else {
            return XCTFail("The imported route should open directly")
        }
        XCTAssertEqual(
            finalURL.absoluteString,
            "https://example.com/callback?oauth=keep")
        XCTAssertFalse(privateWindow)
    }

    func testLocalHTMLFileURLCanMatchRegexRule() {
        let rule = Rule(
            name: "Local HTML",
            matchType: .regex,
            pattern: #"^file:///.*\.html?($|[?#])"#,
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome")
        let config = makeConfig(
            browsers: [chrome],
            rules: [rule],
            activationMode: .smartFallback)
        let url = URL(fileURLWithPath: "/tmp/yojam-test.html")
        let request = IncomingLinkRequest(url: url, origin: .fileOpen)

        let decision = RoutingService.decide(request: request, configuration: config)

        if case .openDirect(let browser, let finalURL, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "com.google.Chrome")
            XCTAssertEqual(finalURL, url)
            XCTAssertEqual(reason, "Matched rule: Local HTML")
        } else {
            XCTFail("Local HTML file URLs should route through the rule engine")
        }
    }

    func testBrowserRuleOpensDirectEvenWhenPickerNormallyShows() {
        let rule = Rule(
            name: "Chrome Work", matchType: .domain, pattern: "example.com",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome")
        let config = makeConfig(
            browsers: [chrome, firefox], rules: [rule], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "com.google.Chrome")
            XCTAssertEqual(reason, "Matched rule: Chrome Work")
        } else {
            XCTFail("Matched browser rules should open directly")
        }
    }

    func testShiftBypassesMatchedRuleAndShowsOriginalURL() {
        let rule = Rule(
            name: "Chrome Work", matchType: .domain, pattern: "example.com",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome",
            rewriteRules: [URLRewriteRule(
                name: "Rule rewrite",
                matchPattern: "https://example.com",
                replacement: "https://rewritten.example")])
        let config = makeConfig(
            browsers: [chrome, firefox], rules: [rule], activationMode: .smartFallback)
        let originalURL = URL(string: "https://example.com/original")!
        let request = IncomingLinkRequest(
            url: originalURL,
            origin: .defaultHandler,
            modifierFlags: 1 << 17)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(
            let entries, let preselected, let finalURL, _, let reason, _, _
        ) = decision {
            XCTAssertEqual(entries.count, 2)
            XCTAssertEqual(preselected, 0)
            XCTAssertEqual(finalURL, originalURL)
            XCTAssertEqual(reason, "Shift held: skipped rules and rewrites")
        } else {
            XCTFail("Shift should bypass a matching rule and force the picker")
        }
    }

    func testShiftBypassesGlobalRewriteInAlwaysMode() {
        let originalURL = URL(string: "https://x.com/yojam/status/123")!
        let rewrite = URLRewriteRule(
            name: "X to alternate frontend",
            matchPattern: #"^https://x\.com/(.*)"#,
            replacement: "https://example.net/$1")
        let config = makeConfig(
            browsers: [chrome, firefox],
            activationMode: .always,
            globalRewriteRules: [rewrite])
        let request = IncomingLinkRequest(
            url: originalURL,
            origin: .defaultHandler,
            modifierFlags: 1 << 17)

        let decision = RoutingService.decide(request: request, configuration: config)

        if case .showPicker(_, _, let finalURL, _, let reason, _, _) = decision {
            XCTAssertEqual(finalURL, originalURL)
            XCTAssertEqual(reason, "Shift held: skipped rules and rewrites")
        } else {
            XCTFail("Shift should preserve the original URL before showing the picker")
        }
    }

    func testAllURLsRuleCanBeScopedToSourceApp() {
        let rule = Rule(
            name: "Slack Links", matchType: .all, pattern: "",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome",
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let config = makeConfig(
            browsers: [chrome], rules: [rule], activationMode: .smartFallback)

        let matching = IncomingLinkRequest(
            url: URL(string: "https://anything.example/path")!,
            sourceAppBundleId: "com.tinyspeck.slackmacgap",
            origin: .defaultHandler)
        if case .openDirect(let browser, _, _, _, _) =
            RoutingService.decide(request: matching, configuration: config) {
            XCTAssertEqual(browser.bundleIdentifier, "com.google.Chrome")
        } else {
            XCTFail("All-URLs source rule should match the configured source")
        }

        let nonMatching = IncomingLinkRequest(
            url: URL(string: "https://anything.example/path")!,
            sourceAppBundleId: "com.apple.mail",
            origin: .defaultHandler)
        if case .showPicker = RoutingService.decide(request: nonMatching, configuration: config) {
        } else {
            XCTFail("All-URLs source rule should skip other sources")
        }
    }

    func testSeveralWorkAppsUseOneRuleAndConfiguredProfile() {
        let work = BrowserEntry(
            bundleIdentifier: "com.google.Chrome", displayName: "Chrome",
            profileId: "Profile 2", profileName: "Work")
        let apps = ["com.apple.mail", "com.tinyspeck.slackmacgap", "com.microsoft.teams2",
                    "com.apple.iCal", "com.microsoft.Outlook"]
        let rule = Rule(
            name: "Work apps", matchType: .all, pattern: "",
            targetBundleId: work.bundleIdentifier, targetAppName: work.fullDisplayName,
            targetBrowserEntryId: work.id,
            sourceApps: apps.map { RuleSourceApp(bundleId: $0) })
        let config = makeConfig(browsers: [chrome, work], rules: [rule], activationMode: .smartFallback)
        for source in apps {
            let request = IncomingLinkRequest(
                url: URL(string: "https://example.com")!, sourceAppBundleId: source, origin: .defaultHandler)
            guard case .openDirect(let browser, _, _, _, _) = RoutingService.decide(
                request: request, configuration: config) else {
                XCTFail("Expected the work profile for \(source)")
                continue
            }
            XCTAssertEqual(browser.id, work.id)
            XCTAssertEqual(browser.profileId, "Profile 2")
        }
    }

    func testEarlierLinearRuleBeatsBroadSlackSourceRule() {
        let slackRule = Rule(
            name: "All Slack Links", matchType: .all, pattern: "",
            targetBundleId: "org.mozilla.firefox", targetAppName: "Firefox",
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let linearRule = Rule(
            name: "Linear", matchType: .domainSuffix, pattern: "linear.app",
            targetBundleId: "com.linear", targetAppName: "Linear",
            isBuiltIn: true)
        let config = makeConfig(
            browsers: [firefox],
            rules: [linearRule, slackRule],
            activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "https://linear.app/acme/issue/ABC-123")!,
            sourceAppBundleId: "com.tinyspeck.slackmacgap",
            origin: .defaultHandler)

        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "com.linear")
            XCTAssertEqual(reason, "Matched rule: Linear")
        } else {
            XCTFail("Earlier Linear rule should beat a broader Slack source rule")
        }
    }

    func testBroadSlackSourceRuleWinsWhenOrderedBeforeLinearRule() {
        let slackRule = Rule(
            name: "All Slack Links", matchType: .all, pattern: "",
            targetBundleId: "org.mozilla.firefox", targetAppName: "Firefox",
            sourceApps: [RuleSourceApp(bundleId: "com.tinyspeck.slackmacgap")])
        let linearRule = Rule(
            name: "Linear", matchType: .domainSuffix, pattern: "linear.app",
            targetBundleId: "com.linear", targetAppName: "Linear",
            isBuiltIn: true)
        let config = makeConfig(
            browsers: [firefox],
            rules: [slackRule, linearRule],
            activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "https://linear.app/acme/issue/ABC-123")!,
            sourceAppBundleId: "com.tinyspeck.slackmacgap",
            origin: .defaultHandler)

        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "org.mozilla.firefox")
            XCTAssertEqual(reason, "Matched rule: All Slack Links")
        } else {
            XCTFail("The first matching rule in the ordered list should win")
        }
    }

    func testRuleTargetsSpecificBrowserEntryById() {
        let workId = UUID()
        let personalId = UUID()
        let work = BrowserEntry(
            id: workId,
            bundleIdentifier: "com.vivaldi.Vivaldi",
            displayName: "Vivaldi",
            profileId: "Work",
            profileName: "Work")
        let personal = BrowserEntry(
            id: personalId,
            bundleIdentifier: "com.vivaldi.Vivaldi",
            displayName: "Vivaldi",
            profileId: "Personal",
            profileName: "Personal")
        let rule = Rule(
            name: "Beeper Personal", matchType: .all, pattern: "",
            targetBundleId: "com.vivaldi.Vivaldi",
            targetAppName: "Vivaldi — Personal",
            targetBrowserEntryId: personalId,
            sourceApps: [RuleSourceApp(bundleId: "com.automattic.beeper")])
        let config = makeConfig(
            browsers: [work, personal], rules: [rule], activationMode: .smartFallback)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: "com.automattic.beeper",
            origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, _, _) = decision {
            XCTAssertEqual(browser.id, personalId)
            XCTAssertEqual(browser.profileId, "Personal")
        } else {
            XCTFail("Rule should carry the selected browser entry/profile")
        }
    }

    func testShiftBypassDoesNotPreselectMatchedRuleTarget() {
        let workId = UUID()
        let personalId = UUID()
        let work = BrowserEntry(
            id: workId,
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "work",
            profileName: "Work")
        let personal = BrowserEntry(
            id: personalId,
            bundleIdentifier: "org.mozilla.firefox",
            displayName: "Firefox",
            profileId: "personal",
            profileName: "Personal")
        let rule = Rule(
            name: "Personal Mail",
            matchType: .domain,
            pattern: "mail.example.com",
            targetBundleId: "org.mozilla.firefox",
            targetAppName: "Firefox - Personal",
            targetBrowserEntryId: personalId)
        let config = makeConfig(
            browsers: [work, personal],
            rules: [rule],
            activationMode: .holdShift)
        let request = IncomingLinkRequest(
            url: URL(string: "https://mail.example.com/inbox")!,
            origin: .defaultHandler,
            modifierFlags: 1 << 17)

        let decision = RoutingService.decide(request: request, configuration: config)

        if case .showPicker(
            let entries, let preselected, let finalURL, _, let reason, _, _
        ) = decision {
            XCTAssertEqual(entries[preselected].id, workId)
            XCTAssertEqual(entries[preselected].profileId, "work")
            XCTAssertEqual(finalURL.absoluteString, "https://mail.example.com/inbox")
            XCTAssertEqual(reason, "Shift held: skipped rules and rewrites")
        } else {
            XCTFail("Shift should bypass the rule target and use the normal picker default")
        }
    }

    func testMachineScopedRuleOnlyMatchesCurrentMachine() {
        let rule = Rule(
            name: "Work Mac", matchType: .all, pattern: "",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome",
            machineScopeIdentifiers: ["machine-a"],
            machineScopeNames: ["machine-a": "Work Mac"])

        let matchingConfig = makeConfig(
            browsers: [chrome], rules: [rule], activationMode: .smartFallback,
            currentMachineIdentifier: "machine-a")
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler)
        if case .openDirect(let browser, _, _, _, _) =
            RoutingService.decide(request: request, configuration: matchingConfig) {
            XCTAssertEqual(browser.bundleIdentifier, "com.google.Chrome")
        } else {
            XCTFail("Machine-scoped rule should match its own machine")
        }

        let otherConfig = makeConfig(
            browsers: [chrome], rules: [rule], activationMode: .smartFallback,
            currentMachineIdentifier: "machine-b")
        if case .showPicker = RoutingService.decide(request: request, configuration: otherConfig) {
        } else {
            XCTFail("Machine-scoped rule should not match another machine")
        }
    }

    func testSourceAppFilterSkipsNonMatchingSource() {
        var rule = Rule(
            name: "Work", matchType: .domain, pattern: "example.com",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome")
        rule.sourceApps = [RuleSourceApp(bundleId: SourceAppSentinel.safariExtension)]
        let config = makeConfig(
            browsers: [chrome], rules: [rule], activationMode: .smartFallback)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!,
            sourceAppBundleId: SourceAppSentinel.chromeExtension,
            origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        // Rule should NOT match because source doesn't match
        if case .showPicker = decision {} else if case .openSystemDefault = decision {} else {
            XCTFail("Source-filtered rule should not match with different source")
        }
    }

    // MARK: - Forced browser

    func testForcedBrowserSkipsRules() {
        let config = makeConfig(browsers: [chrome, firefox])
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .urlScheme,
            forcedBrowserBundleId: "org.mozilla.firefox")
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openDirect(let browser, _, _, let reason, _) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "org.mozilla.firefox")
            XCTAssertEqual(reason, "Forced browser")
        } else {
            XCTFail("Forced browser should open directly")
        }
    }

    // MARK: - Force picker

    func testForcePickerShowsPicker() {
        let config = makeConfig(
            browsers: [chrome, firefox], activationMode: .holdShift)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .urlScheme,
            modifierFlags: 0, forcePicker: true)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker = decision {} else {
            XCTFail("Force picker should show picker regardless of activation mode")
        }
    }

    // MARK: - Mailto handling

    func testMailtoShowsEmailPicker() {
        let config = makeConfig(
            emailClients: [mail], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "mailto:test@example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(let entries, _, _, let isEmail, _, _, _) = decision {
            XCTAssertTrue(isEmail)
            XCTAssertEqual(entries.count, 1)
        } else {
            XCTFail("Mailto in always mode should show email picker")
        }
    }

    func testMailtoNoClientsUsesSystem() {
        let config = makeConfig(emailClients: [], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "mailto:test@example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemMailHandler = decision {} else {
            XCTFail("Mailto with no clients should use system mail handler")
        }
    }

    func testImportedFinickyCatchAllDoesNotCaptureMailto() {
        let rule = Rule(
            name: "Imported Finicky catch-all",
            matchType: .all,
            pattern: "",
            targetBundleId: "com.google.Chrome",
            targetAppName: "Chrome",
            metadata: [
                "importedFrom": "finicky",
                "finickyWebOnly": "true",
            ])
        let config = makeConfig(
            browsers: [chrome],
            emailClients: [mail],
            rules: [rule],
            activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "mailto:test@example.com")!,
            origin: .defaultHandler)

        let decision = RoutingService.decide(request: request, configuration: config)

        guard case .showPicker(let entries, _, let finalURL, let isEmail, _, _, _) = decision else {
            return XCTFail("The mail flow should handle mailto links")
        }
        XCTAssertEqual(entries.map(\.bundleIdentifier), ["com.apple.mail"])
        XCTAssertEqual(finalURL.absoluteString, "mailto:test@example.com")
        XCTAssertTrue(isEmail)
    }

    func testImportedFinickyGlobalRewriteDoesNotChangeMailto() {
        let rewrite = URLRewriteRule(
            name: "Imported Finicky rewrite",
            matchPattern: "mailto:test@example.com",
            replacement: "https://wrong.example",
            metadata: [
                "importedFrom": "finicky",
                "finickyWebOnly": "true",
            ])
        let config = makeConfig(
            emailClients: [mail],
            activationMode: .always,
            globalRewriteRules: [rewrite])
        let request = IncomingLinkRequest(
            url: URL(string: "mailto:test@example.com")!,
            origin: .defaultHandler)

        let decision = RoutingService.decide(request: request, configuration: config)

        guard case .showPicker(_, _, let finalURL, let isEmail, _, _, _) = decision else {
            return XCTFail("The mail flow should handle mailto links")
        }
        XCTAssertEqual(finalURL.absoluteString, "mailto:test@example.com")
        XCTAssertTrue(isEmail)
    }

    // MARK: - Tel handling

    func testTelShowsPhonePicker() {
        let config = makeConfig(
            phoneClients: [faceTime], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "tel:+15551234567")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(
            let entries, _, let finalURL, let isEmail, _, _, _
        ) = decision {
            XCTAssertFalse(isEmail)
            XCTAssertEqual(finalURL.scheme, "tel")
            XCTAssertEqual(entries.first?.bundleIdentifier, "com.apple.FaceTime")
        } else {
            XCTFail("tel: in always mode should show phone picker")
        }
    }

    func testTelNoClientsUsesSystemPhoneHandler() {
        let config = makeConfig(phoneClients: [], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "tel:+15551234567")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemPhoneHandler = decision {} else {
            XCTFail("tel: with no clients should use system phone handler")
        }
    }

    func testTelIgnoresBroadAllURLsBrowserRule() {
        let broadRule = Rule(
            name: "All URLs", matchType: .all, pattern: "",
            targetBundleId: "org.mozilla.firefox", targetAppName: "Firefox")
        let config = makeConfig(
            browsers: [firefox],
            phoneClients: [faceTime],
            rules: [broadRule],
            activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "tel:+15551234567")!, origin: .defaultHandler)

        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(
            let entries, _, let finalURL, let isEmail, _, _, _
        ) = decision {
            XCTAssertFalse(isEmail)
            XCTAssertEqual(finalURL.scheme, "tel")
            XCTAssertEqual(entries.map(\.bundleIdentifier), ["com.apple.FaceTime"])
        } else {
            XCTFail("tel: should use phone clients, not broad browser rules")
        }
    }

    func testTelIgnoresForcedBrowserOverride() {
        let config = makeConfig(
            browsers: [firefox],
            phoneClients: [faceTime],
            activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "tel:+15551234567")!,
            origin: .urlScheme,
            forcedBrowserBundleId: "org.mozilla.firefox")

        let decision = RoutingService.decide(request: request, configuration: config)
        if case .showPicker(
            let entries, _, let finalURL, let isEmail, _, _, _
        ) = decision {
            XCTAssertFalse(isEmail)
            XCTAssertEqual(finalURL.scheme, "tel")
            XCTAssertEqual(entries.map(\.bundleIdentifier), ["com.apple.FaceTime"])
        } else {
            XCTFail("tel: should ignore browser overrides and use phone clients")
        }
    }

    func testDisabledRoutingWithTelUsesSystemPhoneHandler() {
        let config = makeConfig(phoneClients: [faceTime], isEnabled: false)
        let request = IncomingLinkRequest(
            url: URL(string: "tel:+15551234567")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemPhoneHandler = decision {} else {
            XCTFail("Disabled routing with tel: should use system phone handler")
        }
    }

    // MARK: - Empty browsers

    func testEmptyBrowsersFallsToSystemDefault() {
        let config = makeConfig(browsers: [], activationMode: .always)
        let request = IncomingLinkRequest(
            url: URL(string: "https://example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemDefault = decision {} else {
            XCTFail("No browsers should fall back to system default")
        }
    }

    // MARK: - URL sanitization

    func testInvalidSchemeRejected() {
        let config = makeConfig(browsers: [chrome])
        let request = IncomingLinkRequest(
            url: URL(string: "ftp://example.com")!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemDefault = decision {} else {
            XCTFail("FTP scheme should be rejected to system default")
        }
    }

    func testOverlongURLRejected() {
        let config = makeConfig(browsers: [chrome])
        let longURL = "https://example.com/" + String(repeating: "a", count: 33000)
        let request = IncomingLinkRequest(
            url: URL(string: longURL)!, origin: .defaultHandler)
        let decision = RoutingService.decide(request: request, configuration: config)
        if case .openSystemDefault = decision {} else {
            XCTFail("Overlong URL should be rejected to system default")
        }
    }

    // MARK: - RouteDecisionPreview

    func testPreviewFromOpenDirect() {
        let entry = chrome
        let decision = RouteDecision.openDirect(
            browser: entry, finalURL: URL(string: "https://example.com")!,
            privateWindow: false, reason: "Test rule")
        let preview = RouteDecisionPreview.from(decision)
        XCTAssertEqual(preview.kind, .openDirect)
        XCTAssertEqual(preview.targetBundleId, "com.google.Chrome")
        XCTAssertTrue(preview.summary.contains("Chrome"))
    }

    func testPreviewFromShowPicker() {
        let decision = RouteDecision.showPicker(
            entries: [chrome, firefox], preselectedIndex: 0,
            finalURL: URL(string: "https://example.com")!,
            isEmail: false, reason: nil)
        let preview = RouteDecisionPreview.from(decision)
        XCTAssertEqual(preview.kind, .showPicker)
        XCTAssertEqual(preview.pickerCandidates?.count, 2)
        XCTAssertEqual(preview.preselectedDisplayName, "Chrome")
    }

    func testPreviewFromSystemPhoneHandler() {
        let decision = RouteDecision.openSystemPhoneHandler(
            URL(string: "tel:+15551234567")!)
        let preview = RouteDecisionPreview.from(decision)
        XCTAssertEqual(preview.kind, .openSystemPhoneHandler)
        XCTAssertTrue(preview.isPhone)
        XCTAssertFalse(preview.isEmail)
    }

    // MARK: - RoutingSnapshotLoader

    func testSnapshotLoaderReturnsConfigFromEmptyDefaults() {
        let store = SharedRoutingStore()
        let hostKey = SharedRoutingStore.Keys.shortlinkResolutionHosts
        let modeKey = SharedRoutingStore.Keys.shortlinkResolutionMode
        let oldHosts = store.defaults.object(forKey: hostKey)
        let oldMode = store.defaults.object(forKey: modeKey)
        defer {
            if let oldHosts { store.defaults.set(oldHosts, forKey: hostKey) }
            else { store.defaults.removeObject(forKey: hostKey) }
            if let oldMode { store.defaults.set(oldMode, forKey: modeKey) }
            else { store.defaults.removeObject(forKey: modeKey) }
        }
        store.defaults.removeObject(forKey: hostKey)
        store.defaults.removeObject(forKey: modeKey)
        let config = RoutingSnapshotLoader.loadConfiguration(from: store)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.activationMode, .always)
        XCTAssertEqual(config?.isEnabled, true)
        XCTAssertEqual(config?.shortlinkResolutionEnabled, false)
        XCTAssertEqual(config?.shortlinkResolutionHosts, ShortlinkResolver.defaultShortenerHosts)
        XCTAssertEqual(config?.shortlinkResolutionMode, .exactHostHTTPAndHTTPS)
    }
}
