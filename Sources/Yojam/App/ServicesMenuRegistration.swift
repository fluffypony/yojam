import AppKit
import Foundation

/// Keeps the macOS Services registry (`pbs`) pointed at this copy of Yojam.
///
/// pbs scans app bundles and caches each app's `NSServices` entry together
/// with the bundle path it found it in. It rebuilds that cache on its own
/// schedule, mostly at login, so after an app update, a move between folders,
/// or an OS upgrade the "Open in Yojam" entry can keep pointing at a copy
/// that no longer exists. Invoking the service then does nothing at all.
/// `NSUpdateDynamicServices()` asks pbs to rescan right away; Yojam calls it
/// once for every install location and version it runs from.
enum ServicesMenuRegistration {
    enum Status: Equatable {
        /// pbs knows the service and points it at this bundle.
        case registered
        /// pbs points the service at another copy of Yojam.
        case registeredElsewhere(path: String)
        /// pbs has no entry for Yojam.
        case notRegistered
        /// pbs could not be queried.
        case unknown
    }

    static let pbsURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")

    /// Identifies the install pbs last scanned for us: path plus version, so
    /// both an update in place and a move trigger one refresh.
    static var installationKey: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(Bundle.main.bundleURL.path)|\(version)|\(build)"
    }

    /// Ask pbs to rescan installed apps now.
    static func refresh() {
        NSUpdateDynamicServices()
    }

    /// Refresh once per install location and version.
    @MainActor
    static func refreshIfNeeded(settingsStore: SettingsStore) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let key = installationKey
        guard settingsStore.lastServicesRegistrationKey != key else { return }
        refresh()
        settingsStore.lastServicesRegistrationKey = key
        YojamLogger.shared.log("Asked pbs to rescan Services for \(key)")
    }

    /// Where pbs currently points the "Open in Yojam" service. Runs pbs
    /// synchronously; the dump takes a few milliseconds.
    static func currentStatus() -> Status {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let dump = runDump() else { return .unknown }
        let paths = registeredBundlePaths(inDump: dump, bundleIdentifier: bundleIdentifier)
        return status(forRegisteredPaths: paths, currentBundlePath: Bundle.main.bundleURL.path)
    }

    static func status(forRegisteredPaths paths: [String], currentBundlePath: String) -> Status {
        let current = URL(fileURLWithPath: currentBundlePath).standardizedFileURL.path
        if paths.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == current }) {
            return .registered
        }
        if let other = paths.first {
            return .registeredElsewhere(path: other)
        }
        return .notRegistered
    }

    /// Extracts every `NSBundlePath` pbs lists for `bundleIdentifier` from a
    /// `pbs -dump_pboard` listing. Entries are old-style plist dictionaries;
    /// `NSBundleIdentifier` sorts before `NSBundlePath` inside each one.
    static func registeredBundlePaths(inDump dump: String, bundleIdentifier: String) -> [String] {
        var paths: [String] = []
        var inMatchingEntry = false
        for rawLine in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let identifier = value(ofKey: "NSBundleIdentifier", in: line) {
                inMatchingEntry = identifier == bundleIdentifier
            } else if inMatchingEntry, let path = value(ofKey: "NSBundlePath", in: line) {
                paths.append(path)
                inMatchingEntry = false
            } else if line.hasPrefix("}") {
                inMatchingEntry = false
            }
        }
        return paths
    }

    /// Parses `Key = value;` or `Key = "value";` lines.
    private static func value(ofKey key: String, in line: String) -> String? {
        let prefix = key + " = "
        guard line.hasPrefix(prefix), line.hasSuffix(";") else { return nil }
        var value = String(line.dropFirst(prefix.count).dropLast())
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
            value = value.replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }

    private static func runDump() -> String? {
        let process = Process()
        process.executableURL = pbsURL
        process.arguments = ["-dump_pboard"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            YojamLogger.shared.log("Could not run pbs: \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
