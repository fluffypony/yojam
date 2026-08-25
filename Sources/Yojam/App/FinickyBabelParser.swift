import Foundation
import JavaScriptCore

typealias FinickyASTNode = [String: Any]

struct FinickyBabelSyntaxError: Error, Equatable {
    let message: String
    let line: Int?
    let column: Int?
}

final class FinickyBabelParser {
    private let parserSourceProvider: () throws -> String

    init(parserSourceProvider: (() throws -> String)? = nil) {
        self.parserSourceProvider = parserSourceProvider ?? Self.loadBundledParser
    }

    func parse(_ source: String) throws -> FinickyASTNode {
        guard source.utf8.count <= 1_048_576 else {
            throw FinickyBabelSyntaxError(
                message: "The Finicky configuration is larger than 1 MB.",
                line: nil,
                column: nil
            )
        }

        guard let context = JSContext() else {
            throw FinickyBabelSyntaxError(
                message: "Could not start the JavaScript parser.",
                line: nil,
                column: nil
            )
        }

        var capturedException: JSValue?
        context.exceptionHandler = { _, exception in
            capturedException = exception
        }

        // This context runs only the vendored Babel parser. The user source is
        // passed to Babel as data and is never evaluated as JavaScript.
        context.evaluateScript("var exports = {}; var module = { exports: exports };")
        let parserSource = try parserSourceProvider()
        context.evaluateScript(parserSource, withSourceURL: URL(string: "yojam://babel-parser.js"))
        if let capturedException {
            throw Self.syntaxError(from: capturedException)
        }

        guard let parseFunction = context.objectForKeyedSubscript("exports")?
            .objectForKeyedSubscript("parse"), !parseFunction.isUndefined else {
            throw FinickyBabelSyntaxError(
                message: "The bundled JavaScript parser is invalid.",
                line: nil,
                column: nil
            )
        }

        let options: [String: Any] = [
            "sourceType": "unambiguous",
            "plugins": [
                "typescript",
                "jsx",
                "optionalChaining",
                "objectRestSpread",
            ],
            "errorRecovery": false,
            "allowAwaitOutsideFunction": false,
            "ranges": true,
        ]
        capturedException = nil
        guard let value = parseFunction.call(withArguments: [source, options]) else {
            if let capturedException {
                throw Self.syntaxError(from: capturedException)
            }
            throw FinickyBabelSyntaxError(
                message: "Babel did not return a syntax tree.",
                line: nil,
                column: nil
            )
        }
        if let capturedException {
            throw Self.syntaxError(from: capturedException)
        }
        guard let root = value.toObject() as? FinickyASTNode else {
            throw FinickyBabelSyntaxError(
                message: "Babel returned an invalid syntax tree.",
                line: nil,
                column: nil
            )
        }
        return root
    }

    private static func loadBundledParser() throws -> String {
        let bundles: [Bundle] = {
#if SWIFT_PACKAGE
            [Bundle.module, Bundle.main]
#else
            [Bundle.main, Bundle(for: FinickyBabelParser.self)]
#endif
        }()

        for bundle in bundles {
            let candidates = [
                bundle.url(
                    forResource: "babel-parser-7.28.4",
                    withExtension: "js",
                    subdirectory: "ThirdParty/BabelParser"
                ),
                bundle.url(forResource: "babel-parser-7.28.4", withExtension: "js"),
            ]
            for url in candidates.compactMap({ $0 }) {
                return try String(contentsOf: url, encoding: .utf8)
            }
        }

        throw FinickyBabelSyntaxError(
            message: "Could not find the bundled JavaScript parser.",
            line: nil,
            column: nil
        )
    }

    private static func syntaxError(from value: JSValue) -> FinickyBabelSyntaxError {
        let message = value.objectForKeyedSubscript("message")?.toString()
            ?? value.toString()
            ?? "The Finicky configuration has invalid syntax."
        let location = value.objectForKeyedSubscript("loc")
        let line = location?.objectForKeyedSubscript("line")?.toInt32()
        let zeroBasedColumn = location?.objectForKeyedSubscript("column")?.toInt32()
        return FinickyBabelSyntaxError(
            message: message,
            line: line.map(Int.init),
            column: zeroBasedColumn.map { Int($0) + 1 }
        )
    }
}
