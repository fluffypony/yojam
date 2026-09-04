import XCTest
@testable import Yojam

final class UpdateCenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func status(
        update: UpdateCenter.AvailableUpdate? = nil,
        isChecking: Bool = false,
        failed: Bool = false,
        lastCheck: Date? = nil
    ) -> String {
        UpdateCenter.statusText(
            installedVersion: "1.2.4",
            installedBuild: "14",
            availableUpdate: update,
            isChecking: isChecking,
            lastCheckFailed: failed,
            lastCheckDate: lastCheck,
            now: now)
    }

    func testCheckingWinsOverEverythingElse() {
        let text = status(
            update: .init(version: "1.2.5", build: "15"),
            isChecking: true,
            failed: true,
            lastCheck: now)
        XCTAssertEqual(text, "Checking yoj.am for a new version\u{2026}")
    }

    func testAvailableUpdateNamesBothVersions() {
        let text = status(update: .init(version: "1.2.5", build: "15"), lastCheck: now)
        XCTAssertEqual(text, "Yojam 1.2.5 is ready to install. You have 1.2.4.")
    }

    func testNeverCheckedShowsVersionOnly() {
        XCTAssertEqual(status(), "Version 1.2.4 (14) \u{00B7} Not checked yet")
    }

    func testFailedCheckIsReportedWithoutBlame() {
        XCTAssertEqual(
            status(failed: true, lastCheck: now),
            "Version 1.2.4 (14) \u{00B7} Couldn't reach yoj.am on the last check")
    }

    func testRecentCheckReadsAsJustNow() {
        XCTAssertEqual(
            status(lastCheck: now.addingTimeInterval(-20)),
            "Version 1.2.4 (14) \u{00B7} Last checked just now")
    }

    func testOlderCheckUsesRelativeTime() {
        let text = status(lastCheck: now.addingTimeInterval(-3 * 3600))
        XCTAssertTrue(text.hasPrefix("Version 1.2.4 (14) \u{00B7} Last checked "), text)
        XCTAssertTrue(text.contains("3 hours ago"), text)
    }

    func testVersionCanBeLeftOutWhereItIsAlreadyShown() {
        let text = UpdateCenter.statusText(
            installedVersion: "1.2.4", installedBuild: "14",
            availableUpdate: nil, isChecking: false, lastCheckFailed: false,
            lastCheckDate: now.addingTimeInterval(-20), now: now, includesVersion: false)
        XCTAssertEqual(text, "Last checked just now")
        let never = UpdateCenter.statusText(
            installedVersion: "1.2.4", installedBuild: "14",
            availableUpdate: nil, isChecking: false, lastCheckFailed: false,
            lastCheckDate: nil, now: now, includesVersion: false)
        XCTAssertEqual(never, "Not checked yet")
    }
}
