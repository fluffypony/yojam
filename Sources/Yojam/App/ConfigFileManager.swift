import Combine
import Foundation

/// Two-way sync between SettingsStore and a flat JSON file at
/// the default config path or a user-selected custom path.
///
/// Power users can check this file into dotfiles, edit it in $EDITOR, and
/// see their changes picked up without restarting Yojam.
///
/// Not intended as the canonical source of truth — App Group `UserDefaults`
/// remains authoritative for performance (extensions read it directly). The
/// file is a human-editable mirror. Writes from the app are debounced and
/// atomic; external edits are detected via `DispatchSource.FileSystemObject`
/// with a small debounce to ignore our own writes.
@MainActor
final class ConfigFileManager {
    /// On-disk location of the flat-file mirror. Exposed so the
    /// Advanced tab can surface the path and hand it to NSWorkspace/Finder.
    private(set) var configPath: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private let settingsStore: SettingsStore
    private let onImport: (() -> Void)?
    private var pathSubscription: AnyCancellable?
    private var lastSelfWriteAt: Date = .distantPast
    private var lastSelfWriteData: Data?
    private let selfWriteEpsilon: TimeInterval = 1.0

    /// Default on-disk path for the flat-file mirror.
    static var defaultConfigPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yojam/config.json")
    }

    static func configPath(for settingsStore: SettingsStore) -> URL {
        guard let rawPath = settingsStore.configFilePath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return defaultConfigPath
        }
        return URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            .standardizedFileURL
    }

    init(settingsStore: SettingsStore, onImport: (() -> Void)? = nil) {
        self.settingsStore = settingsStore
        self.onImport = onImport
        self.configPath = Self.configPath(for: settingsStore)
        self.pathSubscription = settingsStore.$configFilePath
            .dropFirst()
            .sink { [weak self] _ in
                self?.switchToConfiguredPath()
            }
    }

    deinit {
        fsSource?.cancel()
    }

    func start() {
        let dir = configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if isUsingCustomPath,
           FileManager.default.fileExists(atPath: configPath.path) {
            importExistingConfig()
        } else if !FileManager.default.fileExists(atPath: configPath.path) {
            writeConfig()
        }
        startWatching()
    }

    private var isUsingCustomPath: Bool {
        guard let path = settingsStore.configFilePath?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !path.isEmpty
    }

    private func switchToConfiguredPath() {
        let newPath = Self.configPath(for: settingsStore)
        guard newPath != configPath else { return }
        fsSource?.cancel()
        fsSource = nil
        configPath = newPath
        writeConfig()
        startWatching()
    }

    private func importExistingConfig() {
        guard let data = try? Data(contentsOf: configPath), !data.isEmpty else {
            writeConfig()
            return
        }
        do {
            try settingsStore.importConfigMirrorJSON(data)
            onImport?()
            YojamLogger.shared.log("ConfigFileManager: imported config from \(configPath.lastPathComponent)")
        } catch {
            YojamLogger.shared.log("ConfigFileManager: startup import invalid (\(error.localizedDescription))")
        }
    }

    // MARK: - Writing

    func writeConfig() {
        do {
            try FileManager.default.createDirectory(
                at: configPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try settingsStore.exportJSON()
            let tempPath = configPath.appendingPathExtension("tmp")
            try data.write(to: tempPath, options: .atomic)
            if FileManager.default.fileExists(atPath: configPath.path) {
                _ = try FileManager.default.replaceItemAt(configPath, withItemAt: tempPath)
            } else {
                try FileManager.default.moveItem(at: tempPath, to: configPath)
            }
            lastSelfWriteAt = Date()
            lastSelfWriteData = data
        } catch {
            YojamLogger.shared.log("ConfigFileManager: write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Watching

    private func startWatching() {
        fsSource?.cancel()
        let fd = open(configPath.path, O_EVTONLY)
        guard fd >= 0 else {
            YojamLogger.shared.log("ConfigFileManager: cannot open \(configPath.path) for watching")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in
            self?.handleExternalChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fsSource = source
    }

    private func handleExternalChange() {
        // Always re-arm the watcher regardless of success/failure: the old fd
        // no longer points at the current inode after any write/rename/delete.
        // defer ensures we re-arm even if the file was deleted (recreating the
        // watcher will re-seed on the next writeConfig call).
        defer {
            // If the file exists, re-arm on the fresh inode. If it was deleted,
            // seed it again so downstream edits still get picked up.
            if !FileManager.default.fileExists(atPath: configPath.path) {
                writeConfig()
            }
            startWatching()
        }
        guard let data = try? Data(contentsOf: configPath) else { return }
        // Ignore only our own write content. A remote sync update that lands
        // inside this time window should still import if the file differs.
        if Date().timeIntervalSince(lastSelfWriteAt) < selfWriteEpsilon,
           data == lastSelfWriteData {
            return
        }
        do {
            try settingsStore.importConfigMirrorJSON(data)
            onImport?()
            YojamLogger.shared.log("ConfigFileManager: imported external edit from \(configPath.lastPathComponent)")
        } catch {
            YojamLogger.shared.log("ConfigFileManager: external edit invalid (\(error.localizedDescription))")
        }
    }
}
