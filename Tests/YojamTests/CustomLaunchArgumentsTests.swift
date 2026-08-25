import XCTest
@testable import Yojam

final class CustomLaunchArgumentsTests: XCTestCase {
    @MainActor
    func testCustomLaunchArgsAppendURLWhenTemplateOmitsPlaceholder() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--profile \"$HOME/Library/Application Support/Firefox/Profiles/abc123.Profile 1\"",
            url: url,
            profile: nil,
            bundleId: "org.mozilla.firefox",
            privateWindow: false)

        XCTAssertEqual(args.last, url.absoluteString)
        XCTAssertEqual(args[0], "--profile")
        XCTAssertTrue(args[1].hasSuffix(
            "/Library/Application Support/Firefox/Profiles/abc123.Profile 1"))
    }

    @MainActor
    func testCustomLaunchArgsDoNotAppendURLWhenTemplateContainsPlaceholder() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--new-window $URL",
            url: url,
            profile: nil,
            bundleId: "org.mozilla.firefox",
            privateWindow: false)

        XCTAssertEqual(args, ["--new-window", url.absoluteString])
    }

    @MainActor
    func testArgumentLaunchUsesOpenForNewAppInstance() {
        let appURL = URL(fileURLWithPath: "/Applications/Chromium.app")
        let invocation = AppDelegate.argumentLaunchInvocation(
            appURL: appURL,
            arguments: ["--user-data-dir=/tmp/temporary1", "https://example.com"],
            openAsNewInstance: true)

        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/open")
        XCTAssertEqual(invocation.arguments, [
            "-n",
            "-a",
            "/Applications/Chromium.app",
            "--args",
            "--user-data-dir=/tmp/temporary1",
            "https://example.com",
        ])
    }

    func testColdAppBundleUsesWorkspaceArgumentLaunch() {
        XCTAssertTrue(AppDelegate.shouldUseWorkspaceArgumentLaunch(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isRunning: false,
            openAsNewInstance: false))
    }

    func testRunningAppBundleKeepsDirectArgumentForwarding() {
        XCTAssertFalse(AppDelegate.shouldUseWorkspaceArgumentLaunch(
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isRunning: true,
            openAsNewInstance: false))
    }

    func testBareExecutableKeepsDirectArgumentLaunch() {
        XCTAssertFalse(AppDelegate.shouldUseWorkspaceArgumentLaunch(
            appURL: URL(fileURLWithPath: "/opt/browser/bin/browser"),
            isRunning: false,
            openAsNewInstance: false))
    }

    @MainActor
    func testCustomLaunchArgsIncludeConfiguredUserDataDirectoryBeforeAppendedURL() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--new-window",
            url: url,
            profile: "Profile 2",
            bundleId: "org.chromium.Chromium",
            privateWindow: false,
            userDataDirectory: "/tmp/chromium-state")

        XCTAssertEqual(args, [
            "--new-window",
            "--user-data-dir=/tmp/chromium-state",
            "--profile-directory=Profile 2",
            url.absoluteString,
        ])
    }

    @MainActor
    func testFinickyProfileArgumentsPrecedeExactCustomArguments() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "--app=$URL",
            url: url,
            profile: "Profile 2",
            bundleId: "com.google.Chrome",
            privateWindow: false,
            appendURLIfMissing: false,
            usesFinickyArgumentSemantics: true)

        XCTAssertEqual(args, [
            "--profile-directory=Profile 2",
            "--app=\(url.absoluteString)",
        ])
    }

    @MainActor
    func testFinickyArgumentsDoNotExpandShellHomeTokens() {
        let url = URL(string: "https://example.com/path")!
        let args = AppDelegate.customLaunchArguments(
            template: "$HOME ~/literal",
            url: url,
            profile: nil,
            bundleId: nil,
            privateWindow: false,
            appendURLIfMissing: false,
            usesFinickyArgumentSemantics: true)

        XCTAssertEqual(args, ["$HOME", "~/literal"])
    }

    func testExactFinickyActionKeepsExplicitPrivateRequest() {
        XCTAssertTrue(AppDelegate.effectivePrivateWindow(
            exactFinickyAction: true,
            rulePrivateWindow: false,
            routedPrivateWindow: true,
            forcePrivateWindow: true))
    }

    func testExactFinickyActionBypassesBrowserPrivateSetting() {
        XCTAssertFalse(AppDelegate.effectivePrivateWindow(
            exactFinickyAction: true,
            rulePrivateWindow: false,
            routedPrivateWindow: true,
            forcePrivateWindow: false))
    }

    func testExactFinickyActionKeepsRulePrivateSetting() {
        XCTAssertTrue(AppDelegate.effectivePrivateWindow(
            exactFinickyAction: true,
            rulePrivateWindow: true,
            routedPrivateWindow: false,
            forcePrivateWindow: false))
    }

    func testStandardActionKeepsExistingPrivatePrecedence() {
        XCTAssertFalse(AppDelegate.effectivePrivateWindow(
            exactFinickyAction: false,
            rulePrivateWindow: false,
            routedPrivateWindow: true,
            forcePrivateWindow: true))
    }
}
