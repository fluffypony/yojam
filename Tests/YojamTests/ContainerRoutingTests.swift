import XCTest
@testable import Yojam
import YojamCore

final class ContainerRoutingTests: XCTestCase {
    private let target = URL(string: "https://example.com/a path?q=one&next=two")!

    func testOrionContainerRoutingUsesWebExtensionBridge() throws {
        let routed = AppDelegate.containerRoutedURL(
            target: target,
            container: "Work & Personal",
            browserBundleId: "com.kagi.kagimacOS")

        try assertContainerBridge(
            routed,
            container: "Work & Personal",
            target: target)
    }

    func testOrionRCContainerRoutingUsesWebExtensionBridgeAndKnownBrowserAllowlist() throws {
        let bundleId = "com.kagi.kagimacOS.RC"

        XCTAssertTrue(AppDelegate.supportsContainerRouting(browserBundleId: bundleId))
        XCTAssertTrue(KnownAppAllowlist.browsers.contains(bundleId))

        let routed = AppDelegate.containerRoutedURL(
            target: target,
            container: "Release Candidate",
            browserBundleId: bundleId)

        try assertContainerBridge(
            routed,
            container: "Release Candidate",
            target: target)
    }

    func testFirefoxContainerRoutingStillUsesWebExtensionBridge() throws {
        let firefoxBundleIds = [
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "org.mozilla.nightly",
        ]

        for bundleId in firefoxBundleIds {
            let routed = AppDelegate.containerRoutedURL(
                target: target,
                container: "Banking",
                browserBundleId: bundleId)

            try assertContainerBridge(routed, container: "Banking", target: target)
        }
    }

    func testContainerRoutingLeavesUnsupportedBrowsersUnchanged() {
        let routed = AppDelegate.containerRoutedURL(
            target: target,
            container: "Work",
            browserBundleId: "com.google.Chrome")

        XCTAssertEqual(routed, target)
    }

    func testContainerRoutingLeavesURLUnchangedWithoutContainerName() {
        for container in [nil, ""] as [String?] {
            let routed = AppDelegate.containerRoutedURL(
                target: target,
                container: container,
                browserBundleId: "com.kagi.kagimacOS")

            XCTAssertEqual(routed, target)
        }
    }

    func testGloballyRewrittenRuleCarriesContainerIntoDirectExecution() throws {
        let orion = BrowserEntry(
            bundleIdentifier: "com.kagi.kagimacOS",
            displayName: "Orion")
        let rule = Rule(
            name: "Rewritten work host",
            matchType: .domain,
            pattern: "container.example",
            targetBundleId: orion.bundleIdentifier,
            targetAppName: orion.displayName,
            targetBrowserEntryId: orion.id,
            firefoxContainer: "Work")
        let rewrite = URLRewriteRule(
            name: "Resolve routing host",
            matchPattern: #"^https://go\.example/(.*)$"#,
            replacement: "https://container.example/$1")
        let originalURL = URL(string: "https://go.example/project")!
        let configuration = RoutingConfiguration(
            browsers: [orion],
            emailClients: [],
            rules: [rule],
            globalRewriteRules: [rewrite],
            utmStripParameters: [],
            globalUTMStrippingEnabled: false,
            activationMode: .always,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil)
        let request = IncomingLinkRequest(
            url: originalURL,
            origin: .defaultHandler)

        let decision = RoutingService.decide(
            request: request,
            configuration: configuration)

        guard case .openDirect(
            let browser,
            let finalURL,
            _,
            _,
            let matchedRule
        ) = decision else {
            return XCTFail("A rule matching the globally rewritten URL should open directly")
        }

        XCTAssertEqual(browser.id, orion.id)
        XCTAssertEqual(finalURL, URL(string: "https://container.example/project"))
        XCTAssertEqual(matchedRule?.id, rule.id)
        XCTAssertEqual(matchedRule?.firefoxContainer, "Work")

        let routed = AppDelegate.containerRoutedURL(
            target: finalURL,
            container: matchedRule?.firefoxContainer,
            browserBundleId: browser.bundleIdentifier)
        try assertContainerBridge(routed, container: "Work", target: finalURL)
    }

    func testShiftPickerSelectionBypassesBrowserRewritesAndUTMStripping() {
        let browserRewrite = URLRewriteRule(
            name: "Browser rewrite",
            matchPattern: #"^https://example\.com/(.*)$"#,
            replacement: "https://rewritten.example/$1")
        let browser = BrowserEntry(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Chrome",
            stripUTMParams: true,
            rewriteRules: [browserRewrite])
        let originalURL = URL(string: "https://example.com/path?utm_source=test")!
        let configuration = RoutingConfiguration(
            browsers: [browser],
            emailClients: [],
            rules: [],
            globalRewriteRules: [],
            utmStripParameters: ["utm_source"],
            globalUTMStrippingEnabled: true,
            activationMode: .always,
            defaultSelectionBehavior: .alwaysFirst,
            isEnabled: true,
            learnedDomainPreferences: [:],
            lastUsedBrowserId: nil,
            lastUsedEmailClientId: nil)
        let request = IncomingLinkRequest(
            url: originalURL,
            origin: .defaultHandler,
            modifierFlags: 1 << 17)

        let decision = RoutingService.decide(
            request: request,
            configuration: configuration)

        guard case .showPicker(
            let entries,
            _,
            let pickerURL,
            _,
            _,
            let matchedRule,
            let bypassTransformations
        ) = decision else {
            return XCTFail("Shift should show the picker")
        }

        XCTAssertEqual(entries, [browser])
        XCTAssertEqual(pickerURL, originalURL)
        XCTAssertNil(matchedRule)
        XCTAssertTrue(bypassTransformations)

        var appliedBrowserRewrite = false
        var strippedUTM = false
        let selectedURL = AppDelegate.pickerSelectionURL(
            target: pickerURL,
            browser: browser,
            isEmail: false,
            bypassTransformations: bypassTransformations,
            globalUTMStrippingEnabled: true,
            applyBrowserRewrites: { url, _ in
                appliedBrowserRewrite = true
                return URL(string: "https://unexpected.example") ?? url
            },
            stripUTM: { url in
                strippedUTM = true
                return url
            })

        XCTAssertEqual(selectedURL, originalURL)
        XCTAssertFalse(appliedBrowserRewrite)
        XCTAssertFalse(strippedUTM)
    }

    private func assertContainerBridge(
        _ url: URL,
        container: String,
        target: URL
    ) throws {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "yojam-container.invalid")
        XCTAssertEqual(components.path, "/open")
        XCTAssertEqual(query["c"], container)
        XCTAssertEqual(query["u"], target.absoluteString)
    }
}
