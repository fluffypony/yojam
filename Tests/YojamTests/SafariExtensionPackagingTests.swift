import Foundation
import XCTest

final class SafariExtensionPackagingTests: XCTestCase {
    func testSafariExtensionInfoPlistDeclaresWebExtensionPoint() throws {
#if SWIFT_PACKAGE
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlist = repositoryRoot
            .appendingPathComponent("Sources/YojamSafariExtension/Info.plist")
#else
        let infoPlist = try embeddedSafariExtensionURL()
            .appendingPathComponent("Contents/Info.plist")
#endif
        let data = try Data(contentsOf: infoPlist)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
        let extensionDeclaration = try XCTUnwrap(plist["NSExtension"] as? [String: Any])

        XCTAssertEqual(
            extensionDeclaration["NSExtensionPointIdentifier"] as? String,
            "com.apple.Safari.web-extension")
#if SWIFT_PACKAGE
        XCTAssertEqual(
            extensionDeclaration["NSExtensionPrincipalClass"] as? String,
            "$(PRODUCT_MODULE_NAME).SafariWebExtensionHandler")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
#else
        XCTAssertEqual(
            extensionDeclaration["NSExtensionPrincipalClass"] as? String,
            "YojamSafariExtension.SafariWebExtensionHandler")
        XCTAssertEqual(
            plist["CFBundleShortVersionString"] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(
            plist["CFBundleVersion"] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
#endif
    }

    func testSafariExtensionBuildCopiesAllWebExtensionResourcesIntoProduct() throws {
#if SWIFT_PACKAGE
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectSpecURL = repositoryRoot.appendingPathComponent("project.yml")
        let projectSpec = try String(contentsOf: projectSpecURL, encoding: .utf8)

        XCTAssertTrue(projectSpec.contains(
            "RESOURCE_DIR=\"${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}\""))
        XCTAssertTrue(projectSpec.contains(
            "rsync -av --delete \"${SRCROOT}/Extensions/shared/\" \"${RESOURCE_DIR}/\""))
        XCTAssertTrue(projectSpec.contains(
            "\"${SRCROOT}/Extensions/safari/manifest.json\" \"${RESOURCE_DIR}/manifest.json\""))

        let requiredSharedResources = [
            "background.js", "container-error.html", "yojam-bridge.js",
            "popup.html", "popup.js", "options.html", "options.js",
            "_locales/en/messages.json",
            "icons/16.png", "icons/48.png", "icons/128.png",
        ]
        for resource in requiredSharedResources {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: repositoryRoot
                        .appendingPathComponent("Extensions/shared/\(resource)").path),
                "Missing shared Safari Web Extension resource: \(resource)")
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent(
                "Extensions/safari/manifest.json").path))

        for browser in ["chrome", "firefox", "safari"] {
            let manifestURL = repositoryRoot.appendingPathComponent(
                "Extensions/\(browser)/manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try XCTUnwrap(
                JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let version = try XCTUnwrap(manifest["version"] as? String)
            XCTAssertTrue(
                projectSpec.contains("MARKETING_VERSION: \"\(version)\""),
                "\(browser) extension version does not match the app")
        }
#else
        let resourcesURL = try embeddedSafariExtensionURL()
            .appendingPathComponent("Contents/Resources")
        let requiredResources = [
            "manifest.json", "background.js", "container-error.html",
            "yojam-bridge.js", "popup.html", "popup.js", "options.html",
            "options.js", "_locales/en/messages.json",
            "icons/16.png", "icons/48.png", "icons/128.png",
        ]
        for resource in requiredResources {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: resourcesURL.appendingPathComponent(resource).path),
                "Missing built Safari Web Extension resource: \(resource)")
        }
        let manifestData = try Data(contentsOf: resourcesURL.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(
            manifest["version"] as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
#endif
    }

#if !SWIFT_PACKAGE
    private func embeddedSafariExtensionURL() throws -> URL {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionURL = plugInsURL.appendingPathComponent("YojamSafariExtension.appex")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: extensionURL.path),
            "YojamSafariExtension.appex is not embedded in Yojam.app")
        return extensionURL
    }
#endif
}
