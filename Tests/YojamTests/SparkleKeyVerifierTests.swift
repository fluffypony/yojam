#if SWIFT_PACKAGE
import CryptoKit
import Foundation
import XCTest

final class SparkleKeyVerifierTests: XCTestCase {
    func testVerifierAcceptsMatchingKeyAndRejectsDifferentPublicKey() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("yojam-sparkle-key-\(UUID().uuidString)")
        try privateKey.rawRepresentation.base64EncodedString()
            .write(to: keyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: keyFile) }

        XCTAssertEqual(
            try runVerifier(
                keyFile: keyFile,
                expectedPublicKey: privateKey.publicKey.rawRepresentation.base64EncodedString()),
            0)

        let differentPublicKey = Curve25519.Signing.PrivateKey()
            .publicKey.rawRepresentation.base64EncodedString()
        XCTAssertNotEqual(
            try runVerifier(keyFile: keyFile, expectedPublicKey: differentPublicKey),
            0)
    }

    private func runVerifier(keyFile: URL, expectedPublicKey: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swift",
            repositoryRoot.appendingPathComponent("scripts/verify-sparkle-key.swift").path,
            keyFile.path,
            expectedPublicKey,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testReleaseScriptChecksExplicitKeyAndExportedVersion() throws {
        let releaseScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8)

        XCTAssertTrue(releaseScript.contains("verify-sparkle-key.swift"))
        XCTAssertTrue(releaseScript.contains("EXPORTED_MARKETING_VERSION"))
        XCTAssertTrue(releaseScript.contains("EXPORTED_BUILD_NUMBER"))
    }

    func testReleaseScriptSignsDMGBeforeNotarization() throws {
        let releaseScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8)
        let signingStep = try XCTUnwrap(
            releaseScript.range(of: "# ---- Sign DMG ----"))
        let notarizationStep = try XCTUnwrap(
            releaseScript.range(of: "# ---- Notarize ----"))

        XCTAssertLessThan(signingStep.lowerBound, notarizationStep.lowerBound)
        XCTAssertTrue(releaseScript.contains("codesign --force --timestamp"))
        XCTAssertTrue(releaseScript.contains("context:primary-signature"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
#endif
