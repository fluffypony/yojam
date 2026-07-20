import Foundation
import XCTest

final class ContainerBridgeScriptTests: XCTestCase {
    func testContainerFailureNeverNavigatesBridgeTabToUncontainedTarget() throws {
        let script = try backgroundScript()
        let resourceDirectory = try extensionResourceDirectory()

        XCTAssertFalse(
            script.contains("chrome.tabs.update(d.tabId, { url: target })"),
            "A failed container open must not fall back to the browser's default context")
        XCTAssertTrue(script.contains("showContainerError(d.tabId)"))
        XCTAssertTrue(script.contains("chrome.runtime.getURL(\"container-error.html\")"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resourceDirectory
                .appendingPathComponent("container-error.html").path))
    }

    func testContainerDestinationTabIsGuardedBeforeTargetNavigation() throws {
        let script = try backgroundScript()
        let blankFirst = try XCTUnwrap(script.range(of: "url: \"about:blank\""))
        let loopGuard = try XCTUnwrap(
            script.range(of: "routedTabs.set(containerTabId", range: blankFirst.upperBound..<script.endIndex))
        let targetNavigation = try XCTUnwrap(
            script.range(
                of: "browser.tabs.update(containerTabId, { url })",
                range: loopGuard.upperBound..<script.endIndex))

        XCTAssertLessThan(blankFirst.lowerBound, loopGuard.lowerBound)
        XCTAssertLessThan(loopGuard.lowerBound, targetNavigation.lowerBound)
    }

    private func extensionResourceDirectory() throws -> URL {
#if SWIFT_PACKAGE
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Extensions/shared")
#else
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionURL = plugInsURL.appendingPathComponent("YojamSafariExtension.appex")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: extensionURL.path),
            "YojamSafariExtension.appex is not embedded in Yojam.app")
        return extensionURL.appendingPathComponent("Contents/Resources")
#endif
    }

    private func backgroundScript() throws -> String {
        try String(
            contentsOf: try extensionResourceDirectory().appendingPathComponent("background.js"),
            encoding: .utf8)
    }
}
