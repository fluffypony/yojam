import AppKit
import XCTest
@testable import Yojam

final class AppDelegateWindowTests: XCTestCase {
    @MainActor
    func testPreferencesWindowCandidateMatchesExplicitIdentifier() {
        XCTAssertTrue(AppDelegate.isPreferencesWindowCandidate(
            identifier: AppDelegate.settingsWindowIdentifier,
            title: "Anything",
            isPanel: false))
    }

    @MainActor
    func testPreferencesWindowCandidateRejectsPanels() {
        XCTAssertFalse(AppDelegate.isPreferencesWindowCandidate(
            identifier: AppDelegate.settingsWindowIdentifier,
            title: "Yojam Settings",
            isPanel: true))
    }

    @MainActor
    func testPreferencesWindowCandidateMatchesSwiftUISettingsTitles() {
        XCTAssertTrue(AppDelegate.isPreferencesWindowCandidate(
            identifier: nil,
            title: "Yojam Settings",
            isPanel: false))
        XCTAssertTrue(AppDelegate.isPreferencesWindowCandidate(
            identifier: nil,
            title: "Preferences",
            isPanel: false))
    }
}
