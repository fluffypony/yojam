import AppKit
import Foundation
import YojamCore

struct FinickyParseResult: Equatable {
    var rules: [Rule] = []
    var globalRewrites: [URLRewriteRule] = []
    var warnings: [FinickyImportWarning] = []
    var handlerPipelineIsComplete = true
    var rewritePipelineIsComplete = true
    var shortlinkPolicy: FinickyShortlinkPolicy = .replace(
        hosts: ShortlinkResolver.finickyV4ShortenerHosts,
        mode: .domainSuffixHTTPAndHTTPS)

    var warningMessages: [String] {
        warnings.map(\.description)
    }
}

enum FinickyShortlinkPolicy: Equatable, Sendable {
    case replace(hosts: Set<String>, mode: ShortlinkResolutionMode)
    /// The configuration requires JavaScript execution to determine its list.
    case unknownDynamic
}

struct FinickyImportWarning: Equatable, Sendable, CustomStringConvertible {
    enum Code: String, Equatable, Sendable {
        case syntax
        case unsupported
        case invalid
        case unresolvedApplication
        case unresolvedProfile
    }

    let code: Code
    let message: String
    let line: Int?
    let column: Int?

    init(code: Code, message: String, line: Int? = nil, column: Int? = nil) {
        self.code = code
        self.message = message
        self.line = line
        self.column = column
    }

    var description: String {
        if let line, let column {
            return "Line \(line), column \(column): \(message)"
        }
        if let line {
            return "Line \(line): \(message)"
        }
        return message
    }
}

enum FinickyConfigVersion: Equatable, Sendable {
    case v3
    case v4
}

enum FinickyApplicationKind: String, Sendable {
    case automatic
    case appName
    case bundleId
    case path
}

struct FinickyApplicationReference: Equatable, Sendable {
    var value: String
    var kind: FinickyApplicationKind
}

struct FinickyResolvedApplication: Equatable, Sendable {
    var bundleIdentifier: String
    var displayName: String
}

protocol FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication?
}

protocol FinickyProfileResolving {
    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)?
}

final class WorkspaceFinickyApplicationResolver: FinickyApplicationResolving {
    private static let knownBundleIdentifiers: [String: String] = [
        "Brave Browser": "com.brave.Browser",
        "Brave Browser Beta": "com.brave.Browser.beta",
        "Brave Browser Dev": "com.brave.Browser.dev",
        "Google Chrome": "com.google.Chrome",
        "Google Chrome Beta": "com.google.Chrome.beta",
        "Google Chrome Canary": "com.google.Chrome.canary",
        "Chromium": "org.chromium.Chromium",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Microsoft Edge Beta": "com.microsoft.edgemac.Beta",
        "Vivaldi": "com.vivaldi.Vivaldi",
        "Wavebox": "com.bookry.wavebox",
        "Helium": "net.imput.helium",
        "Comet": "ai.perplexity.comet",
        "Yandex": "ru.yandex.desktop.yandex-browser",
        "Opera": "com.operasoftware.Opera",
        "Opera GX": "com.operasoftware.OperaGX",
        "Safari": "com.apple.Safari",
        "Firefox": "org.mozilla.firefox",
        "Firefox Developer Edition": "org.mozilla.firefoxdeveloperedition",
        "Zen": "app.zen-browser.zen",
    ]

    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        let kind = reference.kind == .automatic
            ? Self.detectedKind(for: reference.value, version: version)
            : reference.kind

        switch kind {
        case .bundleId:
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: reference.value),
               let resolved = Self.resolvedApplication(at: appURL) {
                return resolved
            }
            guard Self.isValidBundleIdentifier(reference.value, version: version) else {
                return nil
            }
            return FinickyResolvedApplication(
                bundleIdentifier: reference.value,
                displayName: reference.value)

        case .path:
            let path = NSString(string: reference.value).expandingTildeInPath
            return Self.resolvedApplication(at: URL(fileURLWithPath: path))

        case .appName:
            if let knownID = Self.knownBundleIdentifiers[reference.value] {
                if let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: knownID),
                   let resolved = Self.resolvedApplication(at: appURL) {
                    return resolved
                }
                return FinickyResolvedApplication(
                    bundleIdentifier: knownID,
                    displayName: reference.value)
            }

            let webURL = URL(string: "https://example.com")!
            for appURL in NSWorkspace.shared.urlsForApplications(toOpen: webURL) {
                guard let resolved = Self.resolvedApplication(at: appURL) else { continue }
                let fileName = appURL.deletingPathExtension().lastPathComponent
                if resolved.displayName.caseInsensitiveCompare(reference.value) == .orderedSame
                    || fileName.caseInsensitiveCompare(reference.value) == .orderedSame {
                    return resolved
                }
            }

            let home = FileManager.default.homeDirectoryForCurrentUser
            for base in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
                let candidate = base.appendingPathComponent(reference.value).appendingPathExtension("app")
                if let resolved = Self.resolvedApplication(at: candidate) {
                    return resolved
                }
            }
            return nil

        case .automatic:
            return nil
        }
    }

    private static func detectedKind(
        for value: String,
        version: FinickyConfigVersion
    ) -> FinickyApplicationKind {
        switch version {
        case .v4:
            if value.range(
                of: #"^[A-Za-z0-9 ]+$"#,
                options: .regularExpression) != nil {
                return .appName
            }
            if value.range(
                of: #"^[A-Za-z0-9.-]+$"#,
                options: .regularExpression) != nil {
                return .bundleId
            }
            if value.range(
                of: #"^(~?(?:/[^/\n]+)+/[^/\n]+\.app)$"#,
                options: .regularExpression) != nil {
                return .path
            }
            return .appName
        case .v3:
            if Self.isValidBundleIdentifier(value, version: .v3) {
                return .bundleId
            }
            if value.hasPrefix("/") || value.hasPrefix("~") {
                return .path
            }
            return .appName
        }
    }

    private static func resolvedApplication(at url: URL) -> FinickyResolvedApplication? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return FinickyResolvedApplication(bundleIdentifier: bundleID, displayName: name)
    }

    private static func isValidBundleIdentifier(
        _ value: String,
        version: FinickyConfigVersion
    ) -> Bool {
        let pattern = version == .v4
            ? #"^[A-Za-z0-9.-]+$"#
            : #"^[A-Za-z]{2,6}((?!-)\.[A-Za-z0-9-]{1,63})+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

final class LocalFinickyProfileResolver: FinickyProfileResolving {
    private let discovery: ProfileDiscovery

    init(discovery: ProfileDiscovery = ProfileDiscovery()) {
        self.discovery = discovery
    }

    func resolveProfile(
        named name: String,
        browserBundleIdentifier: String,
        version: FinickyConfigVersion
    ) -> (id: String, name: String)? {
        let profiles = discovery.discoverProfiles(for: browserBundleIdentifier)
        let profile: BrowserProfile?
        switch version {
        case .v3:
            profile = profiles.first { $0.id == name }
        case .v4:
            profile = profiles.first { $0.name == name }
                ?? profiles.first { $0.id == name }
        }
        return profile.map { (id: $0.id, name: $0.name) }
    }
}

enum FinickyConfigPaths {
    static let legacyBundleIdentifier = "net.kassett.finicky"
    static let legacyBookmarkKey = "config_location_bookmark"

    static let stableRelativePaths = [
        ".finicky.js",
        ".finicky.ts",
        ".config/finicky.js",
        ".config/finicky.ts",
        ".config/finicky/finicky.js",
        ".config/finicky/finicky.ts",
    ]

    static func stableConfigURLs(homeDirectory: URL) -> [URL] {
        stableRelativePaths.map { homeDirectory.appendingPathComponent($0) }
    }

    static func firstStableConfigURL(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        stableConfigURLs(homeDirectory: homeDirectory).first {
            fileManager.fileExists(atPath: $0.path)
        }?.resolvingSymlinksInPath()
    }

    static func preferredConfigURL(
        homeDirectory: URL,
        version: FinickyConfigVersion,
        appVersion: String? = nil,
        legacyBookmarkData: Data? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        switch version {
        case .v4:
            return cachedCustomConfigURL(
                homeDirectory: homeDirectory,
                appVersion: appVersion,
                fileManager: fileManager)
                ?? firstStableConfigURL(
                    homeDirectory: homeDirectory,
                    fileManager: fileManager)
        case .v3:
            return legacyBookmarkConfigURL(
                bookmarkData: legacyBookmarkData,
                fileManager: fileManager)
                ?? legacyDefaultConfigURL(
                    homeDirectory: homeDirectory,
                    fileManager: fileManager)
        }
    }

    static func legacyDefaultConfigURL(
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let url = homeDirectory.appendingPathComponent(".finicky.js")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url.resolvingSymlinksInPath()
    }

    /// Finicky 4 records the selected JS or TypeScript file in its newest
    /// config cache record. This also covers a path supplied with `--config`.
    static func cachedCustomConfigURL(
        homeDirectory: URL,
        appVersion: String? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let cacheDirectory = homeDirectory.appendingPathComponent(
            "Library/Caches/Finicky",
            isDirectory: true)
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else {
            return nil
        }

        let ordered = candidates
            .filter {
                $0.lastPathComponent.hasPrefix("config_cache_")
                    && $0.pathExtension == "json"
            }
            .sorted {
                let lhs = (try? $0.resourceValues(
                    forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(
                    forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }

        for cacheURL in ordered {
            guard let data = try? Data(contentsOf: cacheURL),
                  let record = try? JSONDecoder().decode(
                    FinickyConfigCacheRecord.self,
                    from: data),
                  !record.configPath.isEmpty,
                  appVersion == nil || record.appVersion == appVersion else {
                continue
            }
            let configURL = URL(fileURLWithPath: record.configPath)
                .standardizedFileURL
            if fileManager.fileExists(atPath: configURL.path) {
                return configURL.resolvingSymlinksInPath()
            }
        }
        return nil
    }

    static func legacyBookmarkConfigURL(
        bookmarkData: Data?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let bookmarkData else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url.resolvingSymlinksInPath()
    }

    static func rulesJSONURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(
            "Library/Application Support/Finicky/rules.json"
        )
    }
}

private struct FinickyConfigCacheRecord: Decodable {
    let configPath: String
    let appVersion: String?
}
