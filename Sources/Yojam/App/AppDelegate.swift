import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let settingsWindowDidClose = Notification.Name("YojamSettingsWindowDidClose")
}

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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

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

        // Clipboard
        if settingsStore.clipboardMonitoringEnabled {
            startClipboardMonitor()
        }

        // iCloud sync
        if settingsStore.iCloudSyncEnabled {
            iCloudSyncManager = ICloudSyncManager(
                settingsStore: settingsStore)
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
            }
        }
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
        routeURL(url, sourceAppBundleId: sourceAppBundleId, modifiers: modifiers)
    }

    func routeURL(
        _ url: URL, sourceAppBundleId: String? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags
    ) {
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

        recentURLsManager.add(url)

        var processedURL = url

        // Step 1: Global rewrites
        processedURL = urlRewriter.applyGlobalRewrites(to: processedURL)

        // Step 2: Global UTM stripping before rule evaluation (per spec flow step 5)
        if settingsStore.globalUTMStrippingEnabled {
            processedURL = utmStripper.strip(processedURL)
        }

        // Step 3: Check mailto
        if processedURL.scheme == "mailto" {
            handleMailtoURL(processedURL, modifiers: modifiers)
            return
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

            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: match.targetBundleId
            ) {
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
                            privateWindow: matchedEntry?.openInPrivateWindow ?? false)
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
                        privateWindow: matchedEntry?.openInPrivateWindow ?? false)
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

        if settingsStore.activationMode != .always,
           clients.count == 1, let client = clients.first,
           let appURL = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: client.bundleIdentifier
           ) {
            openURL(url, withAppAt: appURL)
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
            entries = browserManager.browsers.filter {
                $0.enabled && $0.isInstalled &&
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
            }
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
            onCopy: { url in
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

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: entry.bundleIdentifier
        ) else { return }

        browserManager.recordLastUsed(entry, isEmail: isEmail)

        if let domain = finalURL.host?.lowercased() {
            routingSuggestionEngine.recordChoice(
                domain: domain, entryId: entry.id.uuidString)
        }

        openURL(
            finalURL, withAppAt: appURL,
            profile: entry.profileId,
            bundleId: entry.bundleIdentifier,
            privateWindow: entry.openInPrivateWindow)
    }

    func openURL(
        _ url: URL, withAppAt appURL: URL,
        profile: String? = nil, bundleId: String? = nil,
        privateWindow: Bool = false
    ) {
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

    private func openInDefaultBrowser(_ url: URL) {
        guard let first = browserManager.browsers.first(where: \.enabled),
              let appURL = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: first.bundleIdentifier
              ) else {
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
            privateWindow: first.openInPrivateWindow)
    }

    private func resolveDefaultIndex(
        entries: [BrowserEntry], url: URL, isEmail: Bool = false
    ) -> Int {
        switch settingsStore.defaultSelectionBehavior {
        case .alwaysFirst:
            return 0
        case .lastUsed:
            return browserManager.lastUsedIndex(isEmail: isEmail)
        case .smart:
            if let domain = url.host?.lowercased(),
               let suggestedEntryId = routingSuggestionEngine
                   .suggestion(for: domain),
               let idx = entries.firstIndex(where: {
                   $0.id.uuidString == suggestedEntryId
               }) {
                return idx
            }
            if let match = ruleEngine.evaluate(url),
               let idx = entries.firstIndex(where: {
                   $0.bundleIdentifier == match.targetBundleId
               }) {
                return idx
            }
            return 0
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate()
        }

        // Watch for all windows closing to hide from Cmd+Tab again
        startWindowCloseObserver()
    }

    private var windowObservers: [NSObjectProtocol] = []
    private var windowCheckTimer: Timer?

    private func startWindowCloseObserver() {
        guard windowObservers.isEmpty else { return }

        // Primary signal: SwiftUI .onDisappear posts this when the
        // Settings view is torn down (covers Cmd+W / close button).
        let settingsObs = NotificationCenter.default.addObserver(
            forName: .settingsWindowDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.hideFromDockIfNoWindows()
            }
        }
        windowObservers.append(settingsObs)

        // Secondary signals for edge cases (e.g. app hidden, window
        // closed programmatically, user switches away).
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
        ]
        for name in names {
            let obs = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.hideFromDockIfNoWindows()
                }
            }
            windowObservers.append(obs)
        }

        // Fallback: poll every 0.5s in case all notifications miss.
        windowCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.hideFromDockIfNoWindows() }
        }
    }

    private func hideFromDockIfNoWindows() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            guard !(window is NSPanel) else { return false }
            guard window.frame.width > 1, window.frame.height > 1 else { return false }
            return window.isVisible
        }
        guard !hasVisibleWindows else { return }
        NSApp.setActivationPolicy(.accessory)
        windowCheckTimer?.invalidate()
        windowCheckTimer = nil
        for obs in windowObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        windowObservers.removeAll()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        showPreferences()
        return false
    }
}
