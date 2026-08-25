import AppKit
import Foundation
import YojamCore

struct BumprParseResult {
    var rules: [Rule] = []
    var warnings: [String] = []
}

enum BumprConfigPaths {
    static let bundleIdentifier = "com.letsgo.Handler"

    static func preferencesURL(homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(
            "Library/Containers/com.letsgo.Handler/Data/Library/Preferences/com.letsgo.Handler.plist"
        )
    }
}

protocol BumprApplicationNameResolving {
    func displayName(forBundleIdentifier bundleIdentifier: String) -> String?
}

struct WorkspaceBumprApplicationNameResolver: BumprApplicationNameResolving {
    func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }

        let bundle = Bundle(url: appURL)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
    }
}

struct BumprConfigParser {
    private let applicationNameResolver: any BumprApplicationNameResolving

    init(
        applicationNameResolver: any BumprApplicationNameResolving =
            WorkspaceBumprApplicationNameResolver()
    ) {
        self.applicationNameResolver = applicationNameResolver
    }

    func parsePreferences(at url: URL) -> BumprParseResult {
        do {
            return parsePreferencesData(try Data(contentsOf: url))
        } catch {
            return BumprParseResult(
                warnings: ["Could not read Bumpr preferences: \(error.localizedDescription)"]
            )
        }
    }

    func parsePreferencesData(_ data: Data) -> BumprParseResult {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            return BumprParseResult(
                warnings: ["Could not decode Bumpr preferences: \(error.localizedDescription)"]
            )
        }

        guard let preferences = propertyList as? [String: Any] else {
            return BumprParseResult(warnings: ["Bumpr preferences have an invalid root value."])
        }
        guard let archive = preferences["CustomRules"] else {
            return BumprParseResult(warnings: ["Bumpr preferences contain no custom rules."])
        }
        guard let archiveData = archive as? Data else {
            return BumprParseResult(warnings: ["Bumpr's CustomRules value is not valid data."])
        }
        return parseCustomRulesArchive(archiveData)
    }

    func parseCustomRulesArchive(_ data: Data) -> BumprParseResult {
        let archivedRules: [BumprArchivedRule]
        do {
            archivedRules = try Self.decodeArchive(data)
        } catch {
            return BumprParseResult(
                warnings: ["Could not decode Bumpr custom rules: \(error.localizedDescription)"]
            )
        }

        var result = BumprParseResult()
        for archivedRule in archivedRules {
            let identifier = archivedRule.identifier?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let domain = archivedRule.domain?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let handlerBundleIdentifier = archivedRule.handlerIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if identifier == "TutorialRule" {
                result.warnings.append(
                    "Skipped Bumpr's built-in sample rule for \(domain.isEmpty ? "an unknown domain" : domain)."
                )
                continue
            }
            guard !domain.isEmpty else {
                let ruleLabel = identifier.isEmpty ? "with no identifier" : identifier
                result.warnings.append(
                    "Skipped Bumpr rule \(ruleLabel) because it has no domain."
                )
                continue
            }
            guard let normalizedDomain = Self.normalizedHostname(domain) else {
                let ruleLabel = identifier.isEmpty ? "with no identifier" : identifier
                result.warnings.append(
                    "Skipped Bumpr rule \(ruleLabel) because its domain is not a valid hostname."
                )
                continue
            }
            guard !handlerBundleIdentifier.isEmpty else {
                result.warnings.append(
                    "Skipped Bumpr rule for \(domain) because it has no browser bundle ID."
                )
                continue
            }
            guard Self.isValidBundleIdentifier(handlerBundleIdentifier) else {
                result.warnings.append(
                    "Skipped Bumpr rule for \(normalizedDomain) because its browser bundle ID is invalid."
                )
                continue
            }

            let appName = applicationNameResolver.displayName(
                forBundleIdentifier: handlerBundleIdentifier
            )
            if appName == nil {
                result.warnings.append(
                    "Could not find \(handlerBundleIdentifier) on this Mac. "
                        + "The rule for \(normalizedDomain) keeps that bundle ID."
                )
            }

            var metadata = [
                "importedFrom": "bumpr",
                "bumprUseCount": String(archivedRule.useCount),
            ]
            if !identifier.isEmpty {
                metadata["bumprRuleId"] = identifier
            }

            result.rules.append(Rule(
                name: "Bumpr: \(normalizedDomain)",
                enabled: archivedRule.enabled,
                matchType: .regex,
                pattern: Self.hostSuffixPattern(normalizedDomain),
                targetBundleId: handlerBundleIdentifier,
                targetAppName: appName ?? handlerBundleIdentifier,
                isBuiltIn: false,
                priority: 200,
                metadata: metadata
            ))
        }

        return result
    }

    private static func normalizedHostname(_ value: String) -> String? {
        var hostname = value.lowercased()
        if hostname.hasSuffix(".") {
            hostname.removeLast()
        }
        guard !hostname.isEmpty, hostname.utf8.count <= 253 else { return nil }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }) else { return nil }
        return hostname
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
            }
        }
    }

    /// Bumpr 1.4.5 tests `URL.host.hasSuffix(rule.domain)`. It does not
    /// require a DNS label boundary before the saved domain.
    private static func hostSuffixPattern(_ domain: String) -> String {
        let literal = NSRegularExpression.escapedPattern(for: domain)
        return #"\A[A-Za-z][A-Za-z0-9+.-]*://(?:[^/?#@]*@)?[^/?#:@]*(?-i:\#(literal))(?::[0-9]+)?(?:[/?#]|\z)"#
    }

    private static func decodeArchive(_ data: Data) throws -> [BumprArchivedRule] {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(
            BumprArchivedRuleSet.self,
            forClassName: "Bumpr.CustomRuleSet"
        )
        unarchiver.setClass(
            BumprArchivedRule.self,
            forClassName: "Bumpr.CustomRule"
        )
        defer { unarchiver.finishDecoding() }

        let allowedClasses: [AnyClass] = [
            BumprArchivedRuleSet.self,
            BumprArchivedRule.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
        ]
        let root = unarchiver.decodeObject(
            of: allowedClasses,
            forKey: NSKeyedArchiveRootObjectKey
        ) as? BumprArchivedRuleSet

        if let error = unarchiver.error {
            throw error
        }
        guard let root else {
            throw BumprArchiveError.invalidRoot
        }
        return root.rules
    }
}

private enum BumprArchiveError: LocalizedError {
    case invalidRoot

    var errorDescription: String? {
        "The CustomRules archive has an invalid root object."
    }
}

@objc(YojamBumprArchivedRuleSet)
private final class BumprArchivedRuleSet: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let rules: [BumprArchivedRule]

    required init?(coder: NSCoder) {
        rules = coder.decodeObject(
            of: [NSArray.self, BumprArchivedRule.self],
            forKey: "rules"
        ) as? [BumprArchivedRule] ?? []
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(rules, forKey: "rules")
    }
}

@objc(YojamBumprArchivedRule)
private final class BumprArchivedRule: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let identifier: String?
    let domain: String?
    let handlerIdentifier: String?
    let enabled: Bool
    let useCount: Int

    required init?(coder: NSCoder) {
        identifier = coder.decodeObject(of: NSString.self, forKey: "id") as String?
        domain = coder.decodeObject(of: NSString.self, forKey: "domain") as String?
        handlerIdentifier = coder.decodeObject(
            of: NSString.self,
            forKey: "handlerId"
        ) as String?
        enabled = !coder.containsValue(forKey: "enabled")
            || coder.decodeBool(forKey: "enabled")
        useCount = coder.decodeInteger(forKey: "useCount")
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(identifier, forKey: "id")
        coder.encode(domain, forKey: "domain")
        coder.encode(handlerIdentifier, forKey: "handlerId")
        coder.encode(enabled, forKey: "enabled")
        coder.encode(useCount, forKey: "useCount")
    }
}
