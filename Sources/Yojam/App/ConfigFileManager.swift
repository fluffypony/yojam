import Foundation

/// Two-way sync between SettingsStore and a flat JSON file at
/// `~/Library/Application Support/Yojam/config.json`.
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
    let configPath: URL
    private var fsSource: DispatchSourceFileSystemObject?
    private let settingsStore: SettingsStore
    private var lastSelfWriteAt: Date = .distantPast
    private let selfWriteEpsilon: TimeInterval = 1.0

    /// Canonical on-disk path. Exposed as a static helper so UI code that
    /// doesn't hold a ConfigFileManager (e.g. AdvancedTab) can display and
    /// act on the same location without duplicating the constant.
    static var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yojam/config.json")
    }

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.configPath = Self.configPath
    }

    deinit {
        fsSource?.cancel()
    }

    func start() {
        let dir = configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Seed the file on first run.
        if !FileManager.default.fileExists(atPath: configPath.path) {
            writeConfig()
        }
        startWatching()
    }

    // MARK: - Writing

    func writeConfig() {
        do {
            let data = try settingsStore.exportJSON()
            let tempPath = configPath.appendingPathExtension("tmp")
            try data.write(to: tempPath, options: .atomic)
            if FileManager.default.fileExists(atPath: configPath.path) {
                _ = try? FileManager.default.replaceItemAt(configPath, withItemAt: tempPath)
            } else {
                try FileManager.default.moveItem(at: tempPath, to: configPath)
            }
            lastSelfWriteAt = Date()
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
        // Ignore events we triggered ourselves (write path does atomic rename).
        if Date().timeIntervalSince(lastSelfWriteAt) < selfWriteEpsilon {
            return
        }
        guard let data = try? Data(contentsOf: configPath) else { return }
        do {
            try settingsStore.importJSON(data)
            YojamLogger.shared.log("ConfigFileManager: imported external edit from \(configPath.lastPathComponent)")
        } catch {
            YojamLogger.shared.log("ConfigFileManager: external edit invalid (\(error.localizedDescription))")
        }
    }
}
