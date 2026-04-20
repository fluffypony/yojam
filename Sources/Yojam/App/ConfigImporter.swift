import Foundation
import YojamCore

/// Detects and imports rules from other link-routing apps already installed
/// on this Mac. Supported sources:
///   • Bumpr   (plist under ~/Library/Containers/…/Bumpr.plist)
///   • Choosy  (plist under ~/Library/Preferences/com.choosyosx.Choosy.plist)
///   • Finicky (~/.finicky.js — JS config, parsed best-effort)
///
/// Parsers are intentionally conservative: anything we can't map cleanly gets
/// appended to `warnings` instead of silently dropped.
enum ConfigImporter {
    enum Source: String, CaseIterable, Identifiable {
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

    struct ImportResult {
        var rules: [Rule]
        var warnings: [String]
        var source: Source
    }

    // MARK: - Detection

    static func detectAvailable() -> [Source] {
        var available: [Source] = []
        let home = FileManager.default.homeDirectoryForCurrentUser

        let bumprPaths = [
            "Library/Containers/com.nickvdh.Bumpr/Data/Library/Preferences/com.nickvdh.Bumpr.plist",
            "Library/Containers/com.tenseventeen.Bumpr/Data/Library/Preferences/com.tenseventeen.Bumpr.plist",
            "Library/Containers/com.nicholaspsmith.Bumpr/Data/Library/Preferences/com.nicholaspsmith.Bumpr.plist",
            "Library/Preferences/com.nickvdh.Bumpr.plist",
        ]
        if bumprPaths.contains(where: { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }) {
            available.append(.bumpr)
        }

        let choosyPref = home.appendingPathComponent("Library/Preferences/com.choosyosx.Choosy.plist")
        if FileManager.default.fileExists(atPath: choosyPref.path) {
            available.append(.choosy)
        }

        let finickyJS = home.appendingPathComponent(".finicky.js")
        if FileManager.default.fileExists(atPath: finickyJS.path) {
            available.append(.finicky)
        }

        return available
    }

    // MARK: - Import

    static func importFrom(_ source: Source) -> ImportResult {
        switch source {
        case .bumpr:   return importBumpr()
        case .choosy:  return importChoosy()
        case .finicky: return importFinicky()
        }
    }

    private static func importBumpr() -> ImportResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = [
            "Library/Containers/com.nickvdh.Bumpr/Data/Library/Preferences/com.nickvdh.Bumpr.plist",
            "Library/Containers/com.tenseventeen.Bumpr/Data/Library/Preferences/com.tenseventeen.Bumpr.plist",
            "Library/Containers/com.nicholaspsmith.Bumpr/Data/Library/Preferences/com.nicholaspsmith.Bumpr.plist",
            "Library/Preferences/com.nickvdh.Bumpr.plist",
        ]
        guard let url = paths.lazy
            .map({ home.appendingPathComponent($0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else {
            return ImportResult(rules: [], warnings: ["Could not find Bumpr preferences on disk."], source: .bumpr)
        }

        var rules: [Rule] = []
        var warnings: [String] = []

        guard let plist = NSDictionary(contentsOf: url) else {
            return ImportResult(rules: [], warnings: ["Could not read Bumpr preferences."], source: .bumpr)
        }

        // Bumpr's rule storage key has varied across versions. We look for
        // common array-of-dict candidates under known top-level keys.
        let candidates = ["rules", "Rules", "BPRules", "behaviors", "Behaviors"]
        var matched: [[String: Any]] = []
        for key in candidates {
            if let arr = plist[key] as? [[String: Any]] {
                matched = arr; break
            }
        }
        if matched.isEmpty {
            warnings.append("Bumpr file found but no recognized rule array. Format may have changed.")
        }

        for dict in matched {
            let name = (dict["name"] as? String) ?? (dict["title"] as? String) ?? "Imported"
            let pattern = (dict["pattern"] as? String) ?? (dict["domain"] as? String) ?? ""
            let bundleId = (dict["bundleIdentifier"] as? String) ?? (dict["bundleId"] as? String) ?? ""
            let appName = (dict["appName"] as? String) ?? (dict["displayName"] as? String) ?? ""
            guard !pattern.isEmpty, !bundleId.isEmpty else {
                warnings.append("Skipping entry without pattern or bundle ID.")
                continue
            }
            rules.append(Rule(
                name: name,
                matchType: pattern.contains("*") ? .urlContains : .domainSuffix,
                pattern: pattern.replacingOccurrences(of: "*", with: ""),
                targetBundleId: bundleId,
                targetAppName: appName,
                isBuiltIn: false,
                priority: 200,
                metadata: ["importedFrom": Source.bumpr.rawValue]))
        }

        return ImportResult(rules: rules, warnings: warnings, source: .bumpr)
    }

    private static func importChoosy() -> ImportResult {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.choosyosx.Choosy.plist")
        guard let plist = NSDictionary(contentsOf: path) else {
            return ImportResult(rules: [], warnings: ["Could not read Choosy preferences."], source: .choosy)
        }
        var rules: [Rule] = []
        var warnings: [String] = []

        // Choosy stores behaviors under "behaviors" or "rules".
        let arr = (plist["behaviors"] as? [[String: Any]])
            ?? (plist["rules"] as? [[String: Any]]) ?? []
        if arr.isEmpty {
            warnings.append("Choosy file found but no behaviors array present.")
        }

        for dict in arr {
            let name = (dict["name"] as? String) ?? "Imported"
            let pattern = (dict["urlPattern"] as? String)
                ?? (dict["pattern"] as? String)
                ?? (dict["host"] as? String) ?? ""
            let bundleId = (dict["bundleIdentifier"] as? String)
                ?? ((dict["handler"] as? [String: Any])?["bundleIdentifier"] as? String) ?? ""
            let appName = (dict["appName"] as? String) ?? ""
            guard !pattern.isEmpty, !bundleId.isEmpty else {
                warnings.append("Skipping Choosy entry without pattern/bundleId.")
                continue
            }
            rules.append(Rule(
                name: name,
                matchType: .domainSuffix,
                pattern: pattern,
                targetBundleId: bundleId,
                targetAppName: appName,
                isBuiltIn: false,
                priority: 200,
                metadata: ["importedFrom": Source.choosy.rawValue]))
        }

        return ImportResult(rules: rules, warnings: warnings, source: .choosy)
    }

    private static func importFinicky() -> ImportResult {
        // Finicky uses JavaScript; we cannot fully evaluate arbitrary JS here.
        // Strategy: regex-match the `handlers` array for match strings and app
        // names. Report anything we can't parse cleanly.
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".finicky.js")
        guard let js = try? String(contentsOf: path, encoding: .utf8) else {
            return ImportResult(rules: [], warnings: ["Could not read ~/.finicky.js."], source: .finicky)
        }
        var rules: [Rule] = []
        var warnings: [String] = []

        // Very conservative heuristic parser: look for `match: "domain"` / `browser: "App Name"` pairs.
        let pattern = #"match\s*:\s*["']([^"']+)["'][\s,]*browser\s*:\s*["']([^"']+)["']"#
        if let re = try? NSRegularExpression(pattern: pattern, options: []) {
            let ns = js as NSString
            let matches = re.matches(in: js, range: NSRange(location: 0, length: ns.length))
            for m in matches where m.numberOfRanges >= 3 {
                let matchStr = ns.substring(with: m.range(at: 1))
                let browser = ns.substring(with: m.range(at: 2))
                rules.append(Rule(
                    name: "Finicky: \(matchStr)",
                    matchType: .urlContains,
                    pattern: matchStr,
                    targetBundleId: browser,
                    targetAppName: browser,
                    isBuiltIn: false,
                    priority: 200,
                    metadata: ["importedFrom": Source.finicky.rawValue,
                               "note": "Target may be a display name rather than bundle ID"]))
            }
        }

        if rules.isEmpty {
            warnings.append("Could not auto-parse Finicky handlers. Only string-literal match/browser pairs are supported; function-valued handlers require manual migration.")
        } else {
            warnings.append("Finicky import is best-effort. Review each rule's target app — values may be display names rather than bundle IDs.")
        }

        return ImportResult(rules: rules, warnings: warnings, source: .finicky)
    }
}
