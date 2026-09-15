import Foundation
import WebURL
import YojamCore

final class FinickyConfigParser {
    private let applicationResolver: any FinickyApplicationResolving
    private let profileResolver: any FinickyProfileResolving
    private let babelParser: FinickyBabelParser

    init(
        applicationResolver: any FinickyApplicationResolving = WorkspaceFinickyApplicationResolver(),
        profileResolver: any FinickyProfileResolving = LocalFinickyProfileResolver(),
        babelParser: FinickyBabelParser = FinickyBabelParser()
    ) {
        self.applicationResolver = applicationResolver
        self.profileResolver = profileResolver
        self.babelParser = babelParser
    }

    func parse(
        _ source: String,
        version: FinickyConfigVersion = .v4
    ) -> FinickyParseResult {
        let defaultPolicy: FinickyShortlinkPolicy = version == .v3
            ? .replace(
                hosts: ShortlinkResolver.finickyV3ShortenerHosts,
                mode: .exactHostHTTPS)
            : .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS)
        do {
            let root = try babelParser.parse(source)
            return FinickyASTCompiler(
                root: root,
                version: version,
                applicationResolver: applicationResolver,
                profileResolver: profileResolver
            ).compile()
        } catch let error as FinickyBabelSyntaxError {
            return FinickyParseResult(
                warnings: [FinickyImportWarning(
                    code: .syntax,
                    message: error.message,
                    line: error.line,
                    column: error.column
                )],
                handlerPipelineIsComplete: false,
                rewritePipelineIsComplete: false,
                shortlinkPolicy: defaultPolicy)
        } catch {
            return FinickyParseResult(
                warnings: [FinickyImportWarning(
                    code: .syntax,
                    message: "Could not parse the Finicky configuration: \(error.localizedDescription)"
                )],
                handlerPipelineIsComplete: false,
                rewritePipelineIsComplete: false,
                shortlinkPolicy: defaultPolicy)
        }
    }

    /// Finicky 4.4 can save declarative rules in rules.json. Converting that
    /// JSON to a JavaScript object literal lets the same static compiler handle
    /// both formats. The generated source contains JSON only and is not run.
    func parseRulesJSON(_ data: Data) -> FinickyParseResult {
        do {
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return FinickyParseResult(
                    warnings: [FinickyImportWarning(
                        code: .invalid,
                        message: "Finicky rules.json does not contain an object."
                    )],
                    handlerPipelineIsComplete: false)
            }
            for key in ["defaultBrowser", "defaultProfile"] {
                if let value = object[key], !(value is String), !(value is NSNull) {
                    return FinickyParseResult(
                        warnings: [FinickyImportWarning(
                            code: .invalid,
                            message: "Finicky rules.json has a non-string \(key) value. Finicky rejects the file."
                        )],
                        handlerPipelineIsComplete: false)
                }
            }

            let rawRules: [Any]
            if object["rules"] == nil || object["rules"] is NSNull {
                rawRules = []
            } else if let values = object["rules"] as? [Any] {
                rawRules = values
            } else {
                return FinickyParseResult(
                    warnings: [FinickyImportWarning(
                        code: .invalid,
                        message: "Finicky rules.json has a rules value that is not an array."
                    )],
                    handlerPipelineIsComplete: false)
            }

            if object["options"] is NSNull {
                object.removeValue(forKey: "options")
            } else if let rawOptions = object["options"] {
                guard let options = rawOptions as? [String: Any] else {
                    return FinickyParseResult(
                        warnings: [FinickyImportWarning(
                            code: .invalid,
                            message: "Finicky rules.json has an options value that is not an object."
                        )],
                        handlerPipelineIsComplete: false)
                }
                var normalisedOptions: [String: Any] = [:]
                for key in ["keepRunning", "hideIcon", "logRequests", "checkForUpdates"] {
                    guard let value = options[key] else { continue }
                    if value is NSNull { continue }
                    guard value is Bool else {
                        return FinickyParseResult(
                            warnings: [FinickyImportWarning(
                                code: .invalid,
                                message: "Finicky rules.json has a non-boolean \(key) option. Finicky rejects the file."
                            )],
                            handlerPipelineIsComplete: false)
                    }
                    normalisedOptions[key] = value
                }
                object["options"] = normalisedOptions
            }

            var handlers: [[String: Any]] = []
            var fatalWarnings: [FinickyImportWarning] = []
            var skippedRowWarnings: [FinickyImportWarning] = []

            for (offset, value) in rawRules.enumerated() {
                let label = "Finicky rules.json rule \(offset + 1)"
                guard let raw = value as? [String: Any] else {
                    fatalWarnings.append(FinickyImportWarning(
                        code: .invalid,
                        message: "\(label) is not an object."
                    ))
                    continue
                }
                let matches: [String]
                if raw["match"] is NSNull {
                    matches = []
                } else if let match = raw["match"] as? String {
                    matches = [match]
                } else if raw["match"] == nil {
                    matches = []
                } else if let rawMatches = raw["match"] as? [Any] {
                    guard rawMatches.allSatisfy({ $0 is String }) else {
                        fatalWarnings.append(FinickyImportWarning(
                            code: .invalid,
                            message: "\(label) contains a non-string match value."
                        ))
                        continue
                    }
                    matches = rawMatches.compactMap { $0 as? String }
                } else {
                    fatalWarnings.append(FinickyImportWarning(
                        code: .invalid,
                        message: "\(label) has a match value that is not a string or string array."
                    ))
                    continue
                }
                let browser: String
                if raw["browser"] == nil || raw["browser"] is NSNull {
                    browser = ""
                } else if let value = raw["browser"] as? String {
                    browser = value
                } else {
                    fatalWarnings.append(FinickyImportWarning(
                        code: .invalid,
                        message: "\(label) has a browser value that is not a string."
                    ))
                    continue
                }
                let profile: String?
                if raw["profile"] == nil || raw["profile"] is NSNull {
                    profile = nil
                } else if let value = raw["profile"] as? String {
                    profile = value
                } else {
                    fatalWarnings.append(FinickyImportWarning(
                        code: .invalid,
                        message: "\(label) has a profile value that is not a string."
                    ))
                    continue
                }

                // Finicky's ToJSHandlers drops empty match strings, then skips
                // only the incomplete row if no match or browser remains.
                let usableMatches = matches.filter { !$0.isEmpty }
                guard !usableMatches.isEmpty, !browser.isEmpty else {
                    skippedRowWarnings.append(FinickyImportWarning(
                        code: .invalid,
                        message: "\(label) is incomplete and Finicky skips it."
                    ))
                    continue
                }
                let normalizedMatch: Any = usableMatches.count == 1
                    ? usableMatches[0]
                    : usableMatches

                var handler: [String: Any] = [
                    "match": normalizedMatch,
                    "browser": browser,
                ]
                if let profile, !profile.isEmpty {
                    handler["browser"] = ["name": browser, "profile": profile]
                }
                handlers.append(handler)
            }

            guard fatalWarnings.isEmpty else {
                fatalWarnings.append(FinickyImportWarning(
                    code: .invalid,
                    message: "Finicky rejected the rules.json file as one unit. No rules were imported."
                ))
                return FinickyParseResult(
                    warnings: fatalWarnings,
                    handlerPipelineIsComplete: false)
            }
            let defaultBrowser = object["defaultBrowser"] as? String ?? ""
            let defaultProfile = object["defaultProfile"] as? String ?? ""
            if defaultProfile.isEmpty {
                object["defaultBrowser"] = defaultBrowser.isEmpty
                    ? "com.apple.Safari"
                    : defaultBrowser
            } else {
                object["defaultBrowser"] = [
                    "name": defaultBrowser.isEmpty ? "com.apple.Safari" : defaultBrowser,
                    "profile": defaultProfile,
                ]
            }
            object["handlers"] = handlers
            object.removeValue(forKey: "rules")
            object.removeValue(forKey: "rewrite")
            object.removeValue(forKey: "defaultProfile")
            let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let json = String(decoding: normalized, as: UTF8.self)
            var parsed = parse("export default \(json);", version: .v4)
            parsed.warnings.insert(contentsOf: skippedRowWarnings, at: 0)
            return parsed
        } catch {
            return FinickyParseResult(
                warnings: [FinickyImportWarning(
                    code: .invalid,
                    message: "Could not read Finicky rules.json: \(error.localizedDescription)"
                )],
                handlerPipelineIsComplete: false)
        }
    }
}

private final class FinickyASTCompiler {
    private struct RouteMatcher: Equatable {
        var matchType: MatchType
        var pattern: String
        var sourceBundleIdentifier: String?
    }

    private struct BrowserAction {
        var application: FinickyResolvedApplication
        var profileID: String?
        var launchArguments: String?
        var suppressAutomaticURL: Bool
        var requiresManualSelection: Bool
    }

    private enum URLField: Equatable {
        case href
        case host
        case hostname
        case pathname
        case `protocol`
        case search
        case hash
        case legacyProtocol
        case legacySearch
        case legacyHash
    }

    private enum StringOperation: Equatable {
        case equals
        case includes
        case startsWith
        case endsWith
    }

    private struct URLCondition: Equatable {
        var field: URLField
        var operation: StringOperation
        var value: String
        var negated: Bool = false

        func negation() -> URLCondition {
            var copy = self
            copy.negated.toggle()
            return copy
        }

        func implies(_ other: URLCondition) -> Bool {
            guard !negated, !other.negated, field == other.field else {
                return self == other
            }
            switch (operation, other.operation) {
            case (.equals, .equals):
                return value == other.value
            case (.equals, .includes):
                return value.contains(other.value)
            case (.equals, .startsWith):
                return value.hasPrefix(other.value)
            case (.equals, .endsWith):
                return value.hasSuffix(other.value)
            case (.includes, .includes):
                return value.contains(other.value)
            case (.startsWith, .startsWith):
                return value.hasPrefix(other.value)
            case (.startsWith, .includes):
                return value.contains(other.value)
            case (.endsWith, .endsWith):
                return value.hasSuffix(other.value)
            case (.endsWith, .includes):
                return value.contains(other.value)
            default:
                return false
            }
        }
    }

    private enum PredicateAtom: Equatable {
        case source(bundleIdentifier: String, equals: Bool)
        case url(URLCondition)

        func negation() -> PredicateAtom {
            switch self {
            case .source(let bundleID, let equals):
                return .source(bundleIdentifier: bundleID, equals: !equals)
            case .url(let condition):
                return .url(condition.negation())
            }
        }
    }

    private indirect enum PredicateExpression {
        case constant(Bool)
        case atom(PredicateAtom)
        case and(PredicateExpression, PredicateExpression)
        case or(PredicateExpression, PredicateExpression)
        case not(PredicateExpression)
    }

    private struct PredicateAlternative {
        var sourceEquals: String?
        var sourceNotEquals: Set<String> = []
        var urlConditions: [URLCondition] = []
    }

    private struct FunctionContext {
        var urlIdentifiers: Set<String> = []
        var optionsIdentifiers: Set<String> = []
        var legacyURLIdentifiers: Set<String> = []
        var hrefIdentifiers: Set<String> = []
        var openerIdentifiers: Set<String> = []
        var sourceBundleIdentifiers: Set<String> = []
    }

    private let root: FinickyASTNode
    private let version: FinickyConfigVersion
    private let applicationResolver: any FinickyApplicationResolving
    private let profileResolver: any FinickyProfileResolving
    private var bindings: [String: FinickyASTNode] = [:]
    private var bindingStatementOffsets: [String: Int] = [:]
    private var bindingDeclarationOffsets: [String: Int] = [:]
    private var declaredBindings = Set<String>()
    private var bindingDependencySources: [String: FinickyASTNode] = [:]
    private var bindingSourcePaths: [String: [String]] = [:]
    private var invalidBindings = Set<String>()
    private var moduleExportsAliases = Set<String>()
    private var unknownTopLevelCallNode: FinickyASTNode?
    private var topLevelAbortNode: FinickyASTNode?
    private var importDeclarationNode: FinickyASTNode?
    private var warnings: [FinickyImportWarning] = []

    private var urlNormalization: URLNormalizationMode {
        version == .v4 ? .whatwg : .none
    }

    init(
        root: FinickyASTNode,
        version: FinickyConfigVersion,
        applicationResolver: any FinickyApplicationResolving,
        profileResolver: any FinickyProfileResolving
    ) {
        self.root = root
        self.version = version
        self.applicationResolver = applicationResolver
        self.profileResolver = profileResolver
    }

    func compile() -> FinickyParseResult {
        guard let program = root["program"] as? FinickyASTNode,
              let body = program["body"] as? [Any] else {
            return FinickyParseResult(
                warnings: [FinickyImportWarning(
                    code: .invalid,
                    message: "Babel returned a configuration without a program."
                )],
                handlerPipelineIsComplete: false,
                rewritePipelineIsComplete: false)
        }

        collectBindings(from: body)
        guard let configNode = findConfiguration(in: body),
              let config = objectProperties(configNode) else {
            if warnings.isEmpty {
                addWarning(
                    .invalid,
                    "Could not find export default or module.exports in the Finicky configuration.",
                    node: program
                )
            }
            return FinickyParseResult(
                warnings: warnings,
                handlerPipelineIsComplete: false,
                rewritePipelineIsComplete: false)
        }
        guard configurationShapeIsValid(config, node: configNode) else {
            return FinickyParseResult(
                warnings: warnings,
                handlerPipelineIsComplete: false,
                rewritePipelineIsComplete: false,
                shortlinkPolicy: version == .v3
                    ? .replace(
                        hosts: ShortlinkResolver.finickyV3ShortenerHosts,
                        mode: .exactHostHTTPS)
                    : .replace(
                        hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                        mode: .domainSuffixHTTPAndHTTPS))
        }

        if let defaultBrowser = config["defaultBrowser"] {
            addWarning(
                .unsupported,
                "Finicky's default browser is not a route. Select Yojam's fallback behaviour after import.",
                node: defaultBrowser
            )
        }
        if let defaultProfile = config["defaultProfile"] {
            addWarning(
                .unsupported,
                "Finicky's default profile is not imported. Select a profile in Yojam after import.",
                node: defaultProfile
            )
        }
        let shortlinkPolicy = compileShortlinkPolicy(optionsNode: config["options"])
        let shortlinkPolicyIsUnknown = shortlinkPolicy == .unknownDynamic
        if let options = config["options"], version == .v4 {
            addWarning(
                .unsupported,
                "Finicky 4 options are not imported. Review Yojam's settings after import.",
                node: options)
        }

        var rewrites: [URLRewriteRule] = []
        var rewritePipelineIsIncomplete = false
        if let rewritesNode = config["rewrite"] {
            if let rewriteNodes = arrayElements(rewritesNode) {
                var earlierRewriteWasSkipped = false
                for (offset, rewrite) in rewriteNodes.enumerated() {
                    let firstNewRewriteIndex = rewrites.count
                    let warningCountBeforeRewrite = warnings.count
                    let priorRewriteWasSkipped = earlierRewriteWasSkipped
                    compileRewrite(rewrite, index: offset + 1, into: &rewrites)
                    let emittedRewrite = rewrites.count > firstNewRewriteIndex
                    let currentRewriteIsIncomplete = !emittedRewrite
                        || warnings.count > warningCountBeforeRewrite
                    if emittedRewrite && (priorRewriteWasSkipped || currentRewriteIsIncomplete) {
                        for rewriteIndex in firstNewRewriteIndex..<rewrites.count {
                            rewrites[rewriteIndex].metadata?["importRequiresReview"] = "true"
                        }
                    }
                    if priorRewriteWasSkipped, emittedRewrite {
                        addWarning(
                            .unsupported,
                            "A rewrite follows a skipped or partly imported Finicky rewrite. Review and select it manually.",
                            node: rewrite
                        )
                    }
                    if currentRewriteIsIncomplete {
                        earlierRewriteWasSkipped = true
                    }
                }
                rewritePipelineIsIncomplete = earlierRewriteWasSkipped
            } else {
                addWarning(.invalid, "Finicky rewrite must be an array.", node: rewritesNode)
                rewritePipelineIsIncomplete = true
            }
        }

        var rules: [Rule] = []
        var handlerPipelineIsIncomplete = false
        if let handlersNode = config["handlers"] {
            if let handlers = arrayElements(handlersNode) {
                var earlierHandlerWasSkipped = false
                for (offset, handler) in handlers.enumerated() {
                    let firstNewRuleIndex = rules.count
                    let warningCountBeforeHandler = warnings.count
                    let priorHandlerWasSkipped = earlierHandlerWasSkipped
                    compileHandler(handler, index: offset + 1, into: &rules)
                    if priorHandlerWasSkipped, rules.count > firstNewRuleIndex {
                        for ruleIndex in firstNewRuleIndex..<rules.count {
                            rules[ruleIndex].metadata?["importRequiresReview"] = "true"
                        }
                        addWarning(
                            .unsupported,
                            "A route follows a skipped or partly imported Finicky handler. Review and select that route manually.",
                            node: handler
                        )
                    }
                    if rules.count == firstNewRuleIndex || warnings.count > warningCountBeforeHandler {
                        earlierHandlerWasSkipped = true
                    }
                }
                handlerPipelineIsIncomplete = earlierHandlerWasSkipped
                if rewritePipelineIsIncomplete, !rules.isEmpty {
                    for ruleIndex in rules.indices {
                        rules[ruleIndex].metadata?["importRequiresReview"] = "true"
                    }
                    addWarning(
                        .unsupported,
                        "Finicky routes depend on a skipped or partly imported rewrite. Review and select those routes manually.",
                        node: handlersNode
                    )
                }
            } else {
                addWarning(.invalid, "Finicky handlers must be an array.", node: handlersNode)
                handlerPipelineIsIncomplete = true
            }
        }

        if shortlinkPolicyIsUnknown {
            for ruleIndex in rules.indices {
                rules[ruleIndex].metadata?["importRequiresReview"] = "true"
            }
            for rewriteIndex in rewrites.indices {
                rewrites[rewriteIndex].metadata?["importRequiresReview"] = "true"
            }
            handlerPipelineIsIncomplete = true
            rewritePipelineIsIncomplete = true
        }

        for ruleIndex in rules.indices {
            var ruleMetadata = rules[ruleIndex].metadata ?? [:]
            ruleMetadata["finickyWebOnly"] = "true"
            ruleMetadata["importedFrom"] = "finicky"
            rules[ruleIndex].metadata = ruleMetadata
            for rewriteIndex in rules[ruleIndex].rewriteRules.indices {
                var metadata = rules[ruleIndex].rewriteRules[rewriteIndex].metadata ?? [:]
                metadata["finickyWebOnly"] = "true"
                metadata["importedFrom"] = "finicky"
                rules[ruleIndex].rewriteRules[rewriteIndex].metadata = metadata
            }
        }
        for rewriteIndex in rewrites.indices {
            var metadata = rewrites[rewriteIndex].metadata ?? [:]
            metadata["finickyWebOnly"] = "true"
            metadata["importedFrom"] = "finicky"
            rewrites[rewriteIndex].metadata = metadata
        }

        return FinickyParseResult(
            rules: rules,
            globalRewrites: rewrites,
            warnings: warnings,
            handlerPipelineIsComplete: !handlerPipelineIsIncomplete,
            rewritePipelineIsComplete: !rewritePipelineIsIncomplete,
            shortlinkPolicy: shortlinkPolicy
        )
    }

    private func compileShortlinkPolicy(
        optionsNode: FinickyASTNode?
    ) -> FinickyShortlinkPolicy {
        guard version == .v3 else {
            return .replace(
                hosts: ShortlinkResolver.finickyV4ShortenerHosts,
                mode: .domainSuffixHTTPAndHTTPS)
        }
        let defaultHosts = ShortlinkResolver.finickyV3ShortenerHosts
        guard let optionsNode else {
            return .replace(hosts: defaultHosts, mode: .exactHostHTTPS)
        }
        guard let options = objectProperties(optionsNode) else {
            addUnknownShortlinkPolicyWarning(node: optionsNode)
            return .unknownDynamic
        }
        guard let policyNode = options["urlShorteners"] else {
            return .replace(hosts: defaultHosts, mode: .exactHostHTTPS)
        }
        if let literalHosts = literalShortlinkHosts(policyNode) {
            return .replace(hosts: literalHosts, mode: .exactHostHTTPS)
        }
        if let appendedHosts = safelyAppendedShortlinkHosts(policyNode) {
            return .replace(
                hosts: defaultHosts.union(appendedHosts),
                mode: .exactHostHTTPS)
        }
        addUnknownShortlinkPolicyWarning(node: policyNode)
        return .unknownDynamic
    }

    private func configurationShapeIsValid(
        _ config: [String: FinickyASTNode],
        node: FinickyASTNode
    ) -> Bool {
        if version == .v3,
           !Set(config.keys).isSubset(of: [
            "defaultBrowser", "options", "rewrite", "handlers",
           ]) {
            addWarning(
                .invalid,
                "Finicky 3 rejects unknown configuration properties. The configuration was not imported.",
                node: node)
            return false
        }
        guard let defaultBrowser = config["defaultBrowser"] else {
            addWarning(
                .invalid,
                "Finicky requires a defaultBrowser value. The configuration was not imported.",
                node: node)
            return false
        }
        guard browserSpecificationIsValid(defaultBrowser, permitsArray: version == .v3) else {
            addWarning(
                .invalid,
                "Finicky's defaultBrowser value is invalid for this Finicky version. The configuration was not imported.",
                node: defaultBrowser)
            return false
        }
        if let handlersNode = config["handlers"] {
            guard let handlers = arrayElements(handlersNode) else {
                addWarning(.invalid, "Finicky handlers must be an array.", node: handlersNode)
                return false
            }
            for handler in handlers {
                guard let object = objectProperties(handler),
                      version == .v4 || Set(object.keys).isSubset(of: [
                        "match", "url", "browser",
                      ]),
                      let match = object["match"], matcherShapeIsValid(match),
                      let browser = object["browser"],
                      browserSpecificationIsValid(browser, permitsArray: version == .v3)
                else {
                    addWarning(
                        .invalid,
                        "A Finicky handler has a shape that Finicky rejects. The configuration was not imported.",
                        node: handler)
                    return false
                }
                if version == .v3, let url = object["url"],
                   !urlTransformShapeIsValid(url, version: .v3) {
                    addWarning(
                        .invalid,
                        "A Finicky handler URL has a shape that Finicky rejects. The configuration was not imported.",
                        node: url)
                    return false
                }
            }
        }
        if let rewritesNode = config["rewrite"] {
            guard let rewrites = arrayElements(rewritesNode) else {
                addWarning(.invalid, "Finicky rewrite must be an array.", node: rewritesNode)
                return false
            }
            for rewrite in rewrites {
                guard let object = objectProperties(rewrite),
                      version == .v4 || Set(object.keys).isSubset(of: ["match", "url"]),
                      let match = object["match"], matcherShapeIsValid(match),
                      let url = object["url"],
                      urlTransformShapeIsValid(url, version: version)
                else {
                    addWarning(
                        .invalid,
                        "A Finicky rewrite has a shape that Finicky rejects. The configuration was not imported.",
                        node: rewrite)
                    return false
                }
            }
        }
        if let optionsNode = config["options"], !optionsShapeIsValid(optionsNode) {
            addWarning(
                .invalid,
                "Finicky options have a shape that Finicky rejects. The configuration was not imported.",
                node: optionsNode)
            return false
        }
        return true
    }

    private func matcherShapeIsValid(_ rawNode: FinickyASTNode) -> Bool {
        let node = resolved(rawNode)
        if staticString(node) != nil || isFunction(node)
            || regexLiteral(node) != nil
            || isFinickyHostnameHelper(node) {
            return true
        }
        guard nodeType(node) == "ArrayExpression" else { return false }
        return (node["elements"] as? [Any] ?? []).allSatisfy { raw in
            guard let element = raw as? FinickyASTNode else {
                return version == .v3
            }
            guard nodeType(element) != "SpreadElement" else { return false }
            let resolvedElement = resolved(element)
            return staticString(resolvedElement) != nil
                || isFunction(resolvedElement)
                || regexLiteral(resolvedElement) != nil
        }
    }

    private func browserSpecificationIsValid(
        _ rawNode: FinickyASTNode,
        permitsArray: Bool
    ) -> Bool {
        let node = resolved(rawNode)
        if staticString(node) != nil || isFunction(node) || nodeType(node) == "NullLiteral" {
            return true
        }
        if nodeType(node) == "ArrayExpression" {
            guard permitsArray, let elements = arrayElements(node) else { return false }
            return elements.allSatisfy {
                browserSpecificationIsValid($0, permitsArray: false)
            }
        }
        guard let object = objectProperties(node),
              let name = object["name"], staticString(name) != nil else { return false }
        if version == .v3,
           !Set(object.keys).isSubset(of: [
            "name", "appType", "openInBackground", "profile", "args",
           ]) {
            return false
        }
        if let appTypeNode = object["appType"] {
            guard let appType = staticString(appTypeNode) else { return false }
            let validTypes: Set<String> = version == .v3
                ? ["appName", "bundleId", "appPath"]
                : ["appName", "bundleId", "path", "none"]
            guard validTypes.contains(appType) else { return false }
        }
        if let profile = object["profile"], staticString(profile) == nil { return false }
        if let background = object["openInBackground"], staticBool(background) == nil {
            return false
        }
        if let args = object["args"], !stringArrayShapeIsValid(args) {
            return false
        }
        return true
    }

    private func urlTransformShapeIsValid(
        _ rawNode: FinickyASTNode,
        version: FinickyConfigVersion
    ) -> Bool {
        let node = resolved(rawNode)
        if staticString(node) != nil || isFunction(node) { return true }
        if version == .v4 {
            guard nodeType(node) == "NewExpression",
                  let callee = node["callee"] as? FinickyASTNode,
                  memberPath(callee) == ["URL"],
                  let rawArguments = node["arguments"] as? [Any],
                  (1...2).contains(rawArguments.count)
            else { return false }
            let arguments = rawArguments.compactMap { raw -> String? in
                guard let argument = raw as? FinickyASTNode else { return nil }
                return staticString(argument)
            }
            guard arguments.count == rawArguments.count else { return false }
            if arguments.count == 1 {
                return WebURL(arguments[0]) != nil
            }
            return WebURL(arguments[1])?.resolve(arguments[0]) != nil
        }
        guard let object = objectProperties(node) else { return false }
        if !Set(object.keys).isSubset(of: [
            "protocol", "username", "password", "host", "port",
            "pathname", "search", "hash",
        ]) {
            return false
        }
        let stringFields = ["protocol", "username", "password", "host", "pathname", "search", "hash"]
        for field in stringFields {
            if let value = object[field], staticString(value) == nil { return false }
        }
        if let port = object["port"] {
            let resolvedPort = resolved(port)
            guard nodeType(resolvedPort) == "NullLiteral"
                    || nodeType(resolvedPort) == "NumericLiteral"
            else { return false }
        }
        return true
    }

    private func optionsShapeIsValid(_ rawNode: FinickyASTNode) -> Bool {
        guard let options = objectProperties(rawNode) else { return false }
        if version == .v3,
           !Set(options.keys).isSubset(of: [
            "hideIcon", "urlShorteners", "checkForUpdate", "logRequests",
           ]) {
            return false
        }
        let booleanKeys = version == .v3
            ? ["hideIcon", "checkForUpdate", "logRequests"]
            : ["hideIcon", "checkForUpdates", "keepRunning", "logRequests"]
        for key in booleanKeys {
            if let value = options[key], staticBool(value) == nil { return false }
        }
        guard let shorteners = options["urlShorteners"] else { return true }
        if version == .v4 {
            return stringArrayShapeIsValid(shorteners)
        }
        let node = resolved(shorteners)
        if nodeType(node) == "ArrayExpression" {
            return stringArrayShapeIsValid(node)
        }
        if isFunction(node) { return true }
        // Finicky evaluates this expression before schema validation. A call
        // can return the documented array or function, but Yojam cannot run it.
        if ["CallExpression", "OptionalCallExpression", "Identifier"].contains(
            nodeType(node)) {
            return true
        }
        return false
    }

    private func stringArrayShapeIsValid(_ rawNode: FinickyASTNode) -> Bool {
        let node = resolved(rawNode)
        guard nodeType(node) == "ArrayExpression" else { return false }
        return (node["elements"] as? [Any] ?? []).allSatisfy { raw in
            guard let element = raw as? FinickyASTNode,
                  nodeType(element) != "SpreadElement" else { return false }
            return staticString(element) != nil
        }
    }

    private func literalShortlinkHosts(_ rawNode: FinickyASTNode) -> Set<String>? {
        let node = resolved(rawNode)
        guard nodeType(node) == "ArrayExpression" else { return nil }
        var hosts: [String] = []
        for rawElement in node["elements"] as? [Any] ?? [] {
            guard let element = rawElement as? FinickyASTNode,
                  nodeType(element) != "SpreadElement",
                  let value = staticString(element),
                  let host = ShortlinkResolver.canonicalHost(value)
            else { return nil }
            hosts.append(host)
        }
        return Set(hosts)
    }

    /// Statically recognises Finicky 3's documented extension form:
    /// `(list) => [...list, "custom.example"]`.
    private func safelyAppendedShortlinkHosts(
        _ rawNode: FinickyASTNode
    ) -> Set<String>? {
        let function = resolved(rawNode)
        guard nodeType(function) == "ArrowFunctionExpression",
              let parameters = function["params"] as? [Any],
              parameters.count == 1,
              let parameter = parameters[0] as? FinickyASTNode,
              nodeType(parameter) == "Identifier",
              let parameterName = parameter["name"] as? String,
              let rawBody = function["body"] as? FinickyASTNode else { return nil }
        let body = unwrapExpression(rawBody)
        guard nodeType(body) == "ArrayExpression",
              let elements = body["elements"] as? [Any],
              let first = elements.first as? FinickyASTNode,
              nodeType(first) == "SpreadElement",
              let spreadArgument = first["argument"] as? FinickyASTNode,
              nodeType(spreadArgument) == "Identifier",
              spreadArgument["name"] as? String == parameterName else { return nil }

        var hosts = Set<String>()
        for rawElement in elements.dropFirst() {
            guard let element = rawElement as? FinickyASTNode,
                  nodeType(element) != "SpreadElement",
                  let value = staticString(element),
                  let host = ShortlinkResolver.canonicalHost(value)
            else { return nil }
            hosts.insert(host)
        }
        return hosts
    }

    private func addUnknownShortlinkPolicyWarning(node: FinickyASTNode) {
        addWarning(
            .unsupported,
            "Finicky's dynamic URL shortener policy cannot be imported safely. Yojam will keep its current short-link settings. Review and select every imported route and rewrite manually.",
            node: node)
    }

    private func collectBindings(from statements: [Any]) {
        for (statementOffset, value) in statements.enumerated() {
            guard let statement = value as? FinickyASTNode else { continue }
            switch nodeType(statement) {
            case "VariableDeclaration":
                for (declarationOffset, rawDeclaration) in
                    (statement["declarations"] as? [Any] ?? []).enumerated() {
                    guard let declaration = rawDeclaration as? FinickyASTNode,
                          let pattern = declaration["id"] as? FinickyASTNode,
                          let initializer = declaration["init"] as? FinickyASTNode
                    else { continue }
                    recordDeclaration(
                        pattern: pattern,
                        initializer: initializer,
                        statementOffset: statementOffset,
                        declarationOffset: declarationOffset,
                        sourcePath: mutationMemberPath(initializer))
                }
            case "ImportDeclaration":
                importDeclarationNode = importDeclarationNode ?? statement
            default:
                continue
            }
        }

        for (name, source) in bindingDependencySources {
            if let unknown = firstUnknownEagerIdentifier(
                in: source,
                statementOffset: bindingStatementOffsets[name] ?? 0,
                bindingName: name) {
                topLevelAbortNode = topLevelAbortNode ?? unknown
            }
        }
        for value in statements {
            guard let statement = value as? FinickyASTNode else { continue }
            topLevelAbortNode = topLevelAbortNode ?? firstTopLevelThrow(in: statement)
        }

        var foundAlias = true
        while foundAlias {
            foundAlias = false
            for (name, path) in bindingSourcePaths where !moduleExportsAliases.contains(name) {
                if path.starts(with: ["module", "exports"])
                    || path.first.map(moduleExportsAliases.contains) == true {
                    moduleExportsAliases.insert(name)
                    foundAlias = true
                }
            }
        }

        var mutationNodes: [String: FinickyASTNode] = [:]
        for value in statements {
            guard let statement = value as? FinickyASTNode else { continue }
            collectTopLevelMutations(in: statement, into: &mutationNodes)
        }
        invalidBindings.formUnion(mutationNodes.keys)

        var pending = Array(invalidBindings)
        while let name = pending.popLast(), let initializer = bindingDependencySources[name] {
            for dependency in referencedBindingNames(in: initializer)
                where invalidBindings.insert(dependency).inserted {
                pending.append(dependency)
            }
        }

        for name in mutationNodes.keys.sorted() {
            addWarning(
                .unsupported,
                "The top-level binding \(name) changes after declaration. It was not imported.",
                node: mutationNodes[name]
            )
        }
    }

    private func recordDeclaration(
        pattern: FinickyASTNode,
        initializer: FinickyASTNode,
        statementOffset: Int,
        declarationOffset: Int,
        sourcePath: [String]?
    ) {
        switch nodeType(pattern) {
        case "Identifier":
            guard let name = pattern["name"] as? String else { return }
            declaredBindings.insert(name)
            bindingStatementOffsets[name] = statementOffset
            bindingDeclarationOffsets[name] = declarationOffset
            bindingDependencySources[name] = initializer
            if let sourcePath { bindingSourcePaths[name] = sourcePath }
            bindings[name] = initializer
        case "AssignmentPattern":
            guard let left = pattern["left"] as? FinickyASTNode else { return }
            recordDeclaration(
                pattern: left,
                initializer: initializer,
                statementOffset: statementOffset,
                declarationOffset: declarationOffset,
                sourcePath: sourcePath)
        case "RestElement":
            guard let argument = pattern["argument"] as? FinickyASTNode else { return }
            recordDeclaration(
                pattern: argument,
                initializer: initializer,
                statementOffset: statementOffset,
                declarationOffset: declarationOffset,
                sourcePath: nil)
            if let name = argument["name"] as? String {
                bindings.removeValue(forKey: name)
            }
        case "ObjectPattern":
            for rawProperty in pattern["properties"] as? [Any] ?? [] {
                guard let property = rawProperty as? FinickyASTNode else { continue }
                if nodeType(property) == "RestElement",
                   let argument = property["argument"] as? FinickyASTNode {
                    recordDeclaration(
                        pattern: argument,
                        initializer: initializer,
                        statementOffset: statementOffset,
                        declarationOffset: declarationOffset,
                        sourcePath: nil)
                    if let name = argument["name"] as? String {
                        bindings.removeValue(forKey: name)
                    }
                    continue
                }
                guard nodeType(property) == "ObjectProperty",
                      let keyNode = property["key"] as? FinickyASTNode,
                      let key = propertyName(keyNode),
                      let valuePattern = property["value"] as? FinickyASTNode
                else { continue }
                recordDeclaration(
                    pattern: valuePattern,
                    initializer: initializer,
                    statementOffset: statementOffset,
                    declarationOffset: declarationOffset,
                    sourcePath: sourcePath.map { $0 + [key] })
                for name in declaredNames(in: valuePattern) {
                    bindings.removeValue(forKey: name)
                }
            }
        case "ArrayPattern":
            for (index, rawElement) in (pattern["elements"] as? [Any] ?? []).enumerated() {
                guard let element = rawElement as? FinickyASTNode else { continue }
                recordDeclaration(
                    pattern: element,
                    initializer: initializer,
                    statementOffset: statementOffset,
                    declarationOffset: declarationOffset,
                    sourcePath: sourcePath.map { $0 + [String(index)] })
                for name in declaredNames(in: element) {
                    bindings.removeValue(forKey: name)
                }
            }
        default:
            break
        }
    }

    private func declaredNames(in node: FinickyASTNode) -> Set<String> {
        if nodeType(node) == "Identifier", let name = node["name"] as? String {
            return [name]
        }
        var names = Set<String>()
        for value in node.values {
            if let child = value as? FinickyASTNode, child["type"] != nil {
                names.formUnion(declaredNames(in: child))
            } else if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    names.formUnion(declaredNames(in: child))
                }
            }
        }
        return names
    }

    private func firstUnknownEagerIdentifier(
        in rawNode: FinickyASTNode,
        statementOffset: Int,
        bindingName: String
    ) -> FinickyASTNode? {
        let node = unwrapExpression(rawNode)
        let type = nodeType(node)
        if isFunction(node) || ["ClassDeclaration", "ClassExpression"].contains(type) {
            return nil
        }
        if type == "Identifier", let name = node["name"] as? String {
            let knownGlobals: Set<String> = [
                "Array", "BigInt", "Boolean", "Date", "Infinity", "JSON",
                "Map", "Math", "NaN", "Number", "Object", "Reflect",
                "RegExp", "Set", "String", "URL", "console", "exports",
                "finicky", "module", "undefined",
            ]
            if knownGlobals.contains(name) { return nil }
            guard let declarationStatementOffset = bindingStatementOffsets[name],
                  let declarationOffset = bindingDeclarationOffsets[name],
                  let currentDeclarationOffset = bindingDeclarationOffsets[bindingName],
                  declarationStatementOffset < statementOffset
                    || (declarationStatementOffset == statementOffset
                        && declarationOffset < currentDeclarationOffset)
            else { return node }
            return nil
        }

        if type == "ObjectProperty" {
            if node["computed"] as? Bool == true,
               let key = node["key"] as? FinickyASTNode,
               let unsafe = firstUnknownEagerIdentifier(
                in: key,
                statementOffset: statementOffset,
                bindingName: bindingName) {
                return unsafe
            }
            guard let value = node["value"] as? FinickyASTNode else { return nil }
            return firstUnknownEagerIdentifier(
                in: value,
                statementOffset: statementOffset,
                bindingName: bindingName)
        }
        if type == "ObjectMethod" {
            guard node["computed"] as? Bool == true,
                  let key = node["key"] as? FinickyASTNode else { return nil }
            return firstUnknownEagerIdentifier(
                in: key,
                statementOffset: statementOffset,
                bindingName: bindingName)
        }
        if ["MemberExpression", "OptionalMemberExpression"].contains(type) {
            if let object = node["object"] as? FinickyASTNode,
               let unsafe = firstUnknownEagerIdentifier(
                in: object,
                statementOffset: statementOffset,
                bindingName: bindingName) {
                return unsafe
            }
            if node["computed"] as? Bool == true,
               let property = node["property"] as? FinickyASTNode {
                return firstUnknownEagerIdentifier(
                    in: property,
                    statementOffset: statementOffset,
                    bindingName: bindingName)
            }
            return nil
        }

        for value in node.values {
            if let child = value as? FinickyASTNode, child["type"] != nil,
               let unsafe = firstUnknownEagerIdentifier(
                in: child,
                statementOffset: statementOffset,
                bindingName: bindingName) {
                return unsafe
            }
            if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    if let unsafe = firstUnknownEagerIdentifier(
                        in: child,
                        statementOffset: statementOffset,
                        bindingName: bindingName) {
                        return unsafe
                    }
                }
            }
        }
        return nil
    }

    private func firstTopLevelThrow(in node: FinickyASTNode) -> FinickyASTNode? {
        if isFunction(node) || ["ClassDeclaration", "ClassExpression"].contains(nodeType(node)) {
            return nil
        }
        if nodeType(node) == "ThrowStatement" { return node }
        for value in node.values {
            if let child = value as? FinickyASTNode,
               child["type"] != nil,
               let thrown = firstTopLevelThrow(in: child) {
                return thrown
            }
            if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    if let thrown = firstTopLevelThrow(in: child) { return thrown }
                }
            }
        }
        return nil
    }

    private func collectTopLevelMutations(
        in node: FinickyASTNode,
        into mutationNodes: inout [String: FinickyASTNode],
        permitsUnknownCall: Bool = false
    ) {
        switch nodeType(node) {
        case "ArrowFunctionExpression", "FunctionExpression", "FunctionDeclaration",
             "ObjectMethod", "ClassDeclaration", "ClassExpression":
            return
        case "AssignmentExpression":
            if let left = node["left"] as? FinickyASTNode {
                recordMutations(of: left, at: node, into: &mutationNodes)
            }
        case "UpdateExpression":
            if let argument = node["argument"] as? FinickyASTNode {
                recordMutations(of: argument, at: node, into: &mutationNodes)
            }
        case "UnaryExpression":
            if node["operator"] as? String == "delete",
               let argument = node["argument"] as? FinickyASTNode {
                recordMutations(of: argument, at: node, into: &mutationNodes)
            }
        case "CallExpression", "OptionalCallExpression":
            recordCallMutation(
                node,
                into: &mutationNodes,
                permitsUnknownCall: permitsUnknownCall)
        default:
            break
        }

        if version == .v3,
           nodeType(node) == "ObjectProperty",
           (node["key"] as? FinickyASTNode).flatMap(propertyName) == "urlShorteners",
           let value = node["value"] as? FinickyASTNode {
            collectTopLevelMutations(
                in: value,
                into: &mutationNodes,
                permitsUnknownCall: true)
            return
        }

        for value in node.values {
            if let child = value as? FinickyASTNode, child["type"] != nil {
                collectTopLevelMutations(
                    in: child,
                    into: &mutationNodes,
                    permitsUnknownCall: permitsUnknownCall)
            } else if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    collectTopLevelMutations(
                        in: child,
                        into: &mutationNodes,
                        permitsUnknownCall: permitsUnknownCall)
                }
            }
        }
    }

    private func recordCallMutation(
        _ call: FinickyASTNode,
        into mutationNodes: inout [String: FinickyASTNode],
        permitsUnknownCall: Bool
    ) {
        guard let callee = call["callee"] as? FinickyASTNode else { return }
        let arguments = call["arguments"] as? [Any] ?? []
        let path = mutationMemberPath(callee)

        let receiverMutators: Set<String> = [
            "add", "clear", "copyWithin", "delete", "fill", "pop", "push",
            "reverse", "set", "shift", "sort", "splice", "unshift",
        ]
        if let method = path?.last, receiverMutators.contains(method),
           let receiver = callee["object"] as? FinickyASTNode {
            recordMutations(of: receiver, at: call, into: &mutationNodes)
            return
        }

        let firstArgumentMutators: Set<[String]> = [
            ["Object", "assign"],
            ["Object", "defineProperties"],
            ["Object", "defineProperty"],
            ["Object", "setPrototypeOf"],
            ["Reflect", "defineProperty"],
            ["Reflect", "deleteProperty"],
            ["Reflect", "set"],
            ["Reflect", "setPrototypeOf"],
        ]
        if let path, firstArgumentMutators.contains(path),
           let first = arguments.first as? FinickyASTNode {
            recordMutations(of: first, at: call, into: &mutationNodes)
            return
        }

        // These helpers return matcher functions and validate their argument
        // while the configuration loads. Other Finicky calls can throw or
        // depend on runtime state before the export is assigned.
        if safeFinickyHostnameHelperCall(call, path: path) { return }
        if path?.first == "finicky" || !permitsUnknownCall {
            unknownTopLevelCallNode = unknownTopLevelCallNode ?? call
        }
        for rawArgument in arguments {
            guard let argument = rawArgument as? FinickyASTNode else { continue }
            recordMutations(of: argument, at: call, into: &mutationNodes)
        }
    }

    private func safeFinickyHostnameHelperCall(
        _ call: FinickyASTNode,
        path: [String]?
    ) -> Bool {
        guard path == ["finicky", "matchHostnames"]
                || path == ["finicky", "matchDomains"],
              let arguments = call["arguments"] as? [Any],
              arguments.count == 1,
              let argument = arguments.first as? FinickyASTNode else {
            return false
        }
        let node = resolved(argument)
        if staticString(node) != nil
            || ["RegExpLiteral", "RegexLiteral"].contains(nodeType(node)) {
            return true
        }
        guard nodeType(node) == "ArrayExpression" else { return false }
        return (node["elements"] as? [Any] ?? []).allSatisfy { raw in
            // JavaScript Array.forEach skips sparse slots.
            guard let element = raw as? FinickyASTNode else { return true }
            guard nodeType(element) != "SpreadElement" else { return false }
            let value = resolved(element)
            return staticString(value) != nil
                || ["RegExpLiteral", "RegexLiteral"].contains(nodeType(value))
        }
    }

    private func recordMutations(
        of target: FinickyASTNode,
        at mutationNode: FinickyASTNode,
        into mutationNodes: inout [String: FinickyASTNode]
    ) {
        for name in mutatedBindingRoots(in: target) where declaredBindings.contains(name) {
            mutationNodes[name] = mutationNodes[name] ?? mutationNode
        }
    }

    private func mutatedBindingRoots(in rawNode: FinickyASTNode) -> Set<String> {
        let node = unwrapExpression(rawNode)
        switch nodeType(node) {
        case "Identifier":
            return Set((node["name"] as? String).map { [$0] } ?? [])
        case "MemberExpression", "OptionalMemberExpression":
            guard let object = node["object"] as? FinickyASTNode else { return [] }
            return mutatedBindingRoots(in: object)
        case "AssignmentPattern":
            guard let left = node["left"] as? FinickyASTNode else { return [] }
            return mutatedBindingRoots(in: left)
        case "RestElement":
            guard let argument = node["argument"] as? FinickyASTNode else { return [] }
            return mutatedBindingRoots(in: argument)
        case "ArrayPattern", "ObjectPattern":
            var result = Set<String>()
            for value in node.values {
                if let child = value as? FinickyASTNode, child["type"] != nil {
                    result.formUnion(mutatedBindingRoots(in: child))
                } else if let children = value as? [Any] {
                    for rawChild in children {
                        guard let child = rawChild as? FinickyASTNode,
                              child["type"] != nil else { continue }
                        result.formUnion(mutatedBindingRoots(in: child))
                    }
                }
            }
            return result
        default:
            return []
        }
    }

    private func mutationMemberPath(_ rawNode: FinickyASTNode) -> [String]? {
        let node = unwrapExpression(rawNode)
        if nodeType(node) == "Identifier", let name = node["name"] as? String {
            return [name]
        }
        guard ["MemberExpression", "OptionalMemberExpression"].contains(nodeType(node)),
              let object = node["object"] as? FinickyASTNode,
              let property = node["property"] as? FinickyASTNode,
              var path = mutationMemberPath(object) else { return nil }
        let name: String?
        if node["computed"] as? Bool == true {
            name = nodeType(property) == "StringLiteral"
                ? property["value"] as? String
                : nil
        } else {
            name = propertyName(property)
        }
        guard let name else { return nil }
        path.append(name)
        return path
    }

    private func referencedBindingNames(in rawNode: FinickyASTNode) -> Set<String> {
        let node = unwrapExpression(rawNode)
        if isFunction(node) || ["ClassDeclaration", "ClassExpression"].contains(nodeType(node)) {
            return []
        }
        if nodeType(node) == "Identifier", let name = node["name"] as? String,
           declaredBindings.contains(name) {
            return [name]
        }
        var result = Set<String>()
        for value in node.values {
            if let child = value as? FinickyASTNode, child["type"] != nil {
                result.formUnion(referencedBindingNames(in: child))
            } else if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    result.formUnion(referencedBindingNames(in: child))
                }
            }
        }
        return result
    }

    private func findConfiguration(in statements: [Any]) -> FinickyASTNode? {
        if let importDeclarationNode {
            addWarning(
                .unsupported,
                "Finicky imports can load code before the configuration export. Imported files cannot be evaluated safely, so the configuration was not imported.",
                node: importDeclarationNode)
            return nil
        }
        if let topLevelAbortNode {
            addWarning(
                .invalid,
                "A top-level statement can stop Finicky before it exports the configuration. The configuration was not imported.",
                node: topLevelAbortNode)
            return nil
        }
        if let unknownTopLevelCallNode {
            addWarning(
                .unsupported,
                "A top-level helper call can change the exported configuration. The final value cannot be imported safely.",
                node: unknownTopLevelCallNode)
            return nil
        }
        var candidates: [(node: FinickyASTNode, statementOffset: Int)] = []
        for (statementOffset, value) in statements.enumerated() {
            guard let statement = value as? FinickyASTNode else { continue }
            if nodeType(statement) == "ExportDefaultDeclaration",
               let declaration = statement["declaration"] as? FinickyASTNode {
                if version == .v3 {
                    addWarning(
                        .invalid,
                        "Finicky 3 requires module.exports configuration syntax.",
                        node: statement)
                    return nil
                }
                candidates.append((declaration, statementOffset))
                continue
            }
            guard nodeType(statement) == "ExpressionStatement",
                  let expression = statement["expression"] as? FinickyASTNode,
                  nodeType(expression) == "AssignmentExpression",
                  let left = expression["left"] as? FinickyASTNode,
                  memberPath(left) == ["module", "exports"],
                  let right = expression["right"] as? FinickyASTNode else { continue }
            guard expression["operator"] as? String == "=" else {
                addWarning(
                    .invalid,
                    "Finicky requires a direct module.exports assignment. The configuration was not imported.",
                    node: expression)
                return nil
            }
            candidates.append((right, statementOffset))
        }
        if let mutation = statements.compactMap({ $0 as? FinickyASTNode })
            .compactMap(firstModuleExportsMemberMutation)
            .first {
            addWarning(
                .unsupported,
                "module.exports changes after its configuration assignment. The final value cannot be imported safely.",
                node: mutation)
            return nil
        }
        guard candidates.count <= 1 else {
            addWarning(
                .unsupported,
                "The Finicky configuration assigns more than one exported configuration. It was not imported.",
                node: candidates.last?.node
            )
            return nil
        }
        guard let candidate = candidates.first else { return nil }
        if referencesBindingDeclaredAfter(
            candidate.node,
            statementOffset: candidate.statementOffset) {
            addWarning(
                .invalid,
                "The exported Finicky configuration reads a binding before its declaration. The configuration was not imported.",
                node: candidate.node)
            return nil
        }
        return candidate.node
    }

    private func referencesBindingDeclaredAfter(
        _ node: FinickyASTNode,
        statementOffset: Int
    ) -> Bool {
        var pending = Array(referencedBindingNames(in: node))
        var visited = Set<String>()
        while let name = pending.popLast() {
            guard visited.insert(name).inserted else { continue }
            if let declarationOffset = bindingStatementOffsets[name],
               declarationOffset > statementOffset {
                return true
            }
            if let initializer = bindingDependencySources[name] {
                pending.append(contentsOf: referencedBindingNames(in: initializer))
            }
        }
        return false
    }

    private func firstModuleExportsMemberMutation(
        in node: FinickyASTNode
    ) -> FinickyASTNode? {
        if isFunction(node) || ["ClassDeclaration", "ClassExpression"].contains(nodeType(node)) {
            return nil
        }
        switch nodeType(node) {
        case "AssignmentExpression":
            if let left = node["left"] as? FinickyASTNode,
               let path = mutationMemberPath(left),
               isModuleExportsMutationPath(path),
               path != ["module", "exports"] {
                return node
            }
        case "UpdateExpression":
            if let argument = node["argument"] as? FinickyASTNode,
               let path = mutationMemberPath(argument),
               isModuleExportsMutationPath(path) {
                return node
            }
        case "UnaryExpression":
            if node["operator"] as? String == "delete",
               let argument = node["argument"] as? FinickyASTNode,
               let path = mutationMemberPath(argument),
               isModuleExportsMutationPath(path) {
                return node
            }
        case "CallExpression", "OptionalCallExpression":
            if let callee = node["callee"] as? FinickyASTNode,
               let receiver = callee["object"] as? FinickyASTNode,
               let path = mutationMemberPath(receiver),
               isModuleExportsMutationPath(path) {
                return node
            }
            let arguments = node["arguments"] as? [Any] ?? []
            if arguments.contains(where: { raw in
                guard let argument = raw as? FinickyASTNode,
                      let path = mutationMemberPath(argument) else { return false }
                return isModuleExportsMutationPath(path)
            }) {
                return node
            }
        default:
            break
        }
        for value in node.values {
            if let child = value as? FinickyASTNode,
               child["type"] != nil,
               let mutation = firstModuleExportsMemberMutation(in: child) {
                return mutation
            }
            if let children = value as? [Any] {
                for rawChild in children {
                    guard let child = rawChild as? FinickyASTNode,
                          child["type"] != nil else { continue }
                    if let mutation = firstModuleExportsMemberMutation(in: child) {
                        return mutation
                    }
                }
            }
        }
        return nil
    }

    private func isModuleExportsMutationPath(_ path: [String]) -> Bool {
        path.starts(with: ["module", "exports"])
            || path.first.map(moduleExportsAliases.contains) == true
    }

    private func compileHandler(
        _ handlerNode: FinickyASTNode,
        index: Int,
        into rules: inout [Rule]
    ) {
        let warningCount = warnings.count
        guard let handler = objectProperties(handlerNode) else {
            addWarning(.invalid, "Finicky handler \(index) is not an object.", node: handlerNode)
            return
        }
        guard let matchNode = handler["match"] else {
            addWarning(.invalid, "Finicky handler \(index) has no match value.", node: handlerNode)
            return
        }
        guard let browserNode = handler["browser"] else {
            addWarning(.invalid, "Finicky handler \(index) has no browser value.", node: handlerNode)
            return
        }
        guard let action = compileBrowser(browserNode, handlerIndex: index) else { return }

        var constantHandlerURL: String?
        if let urlNode = handler["url"] {
            guard version == .v3, let value = constantRewriteURL(urlNode) else {
                addWarning(
                    .unsupported,
                    "Finicky handler \(index) changes its URL dynamically. It was not imported.",
                    node: urlNode
                )
                return
            }
            constantHandlerURL = value
        }

        let matcherWarningCount = warnings.count
        let matchers = compileMatchers(matchNode, label: "Finicky handler \(index)")
        if matchers.isEmpty {
            if warnings.count == warningCount {
                addWarning(
                    .unsupported,
                    "Finicky handler \(index) has no compatible matcher.",
                    node: matchNode
                )
            }
            return
        }

        var markedCatchAllForReview = false
        for (matcherOffset, matcher) in matchers.enumerated() {
            let suffix = matchers.count > 1 ? " (\(matcherOffset + 1))" : ""
            let ruleID = UUID()
            var metadata = [
                "importedFrom": "finicky",
                "finickyHandlerIndex": "\(index)",
                "finickyExactBrowserAction": "true",
            ]
            if action.suppressAutomaticURL {
                metadata["finickySuppressAutomaticURL"] = "true"
            }
            if action.requiresManualSelection {
                metadata["importRequiresReview"] = "true"
            }
            if matcher.matchType == .all, warnings.count > matcherWarningCount {
                metadata["importRequiresReview"] = "true"
                markedCatchAllForReview = true
            }
            let attachedRewrites: [URLRewriteRule]
            if let constantHandlerURL {
                attachedRewrites = [URLRewriteRule(
                    name: "Finicky handler \(index) URL",
                    matchPattern: "(?s:^.*$)",
                    replacement: NSRegularExpression.escapedTemplate(
                        for: constantHandlerURL),
                    isRegex: true,
                    scope: .rule(ruleID),
                    urlNormalization: urlNormalization
                )]
            } else {
                attachedRewrites = []
            }
            rules.append(Rule(
                id: ruleID,
                name: "Finicky handler \(index)\(suffix)",
                matchType: matcher.matchType,
                pattern: matcher.pattern,
                urlNormalization: urlNormalization,
                targetBundleId: action.application.bundleIdentifier,
                targetAppName: action.application.displayName,
                isBuiltIn: false,
                priority: 200 + rules.count,
                rewriteRules: attachedRewrites,
                sourceApps: matcher.sourceBundleIdentifier.map { [RuleSourceApp(bundleId: $0)] } ?? [],
                metadata: metadata,
                ruleProfileId: action.profileID,
                ruleOpenInPrivateWindow: false,
                ruleCustomLaunchArgs: action.launchArguments,
                ruleOpenAsNewInstance: action.profileID != nil
                    || (version == .v3 && action.launchArguments != nil)
            ))
        }
        if markedCatchAllForReview {
            addWarning(
                .unsupported,
                "Finicky handler \(index) has a catch-all branch beside a skipped matcher. Review and select that route manually.",
                node: matchNode
            )
        }
    }

    private func compileRewrite(
        _ rewriteNode: FinickyASTNode,
        index: Int,
        into rewrites: inout [URLRewriteRule]
    ) {
        guard let rewrite = objectProperties(rewriteNode) else {
            addWarning(.invalid, "Finicky rewrite \(index) is not an object.", node: rewriteNode)
            return
        }
        guard let matchNode = rewrite["match"], let urlNode = rewrite["url"] else {
            addWarning(.invalid, "Finicky rewrite \(index) has no match or URL value.", node: rewriteNode)
            return
        }

        let matchers = compileMatchers(matchNode, label: "Finicky rewrite \(index)")
        guard !matchers.isEmpty else { return }
        guard matchers.allSatisfy({ $0.sourceBundleIdentifier == nil }) else {
            addWarning(
                .unsupported,
                "Finicky rewrite \(index) uses a source-app condition, which Yojam rewrites cannot represent.",
                node: matchNode
            )
            return
        }

        guard let replacement = constantRewriteURL(urlNode) else {
            addWarning(
                .unsupported,
                "Finicky rewrite \(index) uses a dynamic URL transform. It was not imported.",
                node: urlNode
            )
            return
        }

        let alternatives = matchers.map { "(?:\($0.pattern))" }.joined(separator: "|")
        let matchPattern = "(?s:^(?=.*(?:\(alternatives))).*$)"
        guard RegexMatcher.isValid(pattern: matchPattern) else {
            addWarning(.invalid, "Finicky rewrite \(index) produced an invalid pattern.", node: matchNode)
            return
        }
        rewrites.append(URLRewriteRule(
            name: "Finicky rewrite \(index)",
            matchPattern: matchPattern,
            replacement: NSRegularExpression.escapedTemplate(for: replacement),
            isRegex: true,
            scope: .global,
            urlNormalization: urlNormalization,
            metadata: [
                "importedFrom": "finicky",
                "finickyRewriteIndex": "\(index)",
            ]
        ))
    }

    private func compileMatchers(
        _ rawNode: FinickyASTNode,
        label: String
    ) -> [RouteMatcher] {
        let node = resolved(rawNode)
        if nodeType(node) == "ArrayExpression" {
            var result: [RouteMatcher] = []
            for (offset, element) in (node["elements"] as? [Any] ?? []).enumerated() {
                guard let element = element as? FinickyASTNode else { continue }
                let compiled = compileMatchers(element, label: "\(label), matcher \(offset + 1)")
                result.append(contentsOf: compiled)
            }
            return deduplicated(result)
        }

        if let value = staticString(node) {
            let pattern = version == .v4
                ? Self.v4WildcardRegex(value)
                : Self.v3WildcardRegex(value)
            return validatedMatcher(pattern, label: label, node: node)
        }

        if let regex = regexLiteral(node) {
            let pattern = scopedJavaScriptRegex(regex.pattern, flags: regex.flags, label: label, node: node)
            guard let pattern else { return [] }
            return validatedMatcher(pattern, label: label, node: node)
        }
        if isRegExpConstructor(node) {
            addWarning(
                .unsupported,
                "\(label) uses a RegExp constructor with a dynamic pattern or flags.",
                node: node
            )
            return []
        }

        if isFunction(node) {
            return compileFunctionMatcher(node, label: label)
        }

        if nodeType(node) == "CallExpression", isFinickyHostnameHelper(node) {
            return compileHostnameHelper(node, label: label)
        }

        addWarning(.unsupported, "\(label) uses an unsupported matcher.", node: node)
        return []
    }

    private func compileFunctionMatcher(
        _ function: FinickyASTNode,
        label: String
    ) -> [RouteMatcher] {
        let context = functionContext(function)
        guard let predicate = predicateExpression(function, context: context),
              var alternatives = predicateAlternatives(predicate) else {
            addWarning(
                .unsupported,
                "\(label) uses a function that cannot be translated safely.",
                node: function
            )
            return []
        }

        alternatives = simplifyNegativeSources(alternatives)
        var results: [RouteMatcher] = []
        for alternative in alternatives {
            if !alternative.sourceNotEquals.isEmpty {
                addWarning(
                    .unsupported,
                    "\(label) has a negative source-app branch that Yojam cannot represent.",
                    node: function
                )
                continue
            }
            guard let pattern = regex(for: alternative.urlConditions) else {
                addWarning(
                    .unsupported,
                    "\(label) has URL conditions that Yojam cannot represent.",
                    node: function
                )
                continue
            }
            let matcher = RouteMatcher(
                matchType: alternative.urlConditions.isEmpty ? .all : .regex,
                pattern: alternative.urlConditions.isEmpty ? "" : pattern,
                sourceBundleIdentifier: alternative.sourceEquals
            )
            if matcher.matchType == .all || RegexMatcher.isValid(pattern: matcher.pattern) {
                results.append(matcher)
            } else {
                addWarning(.invalid, "\(label) produced an invalid regular expression.", node: function)
            }
        }
        return deduplicated(results)
    }

    private func compileHostnameHelper(
        _ call: FinickyASTNode,
        label: String
    ) -> [RouteMatcher] {
        guard let arguments = call["arguments"] as? [Any],
              arguments.count == 1,
              let argument = arguments.first as? FinickyASTNode else {
            addWarning(.invalid, "\(label) calls a hostname helper without a value.", node: call)
            return []
        }
        let nodes = arrayElements(argument) ?? [resolved(argument)]
        var result: [RouteMatcher] = []
        for node in nodes {
            if let hostname = staticString(node),
               let pattern = regex(for: [URLCondition(field: .hostname, operation: .equals, value: hostname)]) {
                result.append(RouteMatcher(matchType: .regex, pattern: pattern, sourceBundleIdentifier: nil))
            } else {
                addWarning(
                    .unsupported,
                    "\(label) uses a non-string hostname helper value.",
                    node: node
                )
            }
        }
        return deduplicated(result)
    }

    private func validatedMatcher(
        _ pattern: String,
        label: String,
        node: FinickyASTNode
    ) -> [RouteMatcher] {
        guard RegexMatcher.isValid(pattern: pattern) else {
            addWarning(.invalid, "\(label) contains a regular expression Yojam cannot use.", node: node)
            return []
        }
        return [RouteMatcher(matchType: .regex, pattern: pattern, sourceBundleIdentifier: nil)]
    }

    private func compileBrowser(
        _ rawNode: FinickyASTNode,
        handlerIndex: Int
    ) -> BrowserAction? {
        var node = resolved(rawNode)
        var templateContext = FunctionContext()
        if isFunction(node) {
            templateContext = functionContext(node)
            guard let returned = singleReturnExpression(node) else {
                addWarning(
                    .unsupported,
                    "Finicky handler \(handlerIndex) uses a dynamic browser function.",
                    node: node
                )
                return nil
            }
            node = resolved(returned)
        }

        if nodeType(node) == "NullLiteral" {
            addWarning(
                .unsupported,
                "Finicky handler \(handlerIndex) blocks matching URLs. Yojam has no block action.",
                node: node
            )
            return nil
        }

        var appName: String
        var appKind: FinickyApplicationKind = .automatic
        var profileName: String?
        var launchArguments: String?
        var suppressAutomaticURL = false
        var requiresManualSelection = false

        if let browserString = staticString(node, context: templateContext) {
            let split = splitBrowserAndProfile(browserString)
            appName = split.browser
            profileName = split.profile
            if appName.hasPrefix("/") || appName.hasPrefix("~/") {
                requiresManualSelection = true
                addWarning(
                    .unsupported,
                    "Finicky handler \(handlerIndex) targets an application path. Yojam will identify that application by bundle ID.",
                    node: node
                )
            }
        } else if let object = objectProperties(node) {
            guard let nameNode = object["name"],
                  let name = staticString(nameNode, context: templateContext),
                  !name.isEmpty else {
                addWarning(
                    .unsupported,
                    "Finicky handler \(handlerIndex) has a browser object without a static name.",
                    node: node
                )
                return nil
            }
            appName = name
            if let appTypeNode = object["appType"] {
                guard let appType = staticString(appTypeNode, context: templateContext) else {
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) has a dynamic application type.",
                        node: appTypeNode
                    )
                    return nil
                }
                switch appType {
                case "appName": appKind = .appName
                case "bundleId": appKind = .bundleId
                case "path" where version == .v4,
                     "appPath" where version == .v3:
                    appKind = .path
                    requiresManualSelection = true
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) targets an application path. Yojam will identify that application by bundle ID.",
                        node: appTypeNode
                    )
                case "none":
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) uses the none application type.",
                        node: appTypeNode
                    )
                    return nil
                default:
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) uses unknown app type \(appType).",
                        node: appTypeNode
                    )
                    return nil
                }
            }
            if let profileNode = object["profile"] {
                guard let profile = staticString(profileNode, context: templateContext) else {
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) has a dynamic profile.",
                        node: profileNode
                    )
                    return nil
                }
                profileName = profile
            }
            if let argsNode = object["args"] {
                guard let arguments = staticArguments(argsNode, context: templateContext),
                      !arguments.contains("--args") else {
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) has launch arguments that Yojam cannot preserve.",
                        node: argsNode
                    )
                    return nil
                }
                if !arguments.isEmpty {
                    guard let joined = joinedLaunchArguments(arguments) else {
                        addWarning(
                            .unsupported,
                            "Finicky handler \(handlerIndex) has launch arguments that Yojam cannot preserve.",
                            node: argsNode
                        )
                        return nil
                    }
                    launchArguments = joined
                    suppressAutomaticURL = true
                }
            }
            if let backgroundNode = object["openInBackground"] {
                guard let opensInBackground = staticBool(backgroundNode) else {
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) has a dynamic background option.",
                        node: backgroundNode
                    )
                    return nil
                }
                if opensInBackground {
                    requiresManualSelection = true
                    addWarning(
                        .unsupported,
                        "Finicky handler \(handlerIndex) opens its target in the background. Yojam will activate it.",
                        node: backgroundNode
                    )
                }
            }
        } else {
            addWarning(
                .unsupported,
                "Finicky handler \(handlerIndex) uses an unsupported browser value.",
                node: node
            )
            return nil
        }

        guard let application = applicationResolver.resolveApplication(
            FinickyApplicationReference(value: appName, kind: appKind),
            version: version
        ) else {
            addWarning(
                .unresolvedApplication,
                "Finicky handler \(handlerIndex) targets \(appName), but Yojam could not resolve that application.",
                node: node
            )
            return nil
        }

        var profileID: String?
        if let profileName, !profileName.isEmpty {
            if version == .v3,
               !Self.finickyThreeSupportsProfile(
                browserBundleIdentifier: application.bundleIdentifier) {
                return BrowserAction(
                    application: application,
                    profileID: nil,
                    launchArguments: launchArguments,
                    suppressAutomaticURL: suppressAutomaticURL,
                    requiresManualSelection: requiresManualSelection
                )
            }

            if version == .v4,
               !Self.finickyFourSupportsProfile(originalBrowserIdentifier: appName) {
                addWarning(
                    .unresolvedProfile,
                    "Finicky handler \(handlerIndex) uses profile \(profileName) with a browser alias or path that Finicky does not profile-enable. Yojam kept the application route without a profile.",
                    node: node
                )
                requiresManualSelection = true
            } else if let resolvedProfile = profileResolver.resolveProfile(
                named: profileName,
                browserBundleIdentifier: application.bundleIdentifier,
                version: version
            ), !ProfileLaunchHelper.launchArguments(
                forProfile: resolvedProfile.id,
                browserBundleId: application.bundleIdentifier
            ).isEmpty {
                profileID = resolvedProfile.id
            } else {
                addWarning(
                    .unresolvedProfile,
                    "Finicky handler \(handlerIndex) targets profile \(profileName), but Yojam could not resolve and launch it.",
                    node: node
                )
                if version == .v3 {
                    return nil
                }
                requiresManualSelection = true
            }
        }

        return BrowserAction(
            application: application,
            profileID: profileID,
            launchArguments: launchArguments,
            suppressAutomaticURL: suppressAutomaticURL,
            requiresManualSelection: requiresManualSelection
        )
    }

    private func predicateExpression(
        _ function: FinickyASTNode,
        context: FunctionContext
    ) -> PredicateExpression? {
        guard let body = function["body"] as? FinickyASTNode else { return nil }
        if nodeType(body) != "BlockStatement" {
            return booleanExpression(body, context: context)
        }
        return predicateFromStatements(body["body"] as? [Any] ?? [], context: context)
    }

    private func predicateFromStatements(
        _ statements: [Any],
        context: FunctionContext
    ) -> PredicateExpression? {
        guard let firstIndex = statements.firstIndex(where: { $0 is FinickyASTNode }),
              let first = statements[firstIndex] as? FinickyASTNode else { return nil }
        let remaining = Array(statements.dropFirst(firstIndex + 1))
        switch nodeType(first) {
        case "ReturnStatement":
            guard let argument = first["argument"] as? FinickyASTNode else { return nil }
            return booleanExpression(argument, context: context)
        case "IfStatement":
            guard let test = first["test"] as? FinickyASTNode,
                  let condition = booleanExpression(test, context: context),
                  let consequent = first["consequent"] as? FinickyASTNode,
                  let whenTrue = predicateFromBranch(
                    consequent,
                    followedBy: remaining,
                    context: context
                  ) else { return nil }
            let whenFalse: PredicateExpression?
            if let alternate = first["alternate"] as? FinickyASTNode {
                whenFalse = predicateFromBranch(alternate, followedBy: remaining, context: context)
            } else {
                whenFalse = predicateFromStatements(remaining, context: context)
            }
            guard let whenFalse else { return nil }
            return .or(
                .and(condition, whenTrue),
                .and(.not(condition), whenFalse)
            )
        case "EmptyStatement":
            return predicateFromStatements(remaining, context: context)
        default:
            return nil
        }
    }

    private func predicateFromBranch(
        _ statement: FinickyASTNode,
        followedBy remaining: [Any],
        context: FunctionContext
    ) -> PredicateExpression? {
        if nodeType(statement) == "BlockStatement" {
            let body = statement["body"] as? [Any] ?? []
            return predicateFromStatements(body + remaining, context: context)
        }
        return predicateFromStatements([statement] + remaining, context: context)
    }

    private func booleanExpression(
        _ rawNode: FinickyASTNode,
        context: FunctionContext
    ) -> PredicateExpression? {
        let node = resolved(rawNode)
        switch nodeType(node) {
        case "BooleanLiteral":
            return .constant(node["value"] as? Bool ?? false)
        case "LogicalExpression":
            guard let left = node["left"] as? FinickyASTNode,
                  let right = node["right"] as? FinickyASTNode,
                  let lhs = booleanExpression(left, context: context),
                  let rhs = booleanExpression(right, context: context) else { return nil }
            switch node["operator"] as? String {
            case "&&": return .and(lhs, rhs)
            case "||": return .or(lhs, rhs)
            default: return nil
            }
        case "UnaryExpression":
            guard node["operator"] as? String == "!",
                  let argument = node["argument"] as? FinickyASTNode,
                  let expression = booleanExpression(argument, context: context) else { return nil }
            return .not(expression)
        case "BinaryExpression":
            return comparisonExpression(node, context: context)
        case "CallExpression", "OptionalCallExpression":
            return methodPredicate(node, context: context)
        case "ConditionalExpression":
            guard let test = node["test"] as? FinickyASTNode,
                  let consequent = node["consequent"] as? FinickyASTNode,
                  let alternate = node["alternate"] as? FinickyASTNode,
                  let condition = booleanExpression(test, context: context),
                  let yes = booleanExpression(consequent, context: context),
                  let no = booleanExpression(alternate, context: context) else { return nil }
            return .or(.and(condition, yes), .and(.not(condition), no))
        default:
            return nil
        }
    }

    private func comparisonExpression(
        _ node: FinickyASTNode,
        context: FunctionContext
    ) -> PredicateExpression? {
        guard let operatorName = node["operator"] as? String,
              ["===", "==", "!==", "!="].contains(operatorName),
              let left = node["left"] as? FinickyASTNode,
              let right = node["right"] as? FinickyASTNode else { return nil }
        let equals = operatorName == "===" || operatorName == "=="

        if let sourcePath = sourceBundlePath(left, context: context),
           let bundleID = staticString(right) {
            _ = sourcePath
            return .atom(.source(bundleIdentifier: bundleID, equals: equals))
        }
        if let sourcePath = sourceBundlePath(right, context: context),
           let bundleID = staticString(left) {
            _ = sourcePath
            return .atom(.source(bundleIdentifier: bundleID, equals: equals))
        }
        if let field = urlField(left, context: context), let value = staticString(right) {
            let condition = URLCondition(field: field, operation: .equals, value: value)
            return .atom(.url(equals ? condition : condition.negation()))
        }
        if let field = urlField(right, context: context), let value = staticString(left) {
            let condition = URLCondition(field: field, operation: .equals, value: value)
            return .atom(.url(equals ? condition : condition.negation()))
        }
        return nil
    }

    private func methodPredicate(
        _ call: FinickyASTNode,
        context: FunctionContext
    ) -> PredicateExpression? {
        guard let callee = call["callee"] as? FinickyASTNode,
              let calleePath = memberPath(callee), calleePath.count >= 2,
              let arguments = call["arguments"] as? [Any],
              arguments.count == 1,
              let argument = arguments.first as? FinickyASTNode,
              let value = staticString(argument) else { return nil }
        let method = calleePath.last!
        let objectPath = Array(calleePath.dropLast())
        guard let field = urlField(path: objectPath, context: context) else { return nil }
        let operation: StringOperation
        switch method {
        case "includes": operation = .includes
        case "startsWith": operation = .startsWith
        case "endsWith": operation = .endsWith
        default: return nil
        }
        return .atom(.url(URLCondition(field: field, operation: operation, value: value)))
    }

    private func predicateAlternatives(
        _ expression: PredicateExpression
    ) -> [PredicateAlternative]? {
        guard let atomGroups = disjunctiveNormalForm(expression) else { return nil }
        var alternatives: [PredicateAlternative] = []
        for atoms in atomGroups {
            var alternative = PredicateAlternative()
            var invalid = false
            for atom in atoms {
                switch atom {
                case .source(let bundleID, true):
                    if let existing = alternative.sourceEquals, existing != bundleID {
                        invalid = true
                    } else {
                        alternative.sourceEquals = bundleID
                    }
                case .source(let bundleID, false):
                    alternative.sourceNotEquals.insert(bundleID)
                case .url(let condition):
                    alternative.urlConditions.append(condition)
                }
            }
            if let source = alternative.sourceEquals,
               alternative.sourceNotEquals.contains(source) {
                invalid = true
            }
            if !invalid {
                alternative.urlConditions = Array(SetBox.deduplicate(alternative.urlConditions))
                alternatives.append(alternative)
            }
        }
        return alternatives
    }

    private func disjunctiveNormalForm(
        _ expression: PredicateExpression,
        negated: Bool = false
    ) -> [[PredicateAtom]]? {
        switch expression {
        case .constant(let value):
            return value != negated ? [[]] : []
        case .atom(let atom):
            return [[negated ? atom.negation() : atom]]
        case .not(let inner):
            return disjunctiveNormalForm(inner, negated: !negated)
        case .and(let left, let right):
            if negated {
                guard let lhs = disjunctiveNormalForm(left, negated: true),
                      let rhs = disjunctiveNormalForm(right, negated: true) else { return nil }
                return lhs + rhs
            }
            guard let lhs = disjunctiveNormalForm(left),
                  let rhs = disjunctiveNormalForm(right) else { return nil }
            guard lhs.count * rhs.count <= 64 else { return nil }
            return lhs.flatMap { leftAtoms in rhs.map { leftAtoms + $0 } }
        case .or(let left, let right):
            if negated {
                guard let lhs = disjunctiveNormalForm(left, negated: true),
                      let rhs = disjunctiveNormalForm(right, negated: true) else { return nil }
                guard lhs.count * rhs.count <= 64 else { return nil }
                return lhs.flatMap { leftAtoms in rhs.map { leftAtoms + $0 } }
            }
            guard let lhs = disjunctiveNormalForm(left),
                  let rhs = disjunctiveNormalForm(right) else { return nil }
            return lhs + rhs
        }
    }

    private func simplifyNegativeSources(
        _ alternatives: [PredicateAlternative]
    ) -> [PredicateAlternative] {
        alternatives.map { current in
            var simplified = current
            for excludedSource in current.sourceNotEquals {
                let covered = alternatives.contains { positive in
                    positive.sourceEquals == excludedSource
                        && conditions(current.urlConditions, imply: positive.urlConditions)
                }
                if covered {
                    simplified.sourceNotEquals.remove(excludedSource)
                }
            }
            return simplified
        }
    }

    private func conditions(
        _ conditions: [URLCondition],
        imply required: [URLCondition]
    ) -> Bool {
        required.allSatisfy { target in
            conditions.contains { $0.implies(target) }
        }
    }

    private func regex(for conditions: [URLCondition]) -> String? {
        guard !conditions.isEmpty else { return "" }
        var lookaheads = ""
        for condition in conditions {
            guard let fullPattern = fullURLPattern(for: condition) else { return nil }
            lookaheads += condition.negated
                ? "(?!\(fullPattern))"
                : "(?=\(fullPattern))"
        }
        return "(?-i:^\(lookaheads).*$)"
    }

    private func fullURLPattern(for condition: URLCondition) -> String? {
        let value = NSRegularExpression.escapedPattern(for: condition.value)
        let scheme = "[A-Za-z][A-Za-z0-9+.-]*://"
        let userInfo = "(?:[^/?#@]*@)?"
        let host = "[^/?#]*"
        let hostname = "[^:/?#]*"
        switch (condition.field, condition.operation) {
        case (.href, .equals):
            return "\(value)$"
        case (.href, .includes):
            return ".*\(value).*"
        case (.href, .startsWith):
            return "\(value).*"
        case (.href, .endsWith):
            return ".*\(value)$"

        case (.host, .equals):
            return "\(scheme)\(userInfo)\(value)(?:[/?#]|$)"
        case (.host, .includes):
            return "\(scheme)\(userInfo)\(host)\(value)\(host)(?:[/?#]|$)"
        case (.host, .startsWith):
            return "\(scheme)\(userInfo)\(value)\(host)(?:[/?#]|$)"
        case (.host, .endsWith):
            return "\(scheme)\(userInfo)\(host)\(value)(?:[/?#]|$)"

        case (.hostname, .equals):
            return "\(scheme)\(userInfo)\(value)(?::[^/?#]*)?(?:[/?#]|$)"
        case (.hostname, .includes):
            return "\(scheme)\(userInfo)\(hostname)\(value)\(hostname)(?::[^/?#]*)?(?:[/?#]|$)"
        case (.hostname, .startsWith):
            return "\(scheme)\(userInfo)\(value)\(hostname)(?::[^/?#]*)?(?:[/?#]|$)"
        case (.hostname, .endsWith):
            return "\(scheme)\(userInfo)\(hostname)\(value)(?::[^/?#]*)?(?:[/?#]|$)"

        case (.pathname, .equals):
            return "\(scheme)\(userInfo)\(host)\(value)(?:[?#]|$)"
        case (.pathname, .includes):
            return "\(scheme)\(userInfo)\(host)[^?#]*\(value)[^?#]*(?:[?#]|$)"
        case (.pathname, .startsWith):
            return "\(scheme)\(userInfo)\(host)\(value)[^?#]*(?:[?#]|$)"
        case (.pathname, .endsWith):
            return "\(scheme)\(userInfo)\(host)[^?#]*\(value)(?:[?#]|$)"

        case (.protocol, _):
            return protocolPattern(for: condition, includesDelimiter: true)

        case (.search, _):
            return searchPattern(for: condition, includesDelimiter: true)

        case (.hash, _):
            return hashPattern(for: condition, includesDelimiter: true)

        case (.legacyProtocol, _):
            return protocolPattern(for: condition, includesDelimiter: false)

        case (.legacySearch, _):
            return searchPattern(for: condition, includesDelimiter: false)

        case (.legacyHash, _):
            return hashPattern(for: condition, includesDelimiter: false)
        }
    }

    private func protocolPattern(
        for condition: URLCondition,
        includesDelimiter: Bool
    ) -> String {
        let rawValue = condition.value
        let escaped = NSRegularExpression.escapedPattern(for: rawValue)
        let schemeToken = "[A-Za-z][A-Za-z0-9+.-]*:"

        if !includesDelimiter {
            guard !rawValue.contains(":") else { return "(?!)" }
            switch condition.operation {
            case .equals:
                guard Self.isValidSchemeName(rawValue) else { return "(?!)" }
                return "\(escaped):.*"
            case .includes:
                return "(?=[^:]*\(escaped)[^:]*:)\(schemeToken).*"
            case .startsWith:
                return "(?=\(escaped)[^:]*:)\(schemeToken).*"
            case .endsWith:
                return "(?=[^:]*\(escaped):)\(schemeToken).*"
            }
        }

        switch condition.operation {
        case .equals:
            guard Self.isValidSchemeToken(rawValue) else { return "(?!)" }
            return "\(escaped).*"
        case .includes:
            if rawValue.contains(":") {
                guard rawValue.hasSuffix(":"),
                      !rawValue.dropLast().contains(":") else { return "(?!)" }
                return "(?=[^:]*\(escaped))\(schemeToken).*"
            }
            return "(?=[^:]*\(escaped)[^:]*:)\(schemeToken).*"
        case .startsWith:
            if rawValue.contains(":") {
                guard Self.isValidSchemeToken(rawValue) else { return "(?!)" }
                return "\(escaped).*"
            }
            return "(?=\(escaped)[^:]*:)\(schemeToken).*"
        case .endsWith:
            if rawValue.isEmpty {
                return "\(schemeToken).*"
            }
            guard rawValue.hasSuffix(":"),
                  !rawValue.dropLast().contains(":") else { return "(?!)" }
            return "(?=[^:]*\(escaped))\(schemeToken).*"
        }
    }

    private func searchPattern(
        for condition: URLCondition,
        includesDelimiter: Bool
    ) -> String {
        if condition.value.isEmpty {
            return condition.operation == .equals
                ? "[^?#]*(?:\\?)?(?:#.*)?$"
                : ".*"
        }
        guard !condition.value.contains("#") else { return "(?!)" }
        let body = fieldBodyPattern(
            value: condition.value,
            operation: condition.operation,
            wildcard: "[^#]*")
        if includesDelimiter {
            return "[^?#]*(?=\(body)(?:#|$))\\?[^#]+(?:#.*)?$"
        } else {
            return "[^?#]*\\?\(body)(?:#.*)?$"
        }
    }

    private func hashPattern(
        for condition: URLCondition,
        includesDelimiter: Bool
    ) -> String {
        if condition.value.isEmpty {
            return condition.operation == .equals ? "[^#]*(?:#)?$" : ".*"
        }
        let body = fieldBodyPattern(
            value: condition.value,
            operation: condition.operation,
            wildcard: ".*")
        if includesDelimiter {
            return "[^#]*(?=\(body)$)#.+$"
        } else {
            return "[^#]*#\(body)$"
        }
    }

    private func fieldBodyPattern(
        value: String,
        operation: StringOperation,
        wildcard: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        switch operation {
        case .equals: return escaped
        case .includes: return "\(wildcard)\(escaped)\(wildcard)"
        case .startsWith: return "\(escaped)\(wildcard)"
        case .endsWith: return "\(wildcard)\(escaped)"
        }
    }

    private func functionContext(_ function: FinickyASTNode) -> FunctionContext {
        var context = FunctionContext()
        let parameters = function["params"] as? [Any] ?? []
        if let first = parameters.first as? FinickyASTNode {
            if nodeType(first) == "Identifier", let name = first["name"] as? String {
                if version == .v4 {
                    context.urlIdentifiers.insert(name)
                } else {
                    context.optionsIdentifiers.insert(name)
                }
            } else if nodeType(first) == "ObjectPattern" {
                addDestructuredBindings(first, to: &context)
            }
        }
        if version == .v4, parameters.count > 1,
           let second = parameters[1] as? FinickyASTNode {
            if nodeType(second) == "Identifier", let name = second["name"] as? String {
                context.optionsIdentifiers.insert(name)
            } else if nodeType(second) == "ObjectPattern" {
                addDestructuredBindings(second, to: &context)
            }
        }
        return context
    }

    private func addDestructuredBindings(
        _ pattern: FinickyASTNode,
        to context: inout FunctionContext
    ) {
        for rawProperty in pattern["properties"] as? [Any] ?? [] {
            guard let property = rawProperty as? FinickyASTNode,
                  let keyNode = property["key"] as? FinickyASTNode,
                  let key = propertyName(keyNode),
                  let valueNode = property["value"] as? FinickyASTNode else { continue }
            let localName: String?
            if nodeType(valueNode) == "Identifier" {
                localName = valueNode["name"] as? String
            } else if nodeType(valueNode) == "AssignmentPattern",
                      let left = valueNode["left"] as? FinickyASTNode {
                localName = left["name"] as? String
            } else {
                localName = nil
            }
            guard let localName else { continue }
            switch key {
            case "url": context.legacyURLIdentifiers.insert(localName)
            case "urlString": context.hrefIdentifiers.insert(localName)
            case "opener": context.openerIdentifiers.insert(localName)
            case "sourceBundleIdentifier": context.sourceBundleIdentifiers.insert(localName)
            default: continue
            }
        }
    }

    private func sourceBundlePath(
        _ node: FinickyASTNode,
        context: FunctionContext
    ) -> [String]? {
        guard let path = memberPath(node), let rootName = path.first else { return nil }
        if context.sourceBundleIdentifiers.contains(rootName), path.count == 1 {
            return path
        }
        if context.openerIdentifiers.contains(rootName), path == [rootName, "bundleId"] {
            return path
        }
        if context.optionsIdentifiers.contains(rootName),
           path == [rootName, "opener", "bundleId"] {
            return path
        }
        if version == .v4,
           context.urlIdentifiers.contains(rootName),
           path == [rootName, "opener", "bundleId"] {
            return path
        }
        return nil
    }

    private func urlField(
        _ node: FinickyASTNode,
        context: FunctionContext
    ) -> URLField? {
        guard let path = memberPath(node) else { return nil }
        return urlField(path: path, context: context)
    }

    private func urlField(
        path: [String],
        context: FunctionContext
    ) -> URLField? {
        guard let rootName = path.first else { return nil }
        if context.hrefIdentifiers.contains(rootName), path.count == 1 {
            return .href
        }
        switch version {
        case .v3:
            if context.optionsIdentifiers.contains(rootName),
               path == [rootName, "urlString"] {
                return .href
            }
            let fieldName: String?
            if context.legacyURLIdentifiers.contains(rootName), path.count == 2 {
                fieldName = path[1]
            } else if context.optionsIdentifiers.contains(rootName),
                      path.count == 3,
                      path[1] == "url" {
                fieldName = path[2]
            } else {
                fieldName = nil
            }
            switch fieldName {
            case "host": return .hostname
            case "pathname": return .pathname
            case "protocol": return .legacyProtocol
            case "search": return .legacySearch
            case "hash": return .legacyHash
            default: return nil
            }

        case .v4:
            let standardFieldName: String?
            let legacyFieldName: String?
            if context.urlIdentifiers.contains(rootName), path.count == 2 {
                if path[1] == "urlString" {
                    return .href
                }
                standardFieldName = path[1]
                legacyFieldName = nil
            } else if context.urlIdentifiers.contains(rootName),
                      path.count == 3,
                      path[1] == "url" {
                standardFieldName = nil
                legacyFieldName = path[2]
            } else if context.legacyURLIdentifiers.contains(rootName), path.count == 2 {
                standardFieldName = nil
                legacyFieldName = path[1]
            } else {
                standardFieldName = nil
                legacyFieldName = nil
            }
            switch standardFieldName {
            case "href": return .href
            case "host": return .host
            case "hostname": return .hostname
            case "pathname": return .pathname
            case "protocol": return .protocol
            case "search": return .search
            case "hash": return .hash
            default: break
            }
            switch legacyFieldName {
            case "host": return .hostname
            case "pathname": return .pathname
            case "protocol": return .legacyProtocol
            case "search": return .legacySearch
            case "hash": return .legacyHash
            default: return nil
            }
        }
    }

    private func staticArguments(
        _ node: FinickyASTNode,
        context: FunctionContext
    ) -> [String]? {
        guard let elements = arrayElements(node) else { return nil }
        var result: [String] = []
        for element in elements {
            guard !containsLiteralURLPlaceholder(element),
                  let value = staticString(element, context: context) else { return nil }
            result.append(value)
        }
        return result
    }

    private func containsLiteralURLPlaceholder(
        _ rawNode: FinickyASTNode,
        visited: Set<String> = []
    ) -> Bool {
        let node = unwrapExpression(rawNode)
        switch nodeType(node) {
        case "StringLiteral":
            return (node["value"] as? String)?.contains("$URL") == true
        case "Identifier":
            guard let name = node["name"] as? String,
                  !visited.contains(name),
                  !invalidBindings.contains(name),
                  let binding = bindings[name] else { return false }
            return containsLiteralURLPlaceholder(
                binding,
                visited: visited.union([name]))
        case "TemplateLiteral":
            let quasis = node["quasis"] as? [Any] ?? []
            let hasLiteral = quasis.contains { raw in
                guard let quasi = raw as? FinickyASTNode,
                      let value = quasi["value"] as? FinickyASTNode else { return false }
                return ((value["cooked"] as? String) ?? (value["raw"] as? String))?
                    .contains("$URL") == true
            }
            if hasLiteral { return true }
            return (node["expressions"] as? [Any] ?? []).contains { raw in
                guard let expression = raw as? FinickyASTNode else { return false }
                return containsLiteralURLPlaceholder(expression, visited: visited)
            }
        case "BinaryExpression":
            guard node["operator"] as? String == "+" else { return false }
            return [node["left"], node["right"]].contains { raw in
                guard let expression = raw as? FinickyASTNode else { return false }
                return containsLiteralURLPlaceholder(expression, visited: visited)
            }
        default:
            return false
        }
    }

    private func staticString(
        _ rawNode: FinickyASTNode,
        context: FunctionContext = FunctionContext(),
        visited: Set<String> = []
    ) -> String? {
        let node = unwrapExpression(rawNode)
        switch nodeType(node) {
        case "StringLiteral":
            return node["value"] as? String
        case "Identifier":
            guard let name = node["name"] as? String else { return nil }
            if context.hrefIdentifiers.contains(name) || context.urlIdentifiers.contains(name) {
                return "$URL"
            }
            guard !visited.contains(name),
                  !invalidBindings.contains(name),
                  let binding = bindings[name] else { return nil }
            return staticString(binding, context: context, visited: visited.union([name]))
        case "TemplateLiteral":
            let quasis = node["quasis"] as? [Any] ?? []
            let expressions = node["expressions"] as? [Any] ?? []
            guard quasis.count == expressions.count + 1 else { return nil }
            var value = ""
            for index in expressions.indices {
                guard let quasi = quasis[index] as? FinickyASTNode,
                      let quasiValue = quasi["value"] as? FinickyASTNode,
                      let cooked = (quasiValue["cooked"] as? String)
                        ?? (quasiValue["raw"] as? String),
                      let expression = expressions[index] as? FinickyASTNode,
                      let expressionValue = staticString(
                        expression,
                        context: context,
                        visited: visited
                      ) else { return nil }
                value += cooked + expressionValue
            }
            guard let last = quasis.last as? FinickyASTNode,
                  let lastValue = last["value"] as? FinickyASTNode,
                  let cooked = (lastValue["cooked"] as? String)
                    ?? (lastValue["raw"] as? String) else { return nil }
            return value + cooked
        case "BinaryExpression":
            guard node["operator"] as? String == "+",
                  let left = node["left"] as? FinickyASTNode,
                  let right = node["right"] as? FinickyASTNode,
                  let lhs = staticString(left, context: context, visited: visited),
                  let rhs = staticString(right, context: context, visited: visited) else { return nil }
            return lhs + rhs
        case "MemberExpression", "OptionalMemberExpression":
            if let path = memberPath(node), path.count == 2,
               context.urlIdentifiers.contains(path[0]),
               ["href", "urlString"].contains(path[1]) {
                return "$URL"
            }
            return nil
        case "CallExpression", "OptionalCallExpression":
            guard let callee = node["callee"] as? FinickyASTNode,
                  let path = memberPath(callee), path.count == 2,
                  context.urlIdentifiers.contains(path[0]),
                  ["toString", "toJSON"].contains(path[1]) else { return nil }
            return "$URL"
        default:
            return nil
        }
    }

    private func staticBool(_ rawNode: FinickyASTNode) -> Bool? {
        let node = resolved(rawNode)
        guard nodeType(node) == "BooleanLiteral" else { return nil }
        return node["value"] as? Bool
    }

    private func constantRewriteURL(
        _ rawNode: FinickyASTNode,
        depth: Int = 0
    ) -> String? {
        guard depth < 16 else { return nil }
        let node = resolved(rawNode)
        if isFunction(node) {
            guard let returned = singleReturnExpression(node) else { return nil }
            return constantRewriteURL(returned, depth: depth + 1)
        }
        if let value = staticString(node), isAbsoluteURL(value) {
            return value
        }
        guard nodeType(node) == "NewExpression",
              let callee = node["callee"] as? FinickyASTNode,
              callee["name"] as? String == "URL",
              let rawArguments = node["arguments"] as? [Any],
              (version == .v4 ? (1...2).contains(rawArguments.count) : rawArguments.count == 1)
        else { return nil }
        let arguments = rawArguments.compactMap { raw -> String? in
            guard let argument = raw as? FinickyASTNode else { return nil }
            return staticString(argument)
        }
        guard arguments.count == rawArguments.count else { return nil }
        if version == .v4 {
            if arguments.count == 1 {
                return WebURL(arguments[0])?.serialized()
            }
            return WebURL(arguments[1])?.resolve(arguments[0])?.serialized()
        }
        guard isAbsoluteURL(arguments[0]) else { return nil }
        return arguments[0]
    }

    private func isAbsoluteURL(_ value: String) -> Bool {
        if version == .v4 {
            return WebURL(value) != nil
        }
        guard let url = URL(string: value), let scheme = url.scheme else { return false }
        return !scheme.isEmpty
    }

    private func regexLiteral(_ rawNode: FinickyASTNode) -> (pattern: String, flags: String)? {
        let node = resolved(rawNode)
        if nodeType(node) == "RegExpLiteral",
           let pattern = node["pattern"] as? String,
           let flags = node["flags"] as? String {
            return (pattern, flags)
        }
        if nodeType(node) == "NewExpression",
           let callee = node["callee"] as? FinickyASTNode,
           callee["name"] as? String == "RegExp",
           let arguments = node["arguments"] as? [Any],
           arguments.count <= 2,
           let patternNode = arguments.first as? FinickyASTNode,
           let pattern = staticString(patternNode) {
            let flags: String
            if arguments.count > 1 {
                guard let flagsNode = arguments[1] as? FinickyASTNode,
                      let staticFlags = staticString(flagsNode) else { return nil }
                flags = staticFlags
            } else {
                flags = ""
            }
            return (pattern, flags)
        }
        return nil
    }

    private func isRegExpConstructor(_ rawNode: FinickyASTNode) -> Bool {
        let node = resolved(rawNode)
        guard nodeType(node) == "NewExpression",
              let callee = node["callee"] as? FinickyASTNode else { return false }
        return callee["name"] as? String == "RegExp"
    }

    private func scopedJavaScriptRegex(
        _ pattern: String,
        flags: String,
        label: String,
        node: FinickyASTNode
    ) -> String? {
        let unsupported = Set(flags).subtracting(Set("imsu"))
        if !unsupported.isEmpty || Set(flags).count != flags.count {
            addWarning(
                .unsupported,
                "\(label) uses unsupported JavaScript regex flag(s): \(String(unsupported.sorted())).",
                node: node
            )
            return nil
        }

        var result = pattern
        if flags.contains("s") { result = "(?s:\(result))" }
        if flags.contains("m") { result = "(?m:\(result))" }
        if !flags.contains("i") { result = "(?-i:\(result))" }
        return result
    }

    private func singleReturnExpression(_ function: FinickyASTNode) -> FinickyASTNode? {
        guard let body = function["body"] as? FinickyASTNode else { return nil }
        if nodeType(body) != "BlockStatement" {
            return body
        }
        let statements = body["body"] as? [Any] ?? []
        guard statements.count == 1,
              let statement = statements.first as? FinickyASTNode,
              nodeType(statement) == "ReturnStatement" else { return nil }
        return statement["argument"] as? FinickyASTNode
    }

    private func objectProperties(_ rawNode: FinickyASTNode) -> [String: FinickyASTNode]? {
        let node = resolved(rawNode)
        guard nodeType(node) == "ObjectExpression" else { return nil }
        var result: [String: FinickyASTNode] = [:]
        for rawProperty in node["properties"] as? [Any] ?? [] {
            guard let property = rawProperty as? FinickyASTNode else { return nil }
            if nodeType(property) == "SpreadElement" {
                guard let argument = property["argument"] as? FinickyASTNode,
                      let spread = objectProperties(argument) else {
                    addWarning(
                        .unsupported,
                        "A dynamic object spread cannot be imported safely.",
                        node: property
                    )
                    return nil
                }
                result.merge(spread) { _, new in new }
                continue
            }
            guard property["computed"] as? Bool != true else {
                addWarning(
                    .unsupported,
                    "A computed object property cannot be imported safely.",
                    node: property
                )
                return nil
            }
            if nodeType(property) == "ObjectMethod",
               let keyNode = property["key"] as? FinickyASTNode,
               let key = propertyName(keyNode) {
                guard !["get", "set"].contains(property["kind"] as? String ?? "method") else {
                    addWarning(
                        .unsupported,
                        "An object getter or setter can run while Finicky validates the configuration. It was not imported.",
                        node: property)
                    return nil
                }
                result[key] = property
                continue
            }
            guard nodeType(property) == "ObjectProperty",
                  let keyNode = property["key"] as? FinickyASTNode,
                  let key = propertyName(keyNode),
                  let value = property["value"] as? FinickyASTNode else {
                addWarning(
                    .unsupported,
                    "An object property cannot be imported safely.",
                    node: property
                )
                return nil
            }
            result[key] = value
        }
        return result
    }

    private func hasLiteralObjectProperty(
        named expectedName: String,
        in rawNode: FinickyASTNode
    ) -> Bool {
        let node = resolved(rawNode)
        guard nodeType(node) == "ObjectExpression" else { return false }
        return (node["properties"] as? [Any] ?? []).contains { rawProperty in
            guard let property = rawProperty as? FinickyASTNode,
                  nodeType(property) != "SpreadElement",
                  property["computed"] as? Bool != true,
                  let key = property["key"] as? FinickyASTNode else { return false }
            return propertyName(key) == expectedName
        }
    }

    private func arrayElements(_ rawNode: FinickyASTNode) -> [FinickyASTNode]? {
        let node = resolved(rawNode)
        guard nodeType(node) == "ArrayExpression" else { return nil }
        var result: [FinickyASTNode] = []
        for raw in node["elements"] as? [Any] ?? [] {
            guard let child = raw as? FinickyASTNode else { return nil }
            if nodeType(child) == "SpreadElement",
               let argument = child["argument"] as? FinickyASTNode {
                guard let spread = arrayElements(argument) else { return nil }
                result.append(contentsOf: spread)
            } else {
                result.append(child)
            }
        }
        return result
    }

    private func resolved(_ rawNode: FinickyASTNode) -> FinickyASTNode {
        var node = unwrapExpression(rawNode)
        var visited = Set<String>()
        while nodeType(node) == "Identifier",
              let name = node["name"] as? String,
              !visited.contains(name),
              !invalidBindings.contains(name),
              let replacement = bindings[name] {
            visited.insert(name)
            node = unwrapExpression(replacement)
        }
        return node
    }

    private func unwrapExpression(_ rawNode: FinickyASTNode) -> FinickyASTNode {
        var node = rawNode
        while [
            "TSAsExpression",
            "TSSatisfiesExpression",
            "TSNonNullExpression",
            "TypeCastExpression",
            "ParenthesizedExpression",
        ].contains(nodeType(node)),
              let expression = node["expression"] as? FinickyASTNode {
            node = expression
        }
        return node
    }

    private func memberPath(_ rawNode: FinickyASTNode) -> [String]? {
        let node = unwrapExpression(rawNode)
        if nodeType(node) == "Identifier", let name = node["name"] as? String {
            return [name]
        }
        guard ["MemberExpression", "OptionalMemberExpression"].contains(nodeType(node)),
              node["computed"] as? Bool != true,
              let object = node["object"] as? FinickyASTNode,
              let property = node["property"] as? FinickyASTNode,
              let propertyName = propertyName(property),
              var path = memberPath(object) else { return nil }
        path.append(propertyName)
        return path
    }

    private func propertyName(_ node: FinickyASTNode) -> String? {
        if nodeType(node) == "Identifier" { return node["name"] as? String }
        if nodeType(node) == "StringLiteral" { return node["value"] as? String }
        return nil
    }

    private func isFunction(_ node: FinickyASTNode) -> Bool {
        [
            "ArrowFunctionExpression",
            "FunctionExpression",
            "FunctionDeclaration",
            "ObjectMethod",
        ].contains(nodeType(node))
    }

    private func isFinickyHostnameHelper(_ node: FinickyASTNode) -> Bool {
        guard let callee = node["callee"] as? FinickyASTNode,
              let path = memberPath(callee) else { return false }
        return path == ["finicky", "matchHostnames"]
            || path == ["finicky", "matchDomains"]
    }

    private func splitBrowserAndProfile(_ value: String) -> (browser: String, profile: String?) {
        guard version == .v4, let separator = value.firstIndex(of: ":") else {
            return (value, nil)
        }
        let browser = String(value[..<separator])
        let profile = String(value[value.index(after: separator)...])
        return (browser, profile.isEmpty ? nil : profile)
    }

    private func joinedLaunchArguments(_ arguments: [String]) -> String? {
        var tokens: [String] = []
        for argument in arguments {
            if argument.isEmpty {
                tokens.append("''")
                continue
            }
            if argument.contains("\n") || argument.contains("\r")
                || (argument.contains("\"") && argument.contains("'")) {
                return nil
            }
            if argument.rangeOfCharacter(from: .whitespaces) == nil,
               !argument.contains("\""), !argument.contains("'") {
                tokens.append(argument)
            } else if !argument.contains("'") {
                tokens.append("'\(argument)'")
            } else {
                tokens.append("\"\(argument)\"")
            }
        }
        return tokens.joined(separator: " ")
    }

    private func deduplicated(_ matchers: [RouteMatcher]) -> [RouteMatcher] {
        var result: [RouteMatcher] = []
        for matcher in matchers where !result.contains(matcher) {
            result.append(matcher)
        }
        return result
    }

    private func addWarning(
        _ code: FinickyImportWarning.Code,
        _ message: String,
        node: FinickyASTNode?
    ) {
        let location = node.flatMap(sourceLocation)
        warnings.append(FinickyImportWarning(
            code: code,
            message: message,
            line: location?.line,
            column: location?.column
        ))
    }

    private func sourceLocation(_ node: FinickyASTNode) -> (line: Int, column: Int)? {
        guard let location = node["loc"] as? FinickyASTNode,
              let start = location["start"] as? FinickyASTNode,
              let line = number(start["line"]),
              let zeroBasedColumn = number(start["column"]) else { return nil }
        return (line, zeroBasedColumn + 1)
    }

    private func number(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func nodeType(_ node: FinickyASTNode) -> String {
        node["type"] as? String ?? ""
    }

    private static func v3WildcardRegex(_ pattern: String) -> String {
        var body = wildcardBody(pattern)
        if !pattern.hasPrefix("http://") && !pattern.hasPrefix("https://") {
            body = "https?://" + body
        }
        return "^\(body)$"
    }

    private static func finickyThreeSupportsProfile(
        browserBundleIdentifier: String
    ) -> Bool {
        switch browserBundleIdentifier.lowercased() {
        case "com.brave.browser",
             "com.brave.browser.beta",
             "com.brave.browser.dev",
             "com.google.chrome",
             "com.microsoft.edgemac",
             "com.microsoft.edgemac.beta",
             "com.vivaldi.vivaldi":
            return true
        default:
            return false
        }
    }

    private static func finickyFourSupportsProfile(
        originalBrowserIdentifier: String
    ) -> Bool {
        let supportedIdentifiers: Set<String> = [
            "Brave Browser", "com.brave.Browser",
            "Google Chrome", "com.google.Chrome",
            "Google Chrome Beta", "com.google.Chrome.beta",
            "Google Chrome Canary", "com.google.Chrome.canary",
            "Chromium", "org.chromium.Chromium",
            "Microsoft Edge", "com.microsoft.edgemac",
            "Vivaldi", "com.vivaldi.Vivaldi",
            "Wavebox", "com.bookry.wavebox",
            "Helium", "net.imput.helium",
            "Comet", "ai.perplexity.comet",
            "Yandex", "ru.yandex.desktop.yandex-browser",
            "Opera", "com.operasoftware.Opera",
            "Opera GX", "com.operasoftware.OperaGX",
            "Firefox", "org.mozilla.firefox",
            "Firefox Developer Edition", "org.mozilla.firefoxdeveloperedition",
            "Zen", "app.zen-browser.zen",
        ]
        return supportedIdentifiers.contains(originalBrowserIdentifier)
    }

    private static func isValidSchemeName(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidSchemeToken(_ value: String) -> Bool {
        guard value.hasSuffix(":") else { return false }
        return isValidSchemeName(String(value.dropLast()))
    }

    private static func v4WildcardRegex(_ pattern: String) -> String {
        if !pattern.contains("*") {
            let exact = NSRegularExpression.escapedPattern(for: pattern)
            return "(?-i:^\(exact)$)"
        }

        var body = wildcardBody(pattern)
        let hasProtocol = pattern.range(
            of: #"^[A-Za-z0-9_]+:"#,
            options: .regularExpression
        ) != nil
        if !hasProtocol && !pattern.hasPrefix("*") {
            body = "(?:https?:|ftp:|mailto:|file:|tel:|sms:|data:)?(?://)?" + body
        } else if hasProtocol && pattern.hasSuffix("//") {
            body += ".*"
        }
        return "(?-i:^\(body)$)"
    }

    private static func wildcardBody(_ pattern: String) -> String {
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            let next = pattern.index(after: index)
            if character == "\\", next < pattern.endIndex, pattern[next] == "*" {
                result += "\\*"
                index = pattern.index(after: next)
                continue
            }
            if character == "*" {
                result += ".*?"
            } else {
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = next
        }
        return result
    }
}

private enum SetBox {
    static func deduplicate<T: Equatable>(_ values: [T]) -> [T] {
        var result: [T] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}
