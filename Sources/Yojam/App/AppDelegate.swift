import AppKit
import Combine

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
    private var globalClickMonitor: GlobalClickMonitor?
    private var iCloudSyncManager: ICloudSyncManager?

    // MARK: - State
    private var forcePickerForNextURL = false
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Global click modifier
        if settingsStore.universalClickModifierEnabled {
            startGlobalClickMonitor()
        }

        // iCloud sync
        if settingsStore.iCloudSyncEnabled {
            iCloudSyncManager = ICloudSyncManager(
                settingsStore: settingsStore)
            iCloudSyncManager?.startSync()
        }

        // Dynamic service toggles (§2.7)
        settingsStore.$clipboardMonitoringEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.startClipboardMonitor() }
            else { self?.clipboardMonitor?.stop(); self?.clipboardMonitor = nil }
        }.store(in: &cancellables)

        settingsStore.$universalClickModifierEnabled.dropFirst().sink { [weak self] enabled in
            if enabled { self?.startGlobalClickMonitor() }
            else { self?.globalClickMonitor?.stop(); self?.globalClickMonitor = nil }
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

        // Profile discovery - create profile entries (§2.6)
        let profileDiscovery = ProfileDiscovery()
        for entry in browserManager.browsers {
            let profiles = profileDiscovery.discoverProfiles(
                for: entry.bundleIdentifier)
            guard profiles.count > 1 else { continue }
            for profile in profiles {
                let alreadyExists = browserManager.browsers.contains {
                    $0.bundleIdentifier == entry.bundleIdentifier && $0.profileId == profile.id
                }
                guard !alreadyExists else { continue }
                var profileEntry = BrowserEntry(
                    bundleIdentifier: entry.bundleIdentifier,
                    displayName: "\(entry.displayName) — \(profile.name)",
                    enabled: true,
                    position: browserManager.browsers.count,
                    profileId: profile.id,
                    profileName: profile.name,
                    source: .autoDetected
                )
                profileEntry.isInstalled = entry.isInstalled
                browserManager.addBrowser(profileEntry)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appInstallMonitor.stopMonitoring()
        workspaceObserver.stopObserving()
        periodicScanner.stop()
        clipboardMonitor?.stop()
        globalClickMonitor?.stop()
        iCloudSyncManager?.stopSync()
    }

    // MARK: - URL Handling

    @objc private func handleGetURL(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        // Capture modifiers immediately to avoid race condition (§2.8)
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

        // URL deduplication (§2.14)
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

        // Step 2: Check mailto
        if processedURL.scheme == "mailto" {
            handleMailtoURL(processedURL)
            return
        }

        // Step 3: Check force-picker from modifier click
        let forcePicker = forcePickerForNextURL
        forcePickerForNextURL = false

        // Step 4: Evaluate rules (with source app context)
        if !forcePicker,
           let match = ruleEngine.evaluate(
               processedURL, sourceAppBundleId: sourceAppBundleId
           ) {
            processedURL = urlRewriter.applyRuleRewrites(
                to: processedURL, rule: match)

            // Apply UTM stripping: rule > browser > global (§2.11)
            let matchedEntry = browserManager.browsers.first {
                $0.bundleIdentifier == match.targetBundleId
            }
            if match.stripUTMParams {
                processedURL = utmStripper.strip(processedURL)
            } else if let entry = matchedEntry, entry.stripUTMParams {
                processedURL = utmStripper.strip(processedURL)
            } else if settingsStore.globalUTMStrippingEnabled {
                processedURL = utmStripper.strip(processedURL)
            }

            // Apply browser-specific rewrites (§2.5)
            if let entry = matchedEntry {
                processedURL = urlRewriter.applyBrowserRewrites(
                    to: processedURL, browser: entry)
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
                        openURL(processedURL, withAppAt: appURL,
                            profile: matchedEntry?.profileId,
                            bundleId: match.targetBundleId,
                            privateWindow: matchedEntry?.openInPrivateWindow ?? false)
                    }
                case .smartFallback:
                    openURL(processedURL, withAppAt: appURL,
                        profile: matchedEntry?.profileId,
                        bundleId: match.targetBundleId,
                        privateWindow: matchedEntry?.openInPrivateWindow ?? false)
                }
                return
            }
        }

        // Step 5: No rule matched or force picker — apply global UTM stripping
        if settingsStore.globalUTMStrippingEnabled {
            processedURL = utmStripper.strip(processedURL)
        }

        switch settingsStore.activationMode {
        case .always, .smartFallback:
            showPicker(for: processedURL)
        case .holdShift:
            if forcePicker || modifiers.contains(.shift) {
                showPicker(for: processedURL)
            } else {
                openInDefaultBrowser(processedURL)
            }
        }
    }

    private func handleMailtoURL(_ url: URL) {
        let clients = browserManager.emailClients.filter(\.enabled)
        // Respect activation mode (§2.9)
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
        let entries = isEmail
            ? browserManager.emailClients.filter(\.enabled)
            : browserManager.browsers.filter(\.enabled)

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

        pickerPanel?.close()
        pickerPanel = PickerPanel(
            url: url, entries: entries,
            preselectedIndex: preselectedIndex,
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

        // Combine profile + private window arguments (§2.2)
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

        // Use async version for @MainActor safety (§2.12)
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
        // Always target a specific app to avoid recursion (§2.13)
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

    private func startGlobalClickMonitor() {
        globalClickMonitor = GlobalClickMonitor(
            settingsStore: settingsStore
        ) { [weak self] in
            self?.forcePickerForNextURL = true
            // Auto-expire after 200ms (§2.1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.forcePickerForNextURL = false
            }
        }
        globalClickMonitor?.start()
    }

    func showPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(
                Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        showPreferences()
        return false
    }
}
