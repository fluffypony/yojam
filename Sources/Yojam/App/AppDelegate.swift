import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Core Subsystems
    let settingsStore = SettingsStore()
    let browserManager: BrowserManager
    let ruleEngine: RuleEngine
    let urlRewriter: URLRewriter
    let utmStripper: UTMStripper
    let recentURLsManager = RecentURLsManager()
    let routingSuggestionEngine = RoutingSuggestionEngine()

    /// Bridged from YojamApp so we can open Settings from AppKit code
    /// without the deprecated showSettingsWindow: selector.
    var openSettingsAction: OpenSettingsAction?

    // MARK: - Detection
    private var appInstallMonitor: AppInstallMonitor!
    private var workspaceObserver: WorkspaceObserver!
    private var periodicScanner: PeriodicScanner!
    private var changeReconciler: ChangeReconciler!

    // MARK: - UI
    private var statusBarController: StatusBarController!
    private var pickerPanel: PickerPanel?

    // MARK: - Optional subsystems
    private var clipboardMonitor: ClipboardMonitor?
    private var iCloudSyncManager: ICloudSyncManager?

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var recentlyRoutedURLs: [String: Date] = [:]
    private let deduplicationWindow: TimeInterval = 0.5
    private var pendingURLs: [(URL, String?, NSEvent.ModifierFlags)] = []
    private var isFinishedLaunching = false

    override init() {
        let store = settingsStore
        browserManager = BrowserManager(settingsStore: store)
        ruleEngine = RuleEngine(settingsStore: store)
        urlRewriter = URLRewriter(settingsStore: store)
        utmStripper = UTMStripper(settingsStore: store)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Prevent Yojam from appearing in Cmd+Tab and the Dock.
        // Two-step: .prohibited first to avoid a brief Dock icon flash,
        // then .accessory in didFinishLaunching so we can show windows.
        NSApp.setActivationPolicy(.prohibited)

        // Register URL handler early so cold-launch URLs aren't lost.
        // URLs arriving before didFinishLaunching are queued in pendingURLs.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Detection layer
        changeReconciler = ChangeReconciler(
            browserManager: browserManager, ruleEngine: ruleEngine)
        appInstallMonitor = AppInstallMonitor(
            reconciler: changeReconciler)
        workspaceObserver = WorkspaceObserver(
            reconciler: changeReconciler)
        periodicScanner = PeriodicScanner(
            reconciler: changeReconciler,
            interval: settingsStore.periodicRescanInterval)

        appInstallMonitor.startMonitoring()
        workspaceObserver.startObserving()
        periodicScanner.start()

        // Menu bar
        statusBarController = StatusBarController(
            browserManager: browserManager,
            recentURLsManager: recentURLsManager,
            settingsStore: settingsStore,
            onReopen: { [weak self] url in self?.routeURL(url) },
            onOpenPreferences: { [weak self] in self?.showPreferences() },
            onToggleEnabled: { [weak self] in
                self?.settingsStore.isEnabled.toggle()
            })

        // Recent URL retention
        recentURLsManager.configure(
            retention: settingsStore.recentURLRetention,
            retentionMinutes: settingsStore.recentURLRetentionMinutes)

        settingsStore.$recentURLRetention.dropFirst().sink { [weak self] retention in
            guard let self else { return }
            self.recentURLsManager.configure(
                retention: retention,
                retentionMinutes: self.settingsStore.recentURLRetentionMinutes)
        }.store(in: &cancellables)

        settingsStore.$recentURLRetentionMinutes.dropFirst().sink { [weak self] minutes in
            guard let self else { return }
            self.recentURLsManager.configure(
                retention: self.settingsStore.recentURLRetention,
                retentionMinutes: minutes)
        }.store(in: &cancellables)

        // Clipboard
        if settingsStore.clipboardMonitoringEnabled {
            startClipboardMonitor()
        }

        // iCloud sync
        if settingsStore.iCloudSyncEnabled {
            iCloudSyncManager = ICloudSyncManager(
                settingsStore: settingsStore)
            iCloudSyncManager?.browserManager = browserManager
            iCloudSyncManager?.ruleEngine = ruleEngine
            iCloudSyncManager?.startSync()
        }

        // Dynamic service toggles
        settingsStore.$clipboardMonitoringEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.startClipboardMonitor() }
            else { self?.clipboardMonitor?.stop(); self?.clipboardMonitor = nil }
        }.store(in: &cancellables)

        settingsStore.$iCloudSyncEnabled.dropFirst().sink { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.iCloudSyncManager = ICloudSyncManager(settingsStore: self.settingsStore)
                self.iCloudSyncManager?.browserManager = self.browserManager
                self.iCloudSyncManager?.ruleEngine = self.ruleEngine
                self.iCloudSyncManager?.startSync()
            } else {
                self.iCloudSyncManager?.stopSync()
                self.iCloudSyncManager = nil
            }
        }.store(in: &cancellables)

        settingsStore.$periodicRescanInterval.dropFirst().sink { [weak self] interval in
            guard let self else { return }
            self.periodicScanner.stop()
            self.periodicScanner = PeriodicScanner(
                reconciler: self.changeReconciler, interval: interval)
            self.periodicScanner.start()
        }.store(in: &cancellables)

        // First launch
        if settingsStore.isFirstLaunch {
            DefaultBrowserManager.promptSetDefault()
            settingsStore.isFirstLaunch = false
        }

        // Profile discovery - async to avoid blocking launch.
        // Auto-assign the default profile to each base browser entry.
        // Users who want additional profiles as separate picker entries
        // can add the browser again via + and select a different profile.
        let profileDiscovery = ProfileDiscovery()
        Task { @MainActor in
            var changed = false
            for i in browserManager.browsers.indices {
                // Only process base entries that don't have a profile set yet
                guard browserManager.browsers[i].profileId == nil else { continue }
                let profiles = profileDiscovery.discoverProfiles(
                    for: browserManager.browsers[i].bundleIdentifier)
                let namedProfiles = profiles.filter { !$0.name.isEmpty }
                guard namedProfiles.count > 1 else { continue }
                // Set the default profile on the base entry
                if let defaultProfile = namedProfiles.first(where: \.isDefault)
                    ?? namedProfiles.first {
                    browserManager.browsers[i].profileId = defaultProfile.id
                    browserManager.browsers[i].profileName = defaultProfile.name
                    changed = true
                }
            }
            if changed {
                browserManager.save()
                browserManager.refreshProfileSuggestions()
            }
        }

        // Process any URLs that arrived during cold launch
        isFinishedLaunching = true
        for (url, source, mods) in pendingURLs {
            routeURL(url, sourceAppBundleId: source, modifiers: mods)
        }
        pendingURLs.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appInstallMonitor.stopMonitoring()
        workspaceObserver.stopObserving()
        periodicScanner.stop()
        clipboardMonitor?.stop()
        iCloudSyncManager?.stopSync()
    }

    // MARK: - URL Handling

    @objc private func handleGetURL(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        // Capture modifiers immediately to avoid race condition
        let modifiers = NSEvent.modifierFlags
        guard let urlString = event.paramDescriptor(
            forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        let sourceAppBundleId = SourceAppResolver.resolveSourceApp(
            from: event)

        // Queue URLs that arrive before subsystems are ready (cold launch)
        guard isFinishedLaunching else {
            pendingURLs.append((url, sourceAppBundleId, modifiers))
            return
        }

        routeURL(url, sourceAppBundleId: sourceAppBundleId, modifiers: modifiers)
    }

    func routeURL(
        _ url: URL, sourceAppBundleId: String? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
        guard let url = URLSanitizer.sanitize(url) else { return }

        guard settingsStore.isEnabled else {
            openInDefaultBrowser(url)
            return
        }

        // URL deduplication
        let urlKey = url.absoluteString
        let now = Date()
        if let lastRouted = recentlyRoutedURLs[urlKey],
           now.timeIntervalSince(lastRouted) < deduplicationWindow {
            return
        }
        recentlyRoutedURLs[urlKey] = now
        recentlyRoutedURLs = recentlyRoutedURLs.filter { now.timeIntervalSince($0.value) < 5 }

        recentURLsManager.add(url, retention: settingsStore.recentURLRetention)

        var processedURL = url

        // Step 1: Global rewrites
        processedURL = urlRewriter.applyGlobalRewrites(to: processedURL)

        // §28: Check mailto before UTM stripping to avoid stripping mailto query params
        if processedURL.scheme == "mailto" {
            handleMailtoURL(processedURL, modifiers: modifiers)
            return
        }

        // Step 2: Global UTM stripping before rule evaluation
        if settingsStore.globalUTMStrippingEnabled {
            processedURL = utmStripper.strip(processedURL)
        }

        // Step 4: Evaluate rules (with source app context)
        if let match = ruleEngine.evaluate(
               processedURL, sourceAppBundleId: sourceAppBundleId
           ) {
            processedURL = urlRewriter.applyRuleRewrites(
                to: processedURL, rule: match)

            // Apply UTM stripping: rule > browser > global (already applied globally above)
            let matchedEntry = browserManager.browsers.first {
                $0.bundleIdentifier == match.targetBundleId
            }
            if match.stripUTMParams {
                processedURL = utmStripper.strip(processedURL)
            } else if let entry = matchedEntry, entry.stripUTMParams {
                processedURL = utmStripper.strip(processedURL)
            }

            if let appURL = appURL(for: match.targetBundleId) {
                switch settingsStore.activationMode {
                case .always:
                    showPicker(
                        for: processedURL,
                        preselectedBundleId: match.targetBundleId)
                case .holdShift:
                    if modifiers.contains(.shift) {
                        showPicker(
                            for: processedURL,
                            preselectedBundleId: match.targetBundleId)
                    } else {
                        // Apply browser-specific rewrites only for direct open
                        if let entry = matchedEntry {
                            processedURL = urlRewriter.applyBrowserRewrites(
                                to: processedURL, browser: entry)
                        }
                        openURL(processedURL, withAppAt: appURL,
                            profile: matchedEntry?.profileId,
                            bundleId: match.targetBundleId,
                            privateWindow: matchedEntry?.openInPrivateWindow ?? false,
                            customLaunchArgs: matchedEntry?.customLaunchArgs)
                    }
                case .smartFallback:
                    // Apply browser-specific rewrites only for direct open
                    if let entry = matchedEntry {
                        processedURL = urlRewriter.applyBrowserRewrites(
                            to: processedURL, browser: entry)
                    }
                    openURL(processedURL, withAppAt: appURL,
                        profile: matchedEntry?.profileId,
                        bundleId: match.targetBundleId,
                        privateWindow: matchedEntry?.openInPrivateWindow ?? false,
                        customLaunchArgs: matchedEntry?.customLaunchArgs)
                }
                return
            }
        }

        // Step 5: No rule matched — show picker or use default
        switch settingsStore.activationMode {
        case .always, .smartFallback:
            showPicker(for: processedURL)
        case .holdShift:
            if modifiers.contains(.shift) {
                showPicker(for: processedURL)
            } else {
                openInDefaultBrowser(processedURL)
            }
        }
    }

    private func handleMailtoURL(
        _ url: URL, modifiers: NSEvent.ModifierFlags
    ) {
        let clients = browserManager.emailClients.filter(\.enabled)

        if settingsStore.activationMode == .holdShift && modifiers.contains(.shift) {
            showPicker(for: url, isEmail: true)
            return
        }

        // §27: holdShift without Shift → open in first resolvable email client
        if settingsStore.activationMode == .holdShift && !modifiers.contains(.shift) {
            if let client = clients.first(where: { appURL(for: $0.bundleIdentifier) != nil }),
               let resolvedURL = appURL(for: client.bundleIdentifier) {
                openURL(url, withAppAt: resolvedURL,
                    profile: client.profileId,
                    bundleId: client.bundleIdentifier,
                    privateWindow: client.openInPrivateWindow,
                    customLaunchArgs: client.customLaunchArgs)
            } else {
                // No resolvable email client — fall through to system handler
                NSWorkspace.shared.open(url)
            }
            return
        }

        if settingsStore.activationMode != .always,
           clients.count == 1, let client = clients.first,
           let appURL = appURL(for: client.bundleIdentifier) {
            openURL(url, withAppAt: appURL,
                profile: client.profileId,
                bundleId: client.bundleIdentifier,
                privateWindow: client.openInPrivateWindow,
                customLaunchArgs: client.customLaunchArgs)
        } else {
            showPicker(for: url, isEmail: true)
        }
    }

    private func showPicker(
        for url: URL, preselectedBundleId: String? = nil,
        isEmail: Bool = false
    ) {
        let entries: [BrowserEntry]
        if isEmail {
            entries = browserManager.emailClients.filter { $0.enabled && $0.isInstalled }
        } else {
            // §55: Use isInstalled flag instead of redundant appURL IPC per entry
            entries = browserManager.browsers.filter { $0.enabled && $0.isInstalled }
        }

        guard !entries.isEmpty else {
            openInDefaultBrowser(url)
            return
        }

        let preselectedIndex: Int
        if let bundleId = preselectedBundleId,
           let idx = entries.firstIndex(where: {
               $0.bundleIdentifier == bundleId
           }) {
            preselectedIndex = idx
        } else {
            preselectedIndex = resolveDefaultIndex(
                entries: entries, url: url, isEmail: isEmail)
        }

        // Clamp to valid range
        let clampedIndex = min(max(preselectedIndex, 0), entries.count - 1)

        pickerPanel?.close()
        pickerPanel = PickerPanel(
            url: url, entries: entries,
            preselectedIndex: clampedIndex,
            settingsStore: settingsStore,
            onSelect: { [weak self] entry, finalURL in
                self?.handlePickerSelection(
                    entry: entry, url: finalURL, isEmail: isEmail)
            },
            onCopy: { [weak self] url in
                // §25: Suppress clipboard monitor detection of our own write
                self?.clipboardMonitor?.suppressNextChange = true
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    url.absoluteString, forType: .string)
            },
            onDismiss: { [weak self] in self?.pickerPanel = nil })
        pickerPanel?.showAtCursor()
    }

    private func handlePickerSelection(
        entry: BrowserEntry, url: URL, isEmail: Bool
    ) {
        var finalURL = url
        finalURL = urlRewriter.applyBrowserRewrites(
            to: finalURL, browser: entry)

        // Apply UTM stripping: per-browser > global
        if entry.stripUTMParams {
            finalURL = utmStripper.strip(finalURL)
        } else if settingsStore.globalUTMStrippingEnabled {
            finalURL = utmStripper.strip(finalURL)
        }

        guard let appURL = appURL(for: entry.bundleIdentifier) else { return }

        browserManager.recordLastUsed(entry, isEmail: isEmail)

        if let domain = finalURL.host?.lowercased() {
            routingSuggestionEngine.recordChoice(
                domain: domain, entryId: entry.id.uuidString)
        }

        openURL(
            finalURL, withAppAt: appURL,
            profile: entry.profileId,
            bundleId: entry.bundleIdentifier,
            privateWindow: entry.openInPrivateWindow,
            customLaunchArgs: entry.customLaunchArgs)
    }

    func openURL(
        _ url: URL, withAppAt appURL: URL,
        profile: String? = nil, bundleId: String? = nil,
        privateWindow: Bool = false,
        customLaunchArgs: String? = nil
    ) {
        // AppleScript-based private window for Safari/Orion
        if privateWindow, let bundleId,
           ProfileLaunchHelper.appleScriptPrivateWindowApps.contains(bundleId),
           let appName = ProfileLaunchHelper.appName(forBundleId: bundleId) {
            ProfileLaunchHelper.openPrivateWindowViaAppleScript(
                url: url, appName: appName)
            return
        }

        // Custom CLI launch: run the app executable with user-defined args
        if let template = customLaunchArgs, !template.isEmpty {
            let execURL: URL
            if appURL.pathExtension == "app" {
                // .app bundle — find the real executable inside
                if let bundle = Bundle(url: appURL),
                   let exec = bundle.executableURL {
                    execURL = exec
                } else {
                    let name = appURL.deletingPathExtension().lastPathComponent
                    execURL = appURL
                        .appendingPathComponent("Contents/MacOS")
                        .appendingPathComponent(name)
                }
            } else {
                // Bare executable (path stored as bundleIdentifier)
                execURL = appURL
            }

            var args = template
                .components(separatedBy: " ")
                .filter { !$0.isEmpty }
                .map { $0.replacingOccurrences(of: "$URL", with: url.absoluteString) }

            // Also honor profile and private-window settings
            if let profile, let bundleId {
                args.append(contentsOf: ProfileLaunchHelper.launchArguments(
                    forProfile: profile, browserBundleId: bundleId))
            }
            if privateWindow, let bundleId {
                args.append(contentsOf: ProfileLaunchHelper.privateWindowArguments(
                    browserBundleId: bundleId))
            }

            let process = Process()
            process.executableURL = execURL
            process.arguments = args
            // §51: Set termination handler to log completion/failure
            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    YojamLogger.shared.log(
                        "Custom launch exited with status \(proc.terminationStatus)")
                }
            }
            do {
                try process.run()
            } catch {
                YojamLogger.shared.log(
                    "Custom launch failed: \(error.localizedDescription)")
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        // Combine profile + private window arguments
        var arguments: [String] = []
        if let profile, let bundleId {
            arguments.append(contentsOf: ProfileLaunchHelper.launchArguments(
                forProfile: profile, browserBundleId: bundleId))
        }
        if privateWindow, let bundleId {
            arguments.append(contentsOf: ProfileLaunchHelper.privateWindowArguments(
                browserBundleId: bundleId))
        }
        if !arguments.isEmpty { config.arguments = arguments }

        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [url], withApplicationAt: appURL, configuration: config)
            } catch {
                YojamLogger.shared.log(
                    "Failed to open URL: \(error.localizedDescription)")
            }
        }
    }

    // §19: Iterate until an enabled browser actually resolves, not just the first enabled
    private func openInDefaultBrowser(_ url: URL) {
        guard let first = browserManager.browsers.first(where: { entry in
            entry.enabled && appURL(for: entry.bundleIdentifier) != nil
        }), let appURL = appURL(for: first.bundleIdentifier) else {
            YojamLogger.shared.log("No enabled browser available. Cannot open URL.")
            return
        }
        var processedURL = url
        processedURL = urlRewriter.applyBrowserRewrites(
            to: processedURL, browser: first)
        if first.stripUTMParams {
            processedURL = utmStripper.strip(processedURL)
        } else if settingsStore.globalUTMStrippingEnabled {
            processedURL = utmStripper.strip(processedURL)
        }
        openURL(
            processedURL, withAppAt: appURL,
            profile: first.profileId,
            bundleId: first.bundleIdentifier,
            privateWindow: first.openInPrivateWindow,
            customLaunchArgs: first.customLaunchArgs)
    }

    private func resolveDefaultIndex(
        entries: [BrowserEntry], url: URL, isEmail: Bool = false
    ) -> Int {
        switch settingsStore.defaultSelectionBehavior {
        case .alwaysFirst:
            return 0
        case .lastUsed:
            // Look up last-used UUID in the filtered entries list, not the full list
            if let lastId = browserManager.lastUsedId(isEmail: isEmail),
               let idx = entries.firstIndex(where: { $0.id == lastId }) {
                return idx
            }
            return 0
        case .smart:
            if let domain = url.host?.lowercased(),
               let suggestedEntryId = routingSuggestionEngine
                   .suggestion(for: domain),
               let idx = entries.firstIndex(where: {
                   $0.id.uuidString == suggestedEntryId
               }) {
                return idx
            }
            // §53: Removed redundant ruleEngine.evaluate — this block is only reachable
            // when the global evaluate in Step 4 already failed to find a match.
            return 0
        }
    }

    /// Resolve a browser entry's identifier to an app/executable URL.
    /// Handles both real bundle IDs and bare executable paths.
    func appURL(for bundleId: String) -> URL? {
        if bundleId.hasPrefix("/") {
            let url = URL(fileURLWithPath: bundleId)
            return FileManager.default.isExecutableFile(atPath: bundleId) ? url : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    // MARK: - Clipboard & Click Monitor

    private func startClipboardMonitor() {
        clipboardMonitor = ClipboardMonitor(
            settingsStore: settingsStore
        ) { [weak self] url in
            self?.statusBarController.showClipboardNotification(
                for: url
            ) {
                self?.routeURL(url)
            }
        }
        clipboardMonitor?.start()
    }

    func showPreferences() {
        // Show in Cmd+Tab while preferences are open
        NSApp.setActivationPolicy(.regular)

        if let openSettings = openSettingsAction {
            openSettings()
        } else {
            NSApp.sendAction(
                Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        // Delay activation until the window server has registered
        // the policy change — otherwise Yojam appears at the end
        // of the Cmd+Tab list instead of as the active app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate()
            // Bring the Settings window to front explicitly.
            // On reopen after Cmd+W, the window may not yet report
            // isVisible, so match on size instead.
            for window in NSApp.windows where !(window is NSPanel) && window.frame.width > 100 {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }

        // Watch for all windows closing to hide from Cmd+Tab again
        startWindowCloseObserver()
    }

    private var windowCheckTimer: Timer?
    private var settingsWindowKVO: NSKeyValueObservation?

    private func startWindowCloseObserver() {
        stopWindowCloseObserver()

        // Find the Settings window after a short delay (gives SwiftUI
        // time to present it) and observe its visibility via KVO.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let settingsWindow = NSApp.windows.first { window in
                !(window is NSPanel)
                    && window.isVisible
                    && window.frame.width > 100
            }
            if let settingsWindow {
                self.settingsWindowKVO = settingsWindow.observe(
                    \.isVisible, options: [.new]
                ) { [weak self] _, change in
                    if change.newValue == false {
                        DispatchQueue.main.async {
                            self?.hideFromCmdTab()
                        }
                    }
                }
            }
        }

        // Belt-and-suspenders: poll every 0.5s using the window server
        // as the source of truth (bypasses any stale isVisible state).
        // §47: Reduced polling frequency (was 0.5s)
        windowCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkWindowServerAndHide() }
        }
    }

    /// Ask the window server directly whether this process has any
    /// normal-layer (non-panel) windows on screen.
    private func checkWindowServerAndHide() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return }

        let hasOnScreenWindow = infoList.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID] as? Int32,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer] as? Int,
                  layer == 0  // kCGNormalWindowLevel
            else { return false }
            // Ignore tiny internal windows
            if let bounds = info[kCGWindowBounds] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               w <= 1 || h <= 1 {
                return false
            }
            return true
        }

        if !hasOnScreenWindow {
            hideFromCmdTab()
        }
    }

    private func hideFromCmdTab() {
        NSApp.setActivationPolicy(.accessory)
        stopWindowCloseObserver()
    }

    private func stopWindowCloseObserver() {
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
        settingsWindowKVO?.invalidate()
        settingsWindowKVO = nil
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        showPreferences()
        return false
    }
}
