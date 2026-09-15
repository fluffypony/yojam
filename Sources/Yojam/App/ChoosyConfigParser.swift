import Foundation
import YojamCore

enum ChoosyConfigParser {
    struct Result {
        var rules: [Rule]
        var warnings: [String]
    }

    struct ResolvedApplication: Equatable {
        var bundleIdentifier: String
        var displayName: String
    }

    private struct BehaviourTarget {
        var application: ResolvedApplication
        var profileIdentifier: String?
    }

    typealias ApplicationResolver = (URL) -> ResolvedApplication?

    static func sourcePaths(homeDirectory: URL) -> [URL] {
        [
            homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Choosy", isDirectory: true)
                .appendingPathComponent("behaviours.plist", isDirectory: false),
        ]
    }

    static func warning(index: Int, title: String?, reason: String) -> String {
        let cleanTitle = title?
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let label: String
        if let cleanTitle, !cleanTitle.isEmpty {
            label = "\"\(cleanTitle)\""
        } else {
            label = "at position \(index + 1)"
        }
        return "Skipping Choosy rule \(label): \(reason)"
    }

    static func unsupportedBehaviourReason(_ behaviour: Int) -> String? {
        switch behaviour {
        case 0:
            return "behaviour 0 uses Choosy's default behaviour instead of one fixed browser."
        case 1:
            return "behaviour 1 selects Choosy's favourite browser dynamically."
        case 2:
            return "behaviour 2 selects the best running browser dynamically."
        case 3:
            return "behaviour 3 prompts from all browsers."
        case 4:
            return "behaviour 4 prompts from running browsers."
        case 5:
            return "behaviour 5 prompts from a selected browser list."
        case 6:
            return nil
        case 7:
            return "behaviour 7 opens every browser in a selected list."
        case 8:
            return "behaviour 8 opens the macOS Share menu."
        case 9:
            return "behaviour 9 uses a sharing service."
        default:
            return "behaviour \(behaviour) is not recognised."
        }
    }

    static func parse(
        data: Data,
        applicationResolver: ApplicationResolver = { resolveApplication(at: $0) }
    ) -> Result {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil)
        } catch {
            return Result(
                rules: [],
                warnings: ["Could not read Choosy behaviours.plist: \(error.localizedDescription)"])
        }

        guard let entries = propertyList as? [Any] else {
            return Result(
                rules: [],
                warnings: ["Choosy behaviours.plist does not contain a top-level array."])
        }

        var rules: [Rule] = []
        var warnings: [String] = []
        var earlierEntryWasSkipped = false

        for (index, value) in entries.enumerated() {
            let firstNewRuleIndex = rules.count
            let deferredTitle = (value as? [String: Any])?["title"] as? String
            let priorEntryWasSkipped = earlierEntryWasSkipped
            var currentEntryIsKnownDisabled = false
            defer {
                if priorEntryWasSkipped, rules.count > firstNewRuleIndex {
                    for ruleIndex in firstNewRuleIndex..<rules.count {
                        rules[ruleIndex].metadata?["importRequiresReview"] = "true"
                    }
                    let label = deferredTitle.map { "\"\($0)\"" }
                        ?? "at position \(index + 1)"
                    warnings.append(
                        "Choosy rule \(label) follows a skipped rule. "
                        + "Review and select it manually.")
                }
                if rules.count == firstNewRuleIndex, !currentEntryIsKnownDisabled {
                    earlierEntryWasSkipped = true
                }
            }
            guard let entry = value as? [String: Any] else {
                warnings.append(warning(
                    index: index,
                    title: nil,
                    reason: "the plist entry is not a dictionary."))
                continue
            }

            let decodedEnabled = strictBool(entry["enabled"])
            currentEntryIsKnownDisabled = decodedEnabled == false
            let title = entry["title"] as? String
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the title is missing."))
                continue
            }
            guard let predicate = entry["predicate"] as? String,
                  !predicate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the predicate is missing."))
                continue
            }
            guard let enabled = decodedEnabled else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the enabled value is missing or invalid."))
                continue
            }
            guard let behaviour = strictInt(entry["behaviour"]) else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the behaviour value is missing or invalid."))
                continue
            }
            if let reason = unsupportedBehaviourReason(behaviour) {
                warnings.append(warning(index: index, title: title, reason: reason))
                continue
            }

            guard let target = resolveBehaviourTarget(
                entry["behaviourArgument"],
                applicationResolver: applicationResolver) else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "behaviour 6 does not contain one valid ChoosyBrowser app path."))
                continue
            }

            let expression: PredicateExpression
            do {
                var parser = try PredicateParser(predicate)
                expression = try parser.parse()
            } catch let failure as PredicateFailure {
                warnings.append(warning(index: index, title: title, reason: failure.reason))
                continue
            } catch {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the predicate could not be parsed."))
                continue
            }

            let compiled: CompiledPredicate
            do {
                compiled = try compile(
                    expression,
                    applicationResolver: applicationResolver)
            } catch let failure as PredicateFailure {
                warnings.append(warning(index: index, title: title, reason: failure.reason))
                continue
            } catch {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the predicate cannot be represented exactly."))
                continue
            }

            guard !compiled.alternatives.isEmpty else {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the predicate can never match."))
                continue
            }

            var imported: [Rule] = []
            do {
                for alternative in compiled.alternatives {
                    let matcher = try matcher(for: alternative.urlTests)
                    var metadata = [
                        "importedFrom": "choosy",
                        "choosyPredicate": predicate,
                    ]
                    if alternative.source != nil {
                        metadata["importRequiresReview"] = "true"
                    }
                    imported.append(Rule(
                        name: title,
                        enabled: enabled,
                        matchType: matcher.matchType,
                        pattern: matcher.pattern,
                        targetBundleId: target.application.bundleIdentifier,
                        targetAppName: target.application.displayName,
                        isBuiltIn: false,
                        priority: (rules.count + imported.count + 1) * 10,
                        sourceApps: alternative.source.map {
                            [RuleSourceApp(bundleId: $0.application.bundleIdentifier,
                                           name: $0.application.displayName)]
                        } ?? [],
                        metadata: metadata,
                        ruleProfileId: target.profileIdentifier,
                        ruleOpenInPrivateWindow: target.profileIdentifier == nil ? nil : false,
                        ruleOpenAsNewInstance: target.profileIdentifier == nil ? nil : true))
                }
            } catch let failure as PredicateFailure {
                warnings.append(warning(index: index, title: title, reason: failure.reason))
                continue
            } catch {
                warnings.append(warning(
                    index: index,
                    title: title,
                    reason: "the predicate cannot be represented exactly."))
                continue
            }

            rules.append(contentsOf: imported)
            if !compiled.sourcePaths.isEmpty {
                if enabled {
                    earlierEntryWasSkipped = true
                }
                warnings.append(
                    "Choosy rule \"\(title)\" compares a source app path. "
                    + "Yojam uses its bundle ID, so app copies with the same bundle ID are treated as one source.")
            }
        }

        return Result(rules: rules, warnings: warnings)
    }

    static func resolveApplication(at url: URL) -> ResolvedApplication? {
        guard url.isFileURL,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              isValidBundleIdentifier(identifier) else {
            return nil
        }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return ResolvedApplication(
            bundleIdentifier: identifier,
            displayName: displayName)
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { character in
                character.isASCII
                    && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }

    private static func resolveBehaviourTarget(
        _ value: Any?,
        applicationResolver: ApplicationResolver
    ) -> BehaviourTarget? {
        guard let argument = value as? [String: Any],
              let type = argument["type"] as? String,
              let path = argument["path"] as? String,
              path.hasPrefix("/") else {
            return nil
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        guard let application = applicationResolver(url),
              isValidBundleIdentifier(application.bundleIdentifier) else {
            return nil
        }

        switch type {
        case "ChoosyBrowser":
            return BehaviourTarget(application: application, profileIdentifier: nil)

        case "ChoosyChromeProfileMode", "ChoosyEdgeProfileMode",
             "ChoosyBraveProfileMode", "ChoosyVivaldiProfileMode":
            guard BrowserProfileCatalog.configuration(
                for: application.bundleIdentifier)?.engine == .chromium,
                  let profileIdentifier = argument["profileName"] as? String,
                  !profileIdentifier.trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return BehaviourTarget(
                application: application,
                profileIdentifier: profileIdentifier)

        default:
            return nil
        }
    }

    private static func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func strictInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.intValue
        guard NSNumber(value: value) == number else { return nil }
        return value
    }
}

// MARK: - Predicate parsing

private extension ChoosyConfigParser {
    enum ComparisonOperator: Equatable {
        case equal
        case notEqual
        case contains
        case beginsWith
        case endsWith
        case like
        case matches
    }

    struct ComparisonOptions: Equatable {
        var caseInsensitive = false
        var unsupported: String = ""
    }

    struct Comparison: Equatable {
        var field: String
        var operation: ComparisonOperator
        var options: ComparisonOptions
        var value: String
    }

    indirect enum PredicateExpression: Equatable {
        case truePredicate
        case comparison(Comparison)
        case and([PredicateExpression])
        case or([PredicateExpression])
        case not(PredicateExpression)
    }

    enum PredicateToken: Equatable {
        case identifier(String)
        case string(String)
        case comparison(ComparisonOperator, ComparisonOptions)
        case and
        case or
        case not
        case truePredicate
        case leftParenthesis
        case rightParenthesis
        case end
    }

    struct PredicateFailure: Error {
        var reason: String
    }

    struct PredicateLexer {
        private let characters: [Character]
        private var index = 0

        init(_ source: String) {
            characters = Array(source)
        }

        mutating func tokens() throws -> [PredicateToken] {
            var output: [PredicateToken] = []
            while true {
                skipWhitespace()
                guard let character = current else {
                    output.append(.end)
                    return output
                }

                switch character {
                case "(":
                    advance()
                    output.append(.leftParenthesis)
                case ")":
                    advance()
                    output.append(.rightParenthesis)
                case "\"", "'":
                    output.append(.string(try readString(quote: character)))
                case "=":
                    advance()
                    if current == "=" { advance() }
                    output.append(.comparison(.equal, try readOptions()))
                case "!":
                    advance()
                    guard current == "=" else {
                        throw PredicateFailure(reason: "the predicate contains an unsupported ! operator.")
                    }
                    advance()
                    output.append(.comparison(.notEqual, try readOptions()))
                case "<":
                    advance()
                    guard current == ">" else {
                        throw PredicateFailure(reason: "the predicate contains an unsupported comparison.")
                    }
                    advance()
                    output.append(.comparison(.notEqual, try readOptions()))
                default:
                    guard character.isLetter || character == "_" else {
                        throw PredicateFailure(
                            reason: "the predicate contains unsupported token \"\(character)\".")
                    }
                    let word = readWord()
                    switch word.uppercased() {
                    case "AND":
                        output.append(.and)
                    case "OR":
                        output.append(.or)
                    case "NOT":
                        output.append(.not)
                    case "TRUEPREDICATE":
                        output.append(.truePredicate)
                    case "CONTAINS":
                        output.append(.comparison(.contains, try readOptions()))
                    case "BEGINSWITH":
                        output.append(.comparison(.beginsWith, try readOptions()))
                    case "ENDSWITH":
                        output.append(.comparison(.endsWith, try readOptions()))
                    case "LIKE":
                        output.append(.comparison(.like, try readOptions()))
                    case "MATCHES":
                        output.append(.comparison(.matches, try readOptions()))
                    default:
                        output.append(.identifier(word))
                    }
                }
            }
        }

        private var current: Character? {
            index < characters.count ? characters[index] : nil
        }

        private mutating func advance() {
            index += 1
        }

        private mutating func skipWhitespace() {
            while current?.isWhitespace == true { advance() }
        }

        private mutating func readWord() -> String {
            let start = index
            while let character = current,
                  character.isLetter || character.isNumber || character == "_" || character == "." {
                advance()
            }
            return String(characters[start..<index])
        }

        private mutating func readString(quote: Character) throws -> String {
            advance()
            var output = ""
            while let character = current {
                advance()
                if character == quote { return output }
                guard character == "\\" else {
                    output.append(character)
                    continue
                }
                guard let escaped = current else {
                    throw PredicateFailure(reason: "the predicate ends inside a quoted string.")
                }
                advance()
                switch escaped {
                case quote, "\\":
                    output.append(escaped)
                case "n":
                    output.append("\n")
                case "r":
                    output.append("\r")
                case "t":
                    output.append("\t")
                default:
                    output.append("\\")
                    output.append(escaped)
                }
            }
            throw PredicateFailure(reason: "the predicate ends inside a quoted string.")
        }

        private mutating func readOptions() throws -> ComparisonOptions {
            guard current == "[" else { return ComparisonOptions() }
            advance()
            var options = ComparisonOptions()
            var foundEnd = false
            while let character = current {
                advance()
                if character == "]" {
                    foundEnd = true
                    break
                }
                switch character.lowercased() {
                case "c":
                    options.caseInsensitive = true
                default:
                    options.unsupported.append(character)
                }
            }
            guard foundEnd else {
                throw PredicateFailure(reason: "the predicate has an unfinished comparison option.")
            }
            return options
        }
    }

    struct PredicateParser {
        private let tokens: [PredicateToken]
        private var index = 0

        init(_ source: String) throws {
            var lexer = PredicateLexer(source)
            tokens = try lexer.tokens()
        }

        mutating func parse() throws -> PredicateExpression {
            let expression = try parseOr()
            guard current == .end else {
                throw PredicateFailure(reason: "the predicate has an unsupported compound form.")
            }
            return expression
        }

        private var current: PredicateToken {
            tokens[index]
        }

        private mutating func advance() {
            index += 1
        }

        private mutating func parseOr() throws -> PredicateExpression {
            var expressions = [try parseAnd()]
            while current == .or {
                advance()
                expressions.append(try parseAnd())
            }
            return expressions.count == 1 ? expressions[0] : .or(expressions)
        }

        private mutating func parseAnd() throws -> PredicateExpression {
            var expressions = [try parseUnary()]
            while current == .and {
                advance()
                expressions.append(try parseUnary())
            }
            return expressions.count == 1 ? expressions[0] : .and(expressions)
        }

        private mutating func parseUnary() throws -> PredicateExpression {
            if current == .not {
                advance()
                return .not(try parseUnary())
            }
            if current == .leftParenthesis {
                advance()
                let expression = try parseOr()
                guard current == .rightParenthesis else {
                    throw PredicateFailure(reason: "the predicate has an unmatched parenthesis.")
                }
                advance()
                return expression
            }
            if current == .truePredicate {
                advance()
                return .truePredicate
            }
            guard case .identifier(let field) = current else {
                throw PredicateFailure(reason: "the predicate does not start with a supported field.")
            }
            advance()
            guard case .comparison(let operation, let options) = current else {
                throw PredicateFailure(reason: "the predicate uses an unsupported comparison.")
            }
            advance()
            guard case .string(let value) = current else {
                throw PredicateFailure(reason: "the predicate comparison does not use a fixed string.")
            }
            advance()
            return .comparison(Comparison(
                field: field,
                operation: operation,
                options: options,
                value: value))
        }
    }
}

// MARK: - Predicate compilation

private extension ChoosyConfigParser {
    struct URLTest: Equatable {
        var operation: ComparisonOperator
        var value: String
        var caseInsensitive: Bool
    }

    struct SourceFilter: Equatable {
        var path: String
        var application: ResolvedApplication
    }

    struct Alternative: Equatable {
        var source: SourceFilter?
        var urlTests: [URLTest] = []
    }

    struct CompiledPredicate {
        var alternatives: [Alternative]
        var sourcePaths: Set<String>
    }

    struct Matcher {
        var matchType: MatchType
        var pattern: String
    }

    static func compile(
        _ expression: PredicateExpression,
        applicationResolver: ApplicationResolver
    ) throws -> CompiledPredicate {
        switch expression {
        case .truePredicate:
            return CompiledPredicate(alternatives: [Alternative()], sourcePaths: [])

        case .comparison(let comparison):
            return try compile(comparison, applicationResolver: applicationResolver)

        case .not:
            throw PredicateFailure(
                reason: "NOT compounds cannot be represented without changing their meaning.")

        case .or(let expressions):
            var alternatives: [Alternative] = []
            var sourcePaths = Set<String>()
            for child in expressions {
                let compiled = try compile(child, applicationResolver: applicationResolver)
                alternatives.append(contentsOf: compiled.alternatives)
                sourcePaths.formUnion(compiled.sourcePaths)
                guard alternatives.count <= 64 else {
                    throw PredicateFailure(reason: "the predicate expands to more than 64 OR alternatives.")
                }
            }
            return CompiledPredicate(alternatives: alternatives, sourcePaths: sourcePaths)

        case .and(let expressions):
            var alternatives = [Alternative()]
            var sourcePaths = Set<String>()
            for child in expressions {
                let compiled = try compile(child, applicationResolver: applicationResolver)
                sourcePaths.formUnion(compiled.sourcePaths)
                var combined: [Alternative] = []
                for left in alternatives {
                    for right in compiled.alternatives {
                        if let merged = merge(left, right) {
                            combined.append(merged)
                        }
                        guard combined.count <= 64 else {
                            throw PredicateFailure(
                                reason: "the predicate expands to more than 64 AND alternatives.")
                        }
                    }
                }
                alternatives = combined
            }
            return CompiledPredicate(alternatives: alternatives, sourcePaths: sourcePaths)
        }
    }

    static func compile(
        _ comparison: Comparison,
        applicationResolver: ApplicationResolver
    ) throws -> CompiledPredicate {
        guard comparison.options.unsupported.isEmpty else {
            throw PredicateFailure(
                reason: "comparison option [\(comparison.options.unsupported)] is not supported exactly.")
        }

        switch comparison.field {
        case "URL":
            let test = URLTest(
                operation: comparison.operation,
                value: comparison.value,
                caseInsensitive: comparison.options.caseInsensitive)
            return CompiledPredicate(
                alternatives: [Alternative(urlTests: [test])],
                sourcePaths: [])

        case "sourceApp":
            guard comparison.operation == .equal,
                  !comparison.options.caseInsensitive else {
                throw PredicateFailure(
                    reason: "source-app comparisons are supported only as case-sensitive equality.")
            }
            let path = comparison.value
            guard path.hasPrefix("/") else {
                throw PredicateFailure(reason: "the source app is not an absolute app path.")
            }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            guard let application = applicationResolver(url),
                  isValidBundleIdentifier(application.bundleIdentifier) else {
                throw PredicateFailure(reason: "the source app path has no valid bundle ID.")
            }
            return CompiledPredicate(
                alternatives: [Alternative(source: SourceFilter(
                    path: url.path,
                    application: application))],
                sourcePaths: [url.path])

        default:
            throw PredicateFailure(
                reason: "dynamic or unsupported field \"\(comparison.field)\" cannot be imported exactly.")
        }
    }

    static func merge(_ left: Alternative, _ right: Alternative) -> Alternative? {
        let source: SourceFilter?
        switch (left.source, right.source) {
        case (nil, let value), (let value, nil):
            source = value
        case (let first?, let second?):
            guard first.path == second.path else { return nil }
            source = first
        }
        return Alternative(
            source: source,
            urlTests: left.urlTests + right.urlTests)
    }

    static func matcher(for tests: [URLTest]) throws -> Matcher {
        guard !tests.isEmpty else { return Matcher(matchType: .all, pattern: "") }
        let lookaheads = tests.map(regexLookahead)
        let pattern = "\\A\(lookaheads.joined())[\\s\\S]*\\z"
        guard RegexMatcher.isValid(pattern: pattern) else {
            throw PredicateFailure(reason: "the generated URL regular expression is invalid.")
        }
        return Matcher(matchType: .regex, pattern: pattern)
    }

    static func regexLookahead(for test: URLTest) -> String {
        switch test.operation {
        case .equal:
            let literal = NSRegularExpression.escapedPattern(for: test.value)
            let group = caseGroup(literal, caseInsensitive: test.caseInsensitive)
            return "(?=\(group)\\z)"
        case .notEqual:
            let literal = NSRegularExpression.escapedPattern(for: test.value)
            let group = caseGroup(literal, caseInsensitive: test.caseInsensitive)
            return "(?!\(group)\\z)"
        case .contains:
            let literal = NSRegularExpression.escapedPattern(for: test.value)
            let group = caseGroup(literal, caseInsensitive: test.caseInsensitive)
            return "(?=[\\s\\S]*\(group))"
        case .beginsWith:
            let literal = NSRegularExpression.escapedPattern(for: test.value)
            let group = caseGroup(literal, caseInsensitive: test.caseInsensitive)
            return "(?=\(group))"
        case .endsWith:
            let literal = NSRegularExpression.escapedPattern(for: test.value)
            let group = caseGroup(literal, caseInsensitive: test.caseInsensitive)
            return "(?=[\\s\\S]*\(group)\\z)"
        case .like:
            let group = caseGroup(
                likePattern(test.value),
                caseInsensitive: test.caseInsensitive)
            return "(?=\(group)\\z)"
        case .matches:
            let group = caseGroup(
                "(?:\(test.value))",
                caseInsensitive: test.caseInsensitive)
            return "(?=\(group)\\z)"
        }
    }

    static func caseGroup(_ pattern: String, caseInsensitive: Bool) -> String {
        caseInsensitive ? "(?:\(pattern))" : "(?-i:\(pattern))"
    }

    static func likePattern(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                result += NSRegularExpression.escapedPattern(for: String(character))
                escaped = false
                continue
            }
            switch character {
            case "\\":
                escaped = true
            case "*":
                result += "[\\s\\S]*"
            case "?":
                result += "[\\s\\S]"
            default:
                result += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        if escaped {
            result += "\\\\"
        }
        return result
    }
}
