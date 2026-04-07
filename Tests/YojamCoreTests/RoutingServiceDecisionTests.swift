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
        rules: [Rule] = [],
        activationMode: ActivationMode = .always,
        defaultSelection: DefaultSelectionBehavior = .alwaysFirst,
        isEnabled: Bool = true,
        globalUTMStripping: Bool = false,
        utmParams: Set<String> = []
    ) -> RoutingConfiguration {
        RoutingConfiguration(
            browsers: browsers, emailClients: emailClients,
            rules: rules, globalRewriteRules: [],
            utmStripParameters: utmParams,
            globalUTMStrippingEnabled: globalUTMStripping,
            activationMode: activationMode,
            defaultSelectionBehavior: defaultSelection,
            isEnabled: isEnabled,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil,
            shortlinkResolutionEnabled: false
        )
    }

    private let chrome = BrowserEntry(
        bundleIdentifier: "com.google.Chrome", displayName: "Chrome")
    private let firefox = BrowserEntry(
        bundleIdentifier: "org.mozilla.firefox", displayName: "Firefox")
    private let mail = BrowserEntry(
        bundleIdentifier: "com.apple.mail", displayName: "Mail")

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
        if case .showPicker(let entries, _, _, _, _) = decision {
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
        if case .openDirect(let browser, _, _, let reason) = decision {
            XCTAssertEqual(browser.bundleIdentifier, "us.zoom.xos")
            XCTAssert(reason.contains("Zoom"))
        } else {
            XCTFail("Domain rule should match and open directly in smartFallback mode")
        }
    }

    func testSourceAppFilterSkipsNonMatchingSource() {
        var rule = Rule(
            name: "Work", matchType: .domain, pattern: "example.com",
            targetBundleId: "com.google.Chrome", targetAppName: "Chrome")
        rule.sourceAppBundleId = SourceAppSentinel.safariExtension
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
        if case .openDirect(let browser, _, _, let reason) = decision {
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
        if case .showPicker(let entries, _, _, let isEmail, _) = decision {
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

    // MARK: - RoutingSnapshotLoader

    func testSnapshotLoaderReturnsConfigFromEmptyDefaults() {
        let store = SharedRoutingStore()
        let config = RoutingSnapshotLoader.loadConfiguration(from: store)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.activationMode, .always)
        XCTAssertEqual(config?.isEnabled, true)
        XCTAssertEqual(config?.shortlinkResolutionEnabled, false)
    }
}
