import AppKit
import XCTest
@testable import Yojam

final class PickerPanelLinkSourceQuitTests: XCTestCase {
    private func runningAppProcessIdentifier() throws -> pid_t {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != own && !$0.isTerminated
        }) else { throw XCTSkip("No other running app to use as a link source") }
        return app.processIdentifier
    }

    private func startCommandLineProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        return process
    }

    func testRecordsSenderThatIsARunningApp() throws {
        let pid = try runningAppProcessIdentifier()
        XCTAssertEqual(SourceAppResolver.appProcessIdentifier(pid), pid)
    }

    func testIgnoresSenderThatIsACommandLineProcess() throws {
        let process = try startCommandLineProcess()
        defer { process.terminate() }
        XCTAssertNil(SourceAppResolver.appProcessIdentifier(process.processIdentifier))
    }

    func testRunningLinkSourceAppHasNotQuit() throws {
        let pid = try runningAppProcessIdentifier()
        XCTAssertFalse(PickerPanel.linkSourceAppHasQuit(processIdentifier: pid))
    }

    func testLinkSourceAppThatIsGoneHasQuit() throws {
        let process = try startCommandLineProcess()
        process.terminate()
        process.waitUntilExit()
        XCTAssertTrue(PickerPanel.linkSourceAppHasQuit(processIdentifier: process.processIdentifier))
    }

    func testUnknownLinkSourceNeverCountsAsQuit() {
        XCTAssertFalse(PickerPanel.linkSourceAppHasQuit(processIdentifier: nil))
    }

    private let quitAt = Date(timeIntervalSinceReferenceDate: 1_000)

    func testKeepsPickerWhenAnotherAppActivatesRightAfterLinkSourceQuit() {
        XCTAssertTrue(PickerPanel.shouldKeepAfterOtherAppActivated(
            linkSourceQuitAt: quitAt, otherAppActivatedAt: quitAt.addingTimeInterval(0.045),
            hasKeptAfterLinkSourceQuit: false))
    }

    func testKeepsPickerWhenQuitIsReportedJustAfterTheActivation() {
        XCTAssertTrue(PickerPanel.shouldKeepAfterOtherAppActivated(
            linkSourceQuitAt: quitAt, otherAppActivatedAt: quitAt.addingTimeInterval(-0.1),
            hasKeptAfterLinkSourceQuit: false))
    }

    func testDismissesPickerWhenLinkSourceIsStillRunning() {
        XCTAssertFalse(PickerPanel.shouldKeepAfterOtherAppActivated(
            linkSourceQuitAt: nil, otherAppActivatedAt: quitAt,
            hasKeptAfterLinkSourceQuit: false))
    }

    func testDismissesPickerOnUserSwitchLongAfterLinkSourceQuit() {
        XCTAssertFalse(PickerPanel.shouldKeepAfterOtherAppActivated(
            linkSourceQuitAt: quitAt,
            otherAppActivatedAt: quitAt.addingTimeInterval(PickerPanel.linkSourceQuitActivationTolerance),
            hasKeptAfterLinkSourceQuit: false))
    }

    func testDismissesPickerOnActivationAfterItWasKeptOnce() {
        XCTAssertFalse(PickerPanel.shouldKeepAfterOtherAppActivated(
            linkSourceQuitAt: quitAt, otherAppActivatedAt: quitAt.addingTimeInterval(0.045),
            hasKeptAfterLinkSourceQuit: true))
    }

    func testCountsSenderQuitBeforePickerShowedWhenLinkJustArrived() {
        XCTAssertTrue(PickerPanel.linkSourceQuitBeforeShowCounts(
            linkReceivedAt: quitAt, shownAt: quitAt.addingTimeInterval(0.03)))
    }

    func testIgnoresSenderQuitBeforeADelayedPickerShowed() {
        XCTAssertFalse(PickerPanel.linkSourceQuitBeforeShowCounts(
            linkReceivedAt: quitAt, shownAt: quitAt.addingTimeInterval(2)))
    }
}
