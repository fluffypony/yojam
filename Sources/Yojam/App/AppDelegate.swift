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

        // First launch
        if settingsStore.isFirstLaunch {
            DefaultBrowserManager.promptSetDefault()
            settingsStore.isFirstLaunch = false
        }

        // Profile discovery
        let profileDiscovery = ProfileDiscovery()
        for entry in browserManager.browsers {
            let profiles = profileDiscovery.discoverProfiles(
                for: entry.bundleIdentifier)
            if profiles.count > 1 {
                YojamLogger.shared.log(
                    "Found \(profiles.count) profiles for \(entry.displayName)")
            }
        }
    }

    // MARK: - URL Handling

    @objc private func handleGetURL(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(
            forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        let sourceAppBundleId = SourceAppResolver.resolveSourceApp(
            from: event)
        routeURL(url, sourceAppBundleId: sourceAppBundleId)
    }

    func routeURL(_ url: URL, sourceAppBundleId: String? = nil) {
        guard settingsStore.isEnabled else {
            openInDefaultBrowser(url)
            return
        }

        recentURLsManager.add(url)

        var processedURL = url

        // Step 1: Global rewrites
        processedURL = urlRewriter.applyGlobalRewrites(to: processedURL)

        // Step 2: Global UTM stripping
        if settingsStore.globalUTMStrippingEnabled {
            processedURL = utmStripper.strip(processedURL)
        }

        // Step 3: Check mailto
        if processedURL.scheme == "mailto" {
            handleMailtoURL(processedURL)
            return
        }

        // Step 4: Check force-picker from modifier click
        let forcePicker = forcePickerForNextURL
        forcePickerForNextURL = false

        // Step 5: Evaluate rules (with source app context)
        if !forcePicker,
           let match = ruleEngine.evaluate(
               processedURL, sourceAppBundleId: sourceAppBundleId
           ) {
            processedURL = urlRewriter.applyRuleRewrites(
                to: processedURL, rule: match)
            if match.stripUTMParams {
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
                    if NSEvent.modifierFlags.contains(.shift) {
                        showPicker(
                            for: processedURL,
                            preselectedBundleId: match.targetBundleId)
                    } else {
                        openURL(processedURL, withAppAt: appURL)
                    }
                case .smartFallback:
                    openURL(processedURL, withAppAt: appURL)
                }
                return
            }
        }

        // Step 6: No rule matched or force picker
        switch settingsStore.activationMode {
        case .always, .smartFallback:
            showPicker(for: processedURL)
        case .holdShift:
            if forcePicker || NSEvent.modifierFlags.contains(.shift) {
                showPicker(for: processedURL)
            } else {
                openInDefaultBrowser(processedURL)
            }
        }
    }

    private func handleMailtoURL(_ url: URL) {
        let clients = browserManager.emailClients.filter(\.enabled)
        if clients.count == 1, let client = clients.first,
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
                entries: entries, url: url)
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
        if entry.stripUTMParams {
            finalURL = utmStripper.strip(finalURL)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: entry.bundleIdentifier
        ) else { return }

        browserManager.recordLastUsed(entry, isEmail: isEmail)

        if let domain = finalURL.host?.lowercased() {
            routingSuggestionEngine.recordChoice(
                domain: domain, bundleId: entry.bundleIdentifier)
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

        if let profile, let bundleId {
            config.arguments = ProfileLaunchHelper.launchArguments(
                forProfile: profile, browserBundleId: bundleId)
        } else if privateWindow, let bundleId {
            config.arguments = ProfileLaunchHelper
                .privateWindowArguments(browserBundleId: bundleId)
        }

        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL,
            configuration: config
        ) { _, error in
            if let error {
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
            NSWorkspace.shared.open(url)
            return
        }
        var processedURL = url
        processedURL = urlRewriter.applyBrowserRewrites(
            to: processedURL, browser: first)
        if first.stripUTMParams {
            processedURL = utmStripper.strip(processedURL)
        }
        openURL(
            processedURL, withAppAt: appURL,
            profile: first.profileId,
            bundleId: first.bundleIdentifier)
    }

    private func resolveDefaultIndex(
        entries: [BrowserEntry], url: URL
    ) -> Int {
        switch settingsStore.defaultSelectionBehavior {
        case .alwaysFirst:
            return 0
        case .lastUsed:
            return browserManager.lastUsedIndex(isEmail: false)
        case .smart:
            if let domain = url.host?.lowercased(),
               let suggestedBundleId = routingSuggestionEngine
                   .suggestion(for: domain),
               let idx = entries.firstIndex(where: {
                   $0.bundleIdentifier == suggestedBundleId
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
