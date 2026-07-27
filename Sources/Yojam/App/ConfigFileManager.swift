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
/// atomic; external edits are detected via `DispatchSource.FileSystemObject`.
/// Repeated events are ignored by comparing their content with the last data
/// written or imported.
@MainActor
final class ConfigFileManager {
    /// On-disk location of the flat-file mirror. Exposed so the
    /// Advanced tab can surface the path and hand it to NSWorkspace/Finder.
    private(set) var configPath: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private let settingsStore: SettingsStore
    private let onImport: (() -> Void)?
    private var pathSubscription: AnyCancellable?
    private var configSubscription: AnyCancellable?
    private var pendingWrite: DispatchWorkItem?
    private var lastObservedData: Data?
    private var isApplyingExternalChange = false
    private let writeDelay: TimeInterval
    private let onWrite: (() -> Void)?

    /// Default on-disk path for the flat-file mirror.
    static var defaultConfigPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yojam/config.json")
    }

    static func configPath(for settingsStore: SettingsStore) -> URL {
        configPath(forRawPath: settingsStore.configFilePath)
    }

    private static func configPath(forRawPath rawPath: String?) -> URL {
        guard let rawPath = rawPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return defaultConfigPath
        }
        return URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            .standardizedFileURL
    }

    private static func isCustomPath(_ rawPath: String?) -> Bool {
        guard let rawPath else { return false }
        return !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        settingsStore: SettingsStore,
        writeDelay: TimeInterval = 0.3,
        onImport: (() -> Void)? = nil,
        onWrite: (() -> Void)? = nil
    ) {
        self.settingsStore = settingsStore
        self.writeDelay = writeDelay
        self.onImport = onImport
        self.onWrite = onWrite
        self.configPath = Self.configPath(for: settingsStore)
        self.pathSubscription = settingsStore.$configFilePath
            .dropFirst()
            .sink { [weak self] rawPath in
                self?.switchToConfiguredPath(rawPath)
            }
        self.configSubscription = settingsStore.routingDataDidChange
            .merge(with: settingsStore.configMirrorDataDidChange)
            .sink { [weak self] in
                self?.scheduleWrite()
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
            if importExistingConfig() {
                // One canonical write migrates 1.2.0 mirrors away from local
                // installation timestamps. Byte comparison keeps this a no-op
                // once every writer is using the portable representation.
                writeConfig()
            }
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

    private func switchToConfiguredPath(_ rawPath: String?) {
        let newPath = Self.configPath(forRawPath: rawPath)
        guard newPath != configPath else { return }
        fsSource?.cancel()
        fsSource = nil
        pendingWrite?.cancel()
        pendingWrite = nil
        configPath = newPath
        if Self.isCustomPath(rawPath),
           FileManager.default.fileExists(atPath: configPath.path) {
            // Preserve invalid or partially downloaded content instead of
            // replacing it with this Mac's current settings.
            if importExistingConfig() {
                writeConfig()
            }
        } else {
            writeConfig()
        }
        startWatching()
    }

    @discardableResult
    private func importExistingConfig() -> Bool {
        guard let data = try? Data(contentsOf: configPath), !data.isEmpty else {
            return false
        }
        do {
            isApplyingExternalChange = true
            defer { isApplyingExternalChange = false }
            try settingsStore.importConfigMirrorJSON(data)
            lastObservedData = data
            onImport?()
            YojamLogger.shared.log("ConfigFileManager: imported config from \(configPath.lastPathComponent)")
            return true
        } catch {
            YojamLogger.shared.log("ConfigFileManager: startup import invalid (\(error.localizedDescription))")
            return false
        }
    }

    // MARK: - Writing

    func scheduleWrite() {
        guard !isApplyingExternalChange else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingWrite = nil
            self.writeConfig()
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + writeDelay,
            execute: work)
    }

    func writeConfig() {
        do {
            try FileManager.default.createDirectory(
                at: configPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try settingsStore.exportConfigMirrorJSON()
            if let existing = try? Data(contentsOf: configPath), existing == data {
                lastObservedData = data
                return
            }
            let tempPath = configPath.appendingPathExtension("tmp")
            try data.write(to: tempPath, options: .atomic)
            if FileManager.default.fileExists(atPath: configPath.path) {
                _ = try FileManager.default.replaceItemAt(configPath, withItemAt: tempPath)
            } else {
                try FileManager.default.moveItem(at: tempPath, to: configPath)
            }
            lastObservedData = data
            onWrite?()
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
        // Re-arm on the current inode before reading. If a file provider
        // replaced the file while this event was queued, the read sees the
        // newest contents and any later replacement is observed by the new fd.
        fsSource?.cancel()
        fsSource = nil
        if !FileManager.default.fileExists(atPath: configPath.path) {
            writeConfig()
        }
        startWatching()

        guard let data = try? Data(contentsOf: configPath) else { return }
        // Ignore content we have already applied, regardless of how long a
        // file provider took to deliver or replay the inode replacement.
        guard data != lastObservedData else { return }
        do {
            pendingWrite?.cancel()
            pendingWrite = nil
            isApplyingExternalChange = true
            defer { isApplyingExternalChange = false }
            try settingsStore.importConfigMirrorJSON(data)
            lastObservedData = data
            onImport?()
            YojamLogger.shared.log("ConfigFileManager: imported external edit from \(configPath.lastPathComponent)")
        } catch {
            YojamLogger.shared.log("ConfigFileManager: external edit invalid (\(error.localizedDescription))")
        }
    }
}
