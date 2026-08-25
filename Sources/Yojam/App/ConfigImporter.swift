import AppKit
import Foundation
import YojamCore

/// Detects installed link-routing apps and statically imports the parts of
/// their configurations that Yojam can represent exactly.
enum ConfigImporter {
    enum Source: String, CaseIterable, Identifiable, Sendable {
        case bumpr, choosy, finicky
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .bumpr:   "Bumpr"
            case .choosy:  "Choosy"
            case .finicky: "Finicky"
            }
        }
    }

    struct ImportResult: Sendable {
        var rules: [Rule]
        var rewriteRules: [URLRewriteRule]
        var warnings: [String]
        var source: Source
        var finickyShortlinkPolicy: FinickyShortlinkPolicy?

        init(
            rules: [Rule],
            rewriteRules: [URLRewriteRule] = [],
            warnings: [String],
            source: Source,
            finickyShortlinkPolicy: FinickyShortlinkPolicy? = nil
        ) {
            self.rules = rules
            self.rewriteRules = rewriteRules
            self.warnings = warnings
            self.source = source
            self.finickyShortlinkPolicy = finickyShortlinkPolicy
        }

        var itemCount: Int { rules.count + rewriteRules.count }
    }

    // MARK: - Detection

    /// Detect which of the supported sources are installed on this Mac
    /// *without* reading their config files.
    ///
    /// Why LaunchServices instead of `FileManager.fileExists`: touching paths
    /// under `~/Library/Containers/<other-app>/` (Bumpr's sandbox) triggers
    /// the macOS `TCC_SERVICE_SYSTEM_POLICY_APP_DATA` prompt. This is the
    /// "would like to access data from other apps" dialog. It appears on each launch
    /// with a changed code signature (Debug builds, ad-hoc signed). The
    /// actual plist reads happen in `importFrom(_:)`, which is only invoked
    /// when the user explicitly opens the Import sheet; the prompt there is
    /// in-context and one-shot.
    @MainActor
    static func detectAvailable(
        applicationURL: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    ) -> [Source] {
        var available: [Source] = []

        let bumprBundleIds = [
            "com.letsgo.Handler",
        ]
        if bumprBundleIds.contains(where: { applicationURL($0) != nil }) {
            available.append(.bumpr)
        }

        if applicationURL("com.choosyosx.Choosy") != nil {
            available.append(.choosy)
        }

        let finickyBundleIds = [
            "se.johnste.finicky",
            "net.kassett.finicky",
            "net.kassett.Finicky",
        ]
        if finickyBundleIds.contains(where: { applicationURL($0) != nil }) {
            available.append(.finicky)
        }

        return available
    }

    // MARK: - Import

    static func importFrom(_ source: Source) -> ImportResult {
        switch source {
        case .bumpr:   return importBumpr()
        case .choosy:  return importChoosy()
        case .finicky: return importFinicky(detectRuntimeOptions: true)
        }
    }

    static func importBumpr(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ImportResult {
        let url = BumprConfigPaths.preferencesURL(homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ImportResult(rules: [], warnings: ["Could not find Bumpr preferences on disk."], source: .bumpr)
        }

        let parsed = BumprConfigParser().parsePreferences(at: url)
        return ImportResult(
            rules: parsed.rules,
            warnings: parsed.warnings,
            source: .bumpr)
    }

    static func importChoosy(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ImportResult {
        guard let url = ChoosyConfigParser.sourcePaths(homeDirectory: homeDirectory)
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return ImportResult(
                rules: [],
                warnings: ["Could not find Choosy behaviours.plist on disk."],
                source: .choosy)
        }

        do {
            let parsed = ChoosyConfigParser.parse(data: try Data(contentsOf: url))
            return ImportResult(
                rules: parsed.rules,
                warnings: parsed.warnings,
                source: .choosy)
        } catch {
            return ImportResult(
                rules: [],
                warnings: ["Could not read Choosy behaviours.plist: \(error.localizedDescription)"],
                source: .choosy)
        }
    }

    static func importFinicky(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        currentAppInstalled: Bool? = nil,
        legacyBookmarkData: Data? = nil,
        runtimeOptions: FinickyRuntimeOptions? = nil,
        detectRuntimeOptions: Bool = false
    ) -> ImportResult {
        let parser = FinickyConfigParser()
        var rules: [Rule] = []
        var rewrites: [URLRewriteRule] = []
        var warnings: [String] = []
        var javaScriptPipelineIsComplete = true
        var shortlinkPolicy: FinickyShortlinkPolicy?

        let currentBundleIdentifier = "se.johnste.finicky"
        let legacyBundleIdentifiers = [
            "net.kassett.finicky",
            "net.kassett.Finicky",
        ]
        let runtimeDetection = runtimeOptions == nil && detectRuntimeOptions
            ? FinickyRuntimeOptions.detectRunning(bundleIdentifiers: [
                currentBundleIdentifier,
            ] + legacyBundleIdentifiers)
            : nil
        let hasCurrentApp = currentAppInstalled ?? (
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: currentBundleIdentifier) != nil)
        let selectedBundleIdentifier = runtimeDetection?.bundleIdentifier
            ?? (hasCurrentApp
                ? currentBundleIdentifier
                : legacyBundleIdentifiers.first(where: {
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
                }))
        let version: FinickyConfigVersion = selectedBundleIdentifier == currentBundleIdentifier
            ? .v4
            : .v3
        let selectedAppVersion = runtimeDetection?.appVersion
            ?? selectedBundleIdentifier.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }.flatMap(FinickyRuntimeOptions.applicationVersion(at:))
        let bookmarkData = legacyBookmarkData ?? UserDefaults(
            suiteName: FinickyConfigPaths.legacyBundleIdentifier
        )?.data(forKey: FinickyConfigPaths.legacyBookmarkKey)
        let effectiveRuntimeOptions = runtimeOptions ?? runtimeDetection?.options
        let configURL: URL?
        if effectiveRuntimeOptions?.skipsJavaScriptConfig == true {
            configURL = nil
            warnings.append(
                "Finicky is running with --no-config. Its JavaScript configuration was not imported.")
        } else if effectiveRuntimeOptions?.configPath != nil {
            configURL = effectiveRuntimeOptions?.configURL(homeDirectory: homeDirectory)
            if configURL == nil {
                javaScriptPipelineIsComplete = false
                warnings.append(
                    "Finicky uses a relative --config path that Yojam cannot locate safely.")
            }
        } else {
            configURL = FinickyConfigPaths.preferredConfigURL(
                homeDirectory: homeDirectory,
                version: version,
                appVersion: selectedAppVersion,
                legacyBookmarkData: bookmarkData)
        }

        var foundConfiguration = false
        if let configURL {
            foundConfiguration = true
            do {
                let source = try String(contentsOf: configURL, encoding: .utf8)
                let parsed = parser.parse(source, version: version)
                rules.append(contentsOf: parsed.rules)
                rewrites.append(contentsOf: parsed.globalRewrites)
                warnings.append(contentsOf: parsed.warningMessages)
                shortlinkPolicy = parsed.shortlinkPolicy
                javaScriptPipelineIsComplete = parsed.handlerPipelineIsComplete
                    && parsed.rewritePipelineIsComplete
            } catch {
                javaScriptPipelineIsComplete = false
                warnings.append(
                    "Could not read Finicky configuration at \(configURL.path): "
                        + error.localizedDescription)
            }
        }

        // Finicky 3 has no declarative rules.json pipeline. A stale Finicky 4
        // file must not change a legacy import or its short-link policy.
        if version == .v3 {
            if !foundConfiguration {
                warnings.append("Could not find a Finicky configuration on disk.")
            }
            return ImportResult(
                rules: rules,
                rewriteRules: rewrites,
                warnings: warnings,
                source: .finicky,
                finickyShortlinkPolicy: shortlinkPolicy)
        }

        let rulesURL: URL
        if effectiveRuntimeOptions?.rulesPath != nil {
            if let customRulesURL = effectiveRuntimeOptions?.rulesURL(homeDirectory: homeDirectory) {
                rulesURL = customRulesURL
            } else {
                warnings.append(
                    "Finicky uses a relative --rules path that Yojam cannot locate safely.")
                for index in rules.indices {
                    rules[index].metadata?["importRequiresReview"] = "true"
                }
                for index in rewrites.indices {
                    rewrites[index].metadata?["importRequiresReview"] = "true"
                }
                return ImportResult(
                    rules: rules,
                    rewriteRules: rewrites,
                    warnings: warnings,
                    source: .finicky,
                    finickyShortlinkPolicy: shortlinkPolicy)
            }
        } else {
            rulesURL = FinickyConfigPaths.rulesJSONURL(homeDirectory: homeDirectory)
        }
        if FileManager.default.fileExists(atPath: rulesURL.path) {
            foundConfiguration = true
            do {
                var parsed = parser.parseRulesJSON(try Data(contentsOf: rulesURL))
                if version == .v4, !javaScriptPipelineIsComplete, !parsed.rules.isEmpty {
                    for ruleIndex in parsed.rules.indices {
                        parsed.rules[ruleIndex].metadata?["importRequiresReview"] = "true"
                    }
                    warnings.append(
                        "Finicky rules.json routes follow a skipped or partly imported "
                            + "JavaScript handler or rewrite. Review and select them manually.")
                }
                // Finicky 4 evaluates JavaScript handlers before rules.json handlers.
                // Keep that order when the two sources are combined.
                rules.append(contentsOf: parsed.rules)
                rewrites.append(contentsOf: parsed.globalRewrites)
                warnings.append(contentsOf: parsed.warningMessages)
                if version == .v4 {
                    shortlinkPolicy = parsed.shortlinkPolicy
                }
            } catch {
                if effectiveRuntimeOptions?.rulesPath != nil {
                    warnings.append(
                        "Could not read Finicky's explicit --rules file at \(rulesURL.path): "
                            + error.localizedDescription)
                } else {
                    warnings.append(
                        "Could not read Finicky rules.json: \(error.localizedDescription)")
                }
            }
        } else if effectiveRuntimeOptions?.rulesPath != nil {
            warnings.append(
                "Could not find Finicky's explicit --rules file at \(rulesURL.path).")
        }

        if !foundConfiguration {
            warnings.append("Could not find a Finicky configuration on disk.")
        }

        return ImportResult(
            rules: rules,
            rewriteRules: rewrites,
            warnings: warnings,
            source: .finicky,
            finickyShortlinkPolicy: shortlinkPolicy)
    }
}
