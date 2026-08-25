import XCTest
@testable import Yojam

final class FinickyAggregateMutationTests: XCTestCase {
    func testChangedAggregateConstBindingsNeverUseTheirStaleInitialisers() {
        let mutationForms = [
            "handlers.push({ match: \"pushed.example/*\", browser: \"Google Chrome\" });",
            "handlers.splice(0, 1);",
            "handlers[0] = { match: \"assigned.example/*\", browser: \"Google Chrome\" };",
            "handlers[0].browser = \"Google Chrome\";",
            "Object.assign(handlers[0], { browser: \"Google Chrome\" });",
            "handlers[\"push\"]({ match: \"computed.example/*\", browser: \"Google Chrome\" });",
        ]

        for mutation in mutationForms {
            for mutationComesFirst in [true, false] {
                let declaration = #"const handlers = [{ match: "safe.example/*", browser: "Safari" }];"#
                let export = "export default { defaultBrowser: \"Safari\", handlers };"
                let source = mutationComesFirst
                    ? [declaration, mutation, export].joined(separator: "\n")
                    : [declaration, export, mutation].joined(separator: "\n")
                let result = parser.parse(source)

                XCTAssertTrue(
                    result.rules.isEmpty,
                    "Mutation was imported from stale syntax: \(mutation)\n\(result.warningMessages.joined(separator: "\n"))")
                XCTAssertTrue(result.warningMessages.contains {
                    $0.contains("top-level binding handlers changes")
                }, mutation)
            }
        }
    }

    func testConfigPropertyMutationRejectsTheStaleConfigObject() {
        let mutations = [
            "config.handlers.push({ match: \"later.example/*\", browser: \"Safari\" });",
            "config.handlers = [];",
            "Object.assign(config, { handlers: [] });",
            "Object.defineProperty(config, \"handlers\", { value: [] });",
        ]

        for mutation in mutations {
            let result = parser.parse(#"""
            const config = {
              defaultBrowser: "Safari",
              handlers: [{ match: "safe.example/*", browser: "Safari" }]
            };
            export default config;
            \#(mutation)
            """#)

            XCTAssertTrue(result.rules.isEmpty, mutation)
            XCTAssertTrue(result.warningMessages.contains {
                $0.contains("top-level binding config changes")
            }, mutation)
        }
    }

    func testMutationThroughAConstAliasInvalidatesTheOriginalAggregate() {
        let result = parser.parse(#"""
        const handlers = [{ match: "safe.example/*", browser: "Safari" }];
        const alias = handlers;
        export default { defaultBrowser: "Safari", handlers };
        alias.push({ match: "later.example/*", browser: "Google Chrome" });
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains {
            $0.contains("top-level binding alias changes")
        }, result.warningMessages.joined(separator: "\n"))
    }

    func testModuleExportsReceiverMutationRejectsTheStaleExport() {
        let result = parser.parse(#"""
        module.exports = {
          defaultBrowser: "Safari",
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        module.exports.handlers.splice(0, 1);
        """#, version: .v3)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("module.exports changes") })
    }

    func testLetAliasAndDestructuredAliasInvalidateTheOriginalConfig() {
        let sources = [
            #"""
            const config = {
              defaultBrowser: "Safari",
              handlers: [{ match: "safe.example/*", browser: "Safari" }]
            };
            let alias = config;
            export default config;
            alias.handlers.splice(0, 1);
            """#,
            #"""
            const config = {
              defaultBrowser: "Safari",
              handlers: [{ match: "safe.example/*", browser: "Safari" }]
            };
            const { handlers } = config;
            export default config;
            handlers.splice(0, 1);
            """#,
        ]

        for source in sources {
            let result = parser.parse(source)
            XCTAssertTrue(result.rules.isEmpty, result.warningMessages.joined(separator: "\n"))
            XCTAssertTrue(result.warningMessages.contains { $0.contains("top-level binding") })
        }
    }

    func testImmediatelyInvokedFunctionCannotHideAConfigMutation() {
        let result = parser.parse(#"""
        const config = {
          defaultBrowser: "Safari",
          handlers: [{ match: "safe.example/*", browser: "Safari" }]
        };
        (() => config.handlers.splice(0, 1))();
        export default config;
        """#)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.warningMessages.contains { $0.contains("top-level helper call") })
    }

    private var parser: FinickyConfigParser {
        FinickyConfigParser(
            applicationResolver: AggregateMutationApplicationResolver())
    }
}

private struct AggregateMutationApplicationResolver: FinickyApplicationResolving {
    func resolveApplication(
        _ reference: FinickyApplicationReference,
        version: FinickyConfigVersion
    ) -> FinickyResolvedApplication? {
        switch reference.value {
        case "Safari":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari")
        case "Google Chrome":
            return FinickyResolvedApplication(
                bundleIdentifier: "com.google.Chrome",
                displayName: "Google Chrome")
        default:
            return nil
        }
    }
}
