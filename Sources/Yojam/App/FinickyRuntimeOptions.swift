import AppKit
import Darwin
import Foundation

struct FinickyRuntimeDetection: Equatable, Sendable {
    var bundleIdentifier: String
    var appVersion: String?
    var options: FinickyRuntimeOptions
}

struct FinickyRuntimeOptions: Equatable, Sendable {
    var configPath: String?
    var rulesPath: String?
    var skipsJavaScriptConfig = false

    static func detectRunning(bundleIdentifiers: [String]) -> FinickyRuntimeDetection? {
        detect(bundleIdentifiers: bundleIdentifiers) { bundleIdentifier in
            guard let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier).first,
                  let arguments = ProcessArgumentReader.arguments(
                    for: application.processIdentifier)
            else { return nil }
            let version = application.bundleURL.flatMap(Self.applicationVersion(at:))
            return (arguments, version)
        }
    }

    static func detect(
        bundleIdentifiers: [String],
        process: (String) -> (arguments: [String], appVersion: String?)?
    ) -> FinickyRuntimeDetection? {
        for bundleID in bundleIdentifiers {
            guard let process = process(bundleID) else { continue }
            return FinickyRuntimeDetection(
                bundleIdentifier: bundleID,
                appVersion: process.appVersion,
                options: parse(arguments: process.arguments))
        }
        return nil
    }

    static func applicationVersion(at applicationURL: URL) -> String? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }
        return bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static func parse(arguments: [String]) -> FinickyRuntimeOptions {
        var result = FinickyRuntimeOptions()
        var index = arguments.startIndex
        // Go's flag package parses os.Args[1:], after the executable path.
        if index < arguments.endIndex {
            index = arguments.index(after: index)
        }
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--" || !argument.hasPrefix("-") || argument == "-" {
                break
            }
            if let value = flagValue(in: argument, names: ["--config", "-config"]) {
                result.configPath = value.isEmpty ? nil : value
            } else if let value = flagValue(in: argument, names: ["--rules", "-rules"]) {
                result.rulesPath = value.isEmpty ? nil : value
            } else if let value = flagValue(
                in: argument,
                names: [
                    "--no-config", "-no-config",
                    "--window", "-window",
                    "--dry-run", "-dry-run",
                ]
            ) {
                guard let parsed = parseGoBoolean(value) else { break }
                if argument.hasPrefix("--no-config=")
                    || argument.hasPrefix("-no-config=") {
                    result.skipsJavaScriptConfig = parsed
                }
            } else if ["--config", "-config"].contains(argument),
                      arguments.index(after: index) < arguments.endIndex {
                index = arguments.index(after: index)
                result.configPath = arguments[index]
            } else if ["--rules", "-rules"].contains(argument),
                      arguments.index(after: index) < arguments.endIndex {
                index = arguments.index(after: index)
                result.rulesPath = arguments[index]
            } else if ["--no-config", "-no-config"].contains(argument) {
                result.skipsJavaScriptConfig = true
            } else if [
                "--window", "-window", "--dry-run", "-dry-run",
            ].contains(argument) {
                // Known Go boolean flags. Their values do not affect import.
            } else {
                // A running Finicky process cannot have survived an unknown
                // Go flag. Stop rather than interpreting later positional text.
                break
            }
            index = arguments.index(after: index)
        }
        return result
    }

    func configURL(homeDirectory: URL) -> URL? {
        Self.fileURL(
            path: configPath,
            homeDirectory: homeDirectory,
            expandsEnvironment: true)
    }

    func rulesURL(homeDirectory: URL) -> URL? {
        // Finicky passes --rules directly to os.ReadFile. Unlike --config,
        // that path does not expand environment or tilde references.
        Self.fileURL(
            path: rulesPath,
            homeDirectory: homeDirectory,
            expandsEnvironment: false)
    }

    private static func flagValue(in argument: String, names: [String]) -> String? {
        for name in names {
            let prefix = name + "="
            if argument.hasPrefix(prefix) {
                return String(argument.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func parseGoBoolean(_ value: String) -> Bool? {
        switch value {
        case "1", "t", "T", "TRUE", "true", "True":
            return true
        case "0", "f", "F", "FALSE", "false", "False":
            return false
        default:
            return nil
        }
    }

    private static func fileURL(
        path: String?,
        homeDirectory: URL,
        expandsEnvironment: Bool
    ) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        var expanded = path
        if expandsEnvironment {
            expanded = expandEnvironment(in: expanded, homeDirectory: homeDirectory)
            if expanded == "~" {
                expanded = homeDirectory.path
            } else if expanded.hasPrefix("~/") {
                expanded = homeDirectory.appendingPathComponent(
                    String(expanded.dropFirst(2))).path
            }
        }
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private static func expandEnvironment(in path: String, homeDirectory: URL) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))"#)
        let source = path as NSString
        var result = path
        let matches = expression.matches(
            in: path,
            range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let braced = match.range(at: 1)
            let plain = match.range(at: 2)
            let nameRange = braced.location != NSNotFound ? braced : plain
            let name = source.substring(with: nameRange)
            let value = name == "HOME"
                ? homeDirectory.path
                : ProcessInfo.processInfo.environment[name] ?? ""
            result = (result as NSString).replacingCharacters(
                in: match.range,
                with: value)
        }
        return result
    }
}

enum ProcessArgumentReader {
    static func arguments(for processIdentifier: pid_t) -> [String]? {
        var argumentMaximum: Int32 = 0
        var argumentMaximumSize = MemoryLayout<Int32>.size
        guard sysctlbyname(
            "kern.argmax",
            &argumentMaximum,
            &argumentMaximumSize,
            nil,
            0) == 0,
              argumentMaximum > 0
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: Int(argumentMaximum))
        var size = bytes.count
        var query = [CTL_KERN, KERN_PROCARGS2, processIdentifier]
        let status = query.withUnsafeMutableBufferPointer { queryBuffer in
            bytes.withUnsafeMutableBytes { byteBuffer in
                sysctl(
                    queryBuffer.baseAddress,
                    u_int(queryBuffer.count),
                    byteBuffer.baseAddress,
                    &size,
                    nil,
                    0)
            }
        }
        guard status == 0, size >= MemoryLayout<Int32>.size else { return nil }
        return decode(Array(bytes.prefix(size)))
    }

    static func decode(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argumentCount = bytes.withUnsafeBytes {
            $0.loadUnaligned(as: Int32.self)
        }
        guard argumentCount >= 0 else { return nil }

        var cursor = MemoryLayout<Int32>.size
        while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
        while cursor < bytes.count, bytes[cursor] == 0 { cursor += 1 }

        var result: [String] = []
        for _ in 0..<Int(argumentCount) {
            guard cursor <= bytes.count else { return nil }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
            guard cursor < bytes.count,
                  let value = String(bytes: bytes[start..<cursor], encoding: .utf8)
            else { return nil }
            result.append(value)
            cursor += 1
        }
        return result
    }
}
