import XCTest
@testable import Yojam

final class ServicesMenuRegistrationTests: XCTestCase {
    private let dump = """
    (
            {
            NSBundleIdentifier = "com.example.other";
            NSBundlePath = "/Applications/Other.app";
            NSMenuItem =         {
                default = "Do Other";
            };
            NSMessage = doOther;
            NSPortName = Other;
        },
            {
            NSBundleIdentifier = "com.yojam.app";
            NSBundlePath = "/Volumes/Storage/working/yojam/build/test/Yojam.app";
            NSKeyEquivalent =         {
            };
            NSMenuItem =         {
                default = "Open in Yojam";
            };
            NSMessage = openURLViaService;
            NSPortName = Yojam;
            NSSendTypes =         (
                "public.url",
                "public.plain-text"
            );
        },
            {
            NSBundleIdentifier = "com.yojam.app";
            NSBundlePath = "/Applications/Yojam.app";
            NSMessage = openURLViaService;
            NSPortName = Yojam;
        }
    )
    """

    func testFindsEveryPathRegisteredForYojam() {
        let paths = ServicesMenuRegistration.registeredBundlePaths(
            inDump: dump, bundleIdentifier: "com.yojam.app")
        XCTAssertEqual(paths, [
            "/Volumes/Storage/working/yojam/build/test/Yojam.app",
            "/Applications/Yojam.app",
        ])
    }

    func testIgnoresOtherApps() {
        let paths = ServicesMenuRegistration.registeredBundlePaths(
            inDump: dump, bundleIdentifier: "com.example.missing")
        XCTAssertTrue(paths.isEmpty)
    }

    func testHandlesUnquotedValues() {
        let unquoted = """
            {
            NSBundleIdentifier = com.yojam.app;
            NSBundlePath = /Applications/Yojam.app;
        }
        """
        XCTAssertEqual(
            ServicesMenuRegistration.registeredBundlePaths(
                inDump: unquoted, bundleIdentifier: "com.yojam.app"),
            ["/Applications/Yojam.app"])
    }

    func testStatusIsRegisteredWhenAnyEntryPointsAtThisBundle() {
        let status = ServicesMenuRegistration.status(
            forRegisteredPaths: ["/Users/me/Downloads/Yojam.app", "/Applications/Yojam.app"],
            currentBundlePath: "/Applications/Yojam.app/")
        XCTAssertEqual(status, .registered)
    }

    func testStatusReportsStaleCopy() {
        let status = ServicesMenuRegistration.status(
            forRegisteredPaths: ["/Users/me/Downloads/Yojam.app"],
            currentBundlePath: "/Applications/Yojam.app")
        XCTAssertEqual(status, .registeredElsewhere(path: "/Users/me/Downloads/Yojam.app"))
    }

    func testStatusReportsMissingEntry() {
        let status = ServicesMenuRegistration.status(
            forRegisteredPaths: [], currentBundlePath: "/Applications/Yojam.app")
        XCTAssertEqual(status, .notRegistered)
    }

    func testInstallationKeyChangesWithLocationAndVersion() {
        let key = ServicesMenuRegistration.installationKey
        XCTAssertTrue(key.hasPrefix(Bundle.main.bundleURL.path + "|"))
        XCTAssertEqual(key.split(separator: "|").count, 3)
    }
}
