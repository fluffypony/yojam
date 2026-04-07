import AppKit
import Combine
import Sparkle
import SwiftUI
import TipKit
import YojamCore

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

    // MARK: - Auto Update (Sparkle)
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)
    var updater: SPUUpdater { updaterController.updater }

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
    private var pendingRequests: [IncomingLinkRequest] = []
    private var isFinishedLaunching = false

    override init() {
        let store = settingsStore
        browserManager = BrowserManager(settingsStore: store)
        ruleEngine = RuleEngine(settingsStore: store)
        urlRewriter = URLRewriter(settingsStore: store)
        utmStripper = UTMStripper(settingsStore: store)
        super.init()
        NSApp.servicesProvider = self
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Prevent Yojam from appearing in Cmd+Tab and the Dock.
        // Two-step: .prohibited first to avoid a brief Dock icon flash,
        // then .accessory in didFinishLaunching so we can show windows.
        NSApp.setActivationPolicy(.prohibited)

        // Register URL handler early so cold-launch URLs aren't lost.
        // URLs arriving before didFinishLaunching are queued in pendingRequests.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // TipKit
        try? Tips.configure([
            .displayFrequency(.daily),
            .datastoreLocation(.applicationDefault)
        ])

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
            onReopen: { [weak self] url in
                let request = IncomingLinkRequest(url: url, origin: .clipboard)
                self?.enqueueOrHandle(request)
            },
            onOpenPreferences: { [weak self] in self?.showPreferences() },
            onToggleEnabled: { [weak self] in
                self?.settingsStore.isEnabled.toggle()
            },
            onShowQuickStart: { [weak self] in
                guard let self else { return }
                self.settingsStore.hasDismissedQuickStart = false
                self.showPreferences()
            },
            onShowKeyboardShortcuts: { [weak self] in
                guard let self else { return }
                self.settingsStore.pendingScrollToSection = "Picker"
                self.showPreferences()
            },
            onCheckForUpdates: { [weak self] in
                self?.updater.checkForUpdates()
            },
            canCheckForUpdates: { [weak self] in
                self?.updater.canCheckForUpdates ?? false
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
            // Auto-open Preferences so the user sees the Quick Start card
            if pendingRequests.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showPreferences()
                }
            }
        }

        // Install native messaging host manifests on every launch to
        // repair them after the app bundle is moved.
        NativeMessagingInstaller.installAll()

        // Profile discovery - async to avoid blocking launch.
        // Auto-assign the default profile to each base browser entry.
        // Users who want additional profiles as separate picker entries
        // can add the browser again via + and select a different profile.
        // Pending URLs are drained AFTER profile discovery completes
        // to avoid opening the first URL without the intended profile.
        let profileDiscovery = ProfileDiscovery()
        Task { @MainActor in
            var changed = false
            for i in browserManager.browsers.indices {
                // Only process base entries that don't have a profile set yet
                guard browserManager.browsers[i].profileId == nil else { continue }
                let bundleId = browserManager.browsers[i].bundleIdentifier
                let profiles = await Task.detached {
                    profileDiscovery.discoverProfiles(for: bundleId)
                }.value
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
            // Now that profiles are assigned, drain pending queue.
            // Small delay so the window server has finished processing the
            // activation policy before the picker tries NSApp.activate().
            // Use enqueueOrHandle so shortlink resolution is applied.
            let requests = self.pendingRequests
            self.pendingRequests.removeAll()
            // Flip BEFORE drain so enqueueOrHandle doesn't re-queue them.
            self.isFinishedLaunching = true
            if !requests.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self else { return }
                    for request in requests {
                        self.enqueueOrHandle(request)
                    }
                }
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

    // MARK: - Unified Ingress Coordinator

    /// Public entry point for AppIntents and other in-process callers
    /// that need to route an IncomingLinkRequest through the unified pipeline.
    func routeIncomingRequest(_ request: IncomingLinkRequest) {
        enqueueOrHandle(request)
    }

    /// Single entry point for all ingress paths. Queues requests during cold
    /// launch, then routes them once subsystems are ready.
    private func enqueueOrHandle(_ request: IncomingLinkRequest) {
        guard isFinishedLaunching else {
            pendingRequests.append(request)
            return
        }
        // Opt-in shortlink resolution: async pre-stage before routing
        if settingsStore.shortlinkResolutionEnabled,
           let host = request.url.host?.lowercased(),
           ShortlinkResolver.defaultShortenerHosts.contains(host) {
            Task { @MainActor in
                let resolved = await ShortlinkResolver.shared.resolve(request.url)
                let resolvedRequest = IncomingLinkRequest(
                    url: resolved,
                    sourceAppBundleId: request.sourceAppBundleId,
                    origin: request.origin,
                    modifierFlags: request.modifierFlags,
                    receivedAt: request.receivedAt,
                    metadata: request.metadata,
                    forcedBrowserBundleId: request.forcedBrowserBundleId,
                    forcePicker: request.forcePicker,
                    forcePrivateWindow: request.forcePrivateWindow
                )
                self.handleIncomingRequest(resolvedRequest)
            }
            return
        }
        handleIncomingRequest(request)
    }

    /// Process an incoming link request through the routing pipeline.
    /// Calls `RoutingService.decide()` from YojamCore and executes the result.
    private func handleIncomingRequest(_ request: IncomingLinkRequest) {
        let config = buildRoutingConfiguration()
        let decision = RoutingService.decide(request: request, configuration: config)
        executeRouteDecision(decision, request: request)
    }

    /// Snapshot the current routing state for RoutingService.
    private func buildRoutingConfiguration() -> RoutingConfiguration {
        let browsers = browserManager.browsers.filter { $0.enabled && $0.isInstalled }
        let emailClients = browserManager.emailClients.filter { $0.enabled && $0.isInstalled }
        let rules = ruleEngine.rules.filter(\.enabled).sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.priority < $1.priority
        }.filter { rule in
            // Pre-filter for installed targets (RoutingService has no NSWorkspace)
            let isPath = rule.targetBundleId.hasPrefix("/")
            return isPath
                ? FileManager.default.isExecutableFile(atPath: rule.targetBundleId)
                : (NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: rule.targetBundleId) != nil)
        }
        let globalRules = settingsStore.loadGlobalRewriteRules().filter {
            $0.enabled && $0.scope == .global
        }
        let utmParams = Set(settingsStore.utmStripList.map { $0.lowercased() })

        return RoutingConfiguration(
            browsers: browsers,
            emailClients: emailClients,
            rules: rules,
            globalRewriteRules: globalRules,
            utmStripParameters: utmParams,
            globalUTMStrippingEnabled: settingsStore.globalUTMStrippingEnabled,
            activationMode: settingsStore.activationMode,
            defaultSelectionBehavior: settingsStore.defaultSelectionBehavior,
            isEnabled: settingsStore.isEnabled,
            learnedDomainPreferences: routingSuggestionEngine.allSuggestions(),
            lastUsedBrowserId: browserManager.lastUsedId(isEmail: false),
            lastUsedEmailClientId: browserManager.lastUsedId(isEmail: true)
        )
    }

    /// Execute a RouteDecision from RoutingService via app-only executors.
    private func executeRouteDecision(_ decision: RouteDecision, request: IncomingLinkRequest) {
        // Hoist deduplication to top so ALL decision paths are deduped,
        // including .openSystemMailHandler (prevents mailto loop when
        // Yojam is the default mail handler and routing is disabled).
        let deduplicationURL: URL
        switch decision {
        case .openDirect(_, let url, _, _): deduplicationURL = url
        case .showPicker(_, _, let url, _, _): deduplicationURL = url
        case .openSystemDefault(let url): deduplicationURL = url
        case .openSystemMailHandler(let url): deduplicationURL = url
        }
        let urlKey = deduplicationURL.absoluteString
        let now = Date()
        if let lastRouted = recentlyRoutedURLs[urlKey],
           now.timeIntervalSince(lastRouted) < deduplicationWindow { return }
        recentlyRoutedURLs[urlKey] = now
        recentlyRoutedURLs = recentlyRoutedURLs.filter { now.timeIntervalSince($0.value) < 5 }

        // Structured decision log
        DecisionTrace.shared.log(inputURL: request.url, decision: decision, request: request)

        switch decision {
        case .openDirect(let entry, let finalURL, let privateWindow, _):

            recentURLsManager.add(finalURL, retention: settingsStore.recentURLRetention)
            if let domain = finalURL.host?.lowercased() {
                routingSuggestionEngine.recordChoice(domain: domain, entryId: entry.id.uuidString)
            }

            guard let resolvedAppURL = appURL(for: entry.bundleIdentifier) else { return }
            openURL(finalURL, withAppAt: resolvedAppURL,
                    profile: entry.profileId,
                    bundleId: entry.bundleIdentifier,
                    privateWindow: privateWindow,
                    customLaunchArgs: entry.customLaunchArgs)

        case .showPicker(let entries, let preselectedIndex, let finalURL, let isEmail, let reason):
            recentURLsManager.add(finalURL, retention: settingsStore.recentURLRetention)

            // Compute smart routing reason when none was provided
            var effectiveReason = reason
            if effectiveReason == nil,
               settingsStore.defaultSelectionBehavior == .smart,
               let domain = finalURL.host?.lowercased(),
               routingSuggestionEngine.suggestion(for: domain) != nil {
                effectiveReason = "Suggested based on your history for \(finalURL.host ?? domain)"
            }

            guard !entries.isEmpty else {
                if isEmail { NSWorkspace.shared.open(finalURL) }
                else { openInDefaultBrowser(finalURL) }
                return
            }
            let clampedIndex = min(max(preselectedIndex, 0), entries.count - 1)
            pickerPanel?.close()
            pickerPanel = PickerPanel(
                url: finalURL, entries: entries,
                preselectedIndex: clampedIndex,
                settingsStore: settingsStore,
                matchReason: effectiveReason,
                onSelect: { [weak self] entry, selectedURL in
                    self?.handlePickerSelection(entry: entry, url: selectedURL, isEmail: isEmail)
                },
                onCopy: { [weak self] url in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    self?.clipboardMonitor?.updateExpectedChangeCount()
                },
                onDismiss: { [weak self] panel in
                    guard self?.pickerPanel === panel else { return }
                    self?.pickerPanel = nil
                    if NSApp.activationPolicy() == .regular {
                        let prefsOpen = NSApp.windows.contains { window in
                            !(window is NSPanel) && window.isVisible && window.frame.width > 100
                        }
                        if !prefsOpen { NSApp.setActivationPolicy(.accessory) }
                    }
                })
            pickerPanel?.showAtCursor()

        case .openSystemDefault(let url):
            openInDefaultBrowser(url)

        case .openSystemMailHandler(let url):
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - URL Handling (Apple Events)

    @objc private func handleGetURL(
        event: NSAppleEventDescriptor,
        reply: NSAppleEventDescriptor
    ) {
        // Capture modifiers immediately to avoid race condition
        let modifiers = NSEvent.modifierFlags
        guard let urlString = event.paramDescriptor(
            forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }

        // Handle yojam:// scheme before anything else
        if url.scheme?.lowercased() == "yojam" {
            guard let command = YojamCommand.parse(url) else {
                YojamLogger.shared.log("Rejected malformed yojam:// URL: \(url)")
                return
            }
            switch command {
            case .route(let request):
                enqueueOrHandle(request)
            case .openSettings:
                showPreferences()
            }
            return
        }

        let sourceAppBundleId = SourceAppResolver.resolveSourceApp(
            from: event)

        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: sourceAppBundleId,
            origin: .defaultHandler,
            modifierFlags: modifiers.rawValue
        )

        enqueueOrHandle(request)
    }

    /// Handles file open events from Finder (e.g. double-clicking an .html
    /// file when Yojam is the default handler for that type), AirDropped
    /// .webloc files, and other internet-location files.
    func application(_ application: NSApplication, open urls: [URL]) {
        let modifiers = NSEvent.modifierFlags

        let sourceAppBundleId: String? = NSAppleEventManager.shared()
            .currentAppleEvent
            .flatMap { SourceAppResolver.resolveSourceApp(from: $0) }

        for incoming in urls {
            // Normalize through IncomingLinkExtractor for .webloc/.url support
            guard let normalized = IncomingLinkExtractor.normalize(incoming) else {
                YojamLogger.shared.log("Refused inbound file: \(incoming.path)")
                continue
            }

            // Determine origin. Internet-location files (.webloc/.inetloc/.url)
            // could come from AirDrop or from Finder double-click. We tag as
            // .airdrop only when the source app is the AirDrop/Sharing agent;
            // otherwise it's a normal file open.
            let origin: IngressOrigin
            let isInternetLocationFile: Bool
            if incoming.isFileURL {
                let ext = incoming.pathExtension.lowercased()
                isInternetLocationFile = ["webloc", "inetloc", "url"].contains(ext)
                // Only mark as airdrop when source is the sharing daemon.
                // A nil source with an internet-location file is more likely
                // a normal Finder open, not AirDrop.
                let isFromAirDrop = sourceAppBundleId == "com.apple.sharingd"
                origin = isFromAirDrop ? .airdrop : .fileOpen
            } else {
                isInternetLocationFile = false
                origin = .fileOpen
            }

            let effectiveSource: String?
            if origin == .airdrop {
                effectiveSource = SourceAppSentinel.airdrop
            } else if isInternetLocationFile {
                // Internet-location file opened from Finder — preserve
                // the actual source app if we have one.
                effectiveSource = sourceAppBundleId
            } else {
                effectiveSource = sourceAppBundleId
            }

            let request = IncomingLinkRequest(
                url: normalized,
                sourceAppBundleId: effectiveSource,
                origin: origin,
                modifierFlags: modifiers.rawValue
            )
            enqueueOrHandle(request)
        }
    }

    // MARK: - Handoff

    func application(_ application: NSApplication,
                     willContinueUserActivityWithType userActivityType: String) -> Bool {
        return userActivityType == NSUserActivityTypeBrowsingWeb
    }

    func application(_ application: NSApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        let modifiers = NSEvent.modifierFlags
        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: SourceAppSentinel.handoff,
            origin: .handoff,
            modifierFlags: modifiers.rawValue
        )
        enqueueOrHandle(request)
        return true
    }

    func application(_ application: NSApplication,
                     didFailToContinueUserActivityWithType userActivityType: String,
                     error: any Error) {
        YojamLogger.shared.log("Handoff continuation failed for \(userActivityType): \(error)")
    }

    // MARK: - Services Menu

    @objc func openURLViaService(_ pasteboard: NSPasteboard,
                                 userData: String?,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let candidates: [URL]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            candidates = urls
        } else if let text = pasteboard.string(forType: .string) {
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(text.startIndex..., in: text)
            candidates = detector?.matches(in: text, range: range).compactMap(\.url) ?? []
        } else {
            candidates = []
        }
        let modifiers = NSEvent.modifierFlags
        for url in candidates {
            let request = IncomingLinkRequest(
                url: url,
                sourceAppBundleId: SourceAppSentinel.servicesMenu,
                origin: .servicesMenu,
                modifierFlags: modifiers.rawValue
            )
            enqueueOrHandle(request)
        }
    }

    // MARK: - Legacy Routing (thin wrapper around unified pipeline)

    /// Legacy entry point. Constructs an `IncomingLinkRequest` and routes
    /// through the unified `RoutingService.decide` pipeline.
    func routeURL(
        _ url: URL, sourceAppBundleId: String? = nil,
        modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags,
        forcePicker: Bool = false,
        forcePrivateWindow: Bool = false,
        forcedBrowserBundleId: String? = nil
    ) {
        let request = IncomingLinkRequest(
            url: url,
            sourceAppBundleId: sourceAppBundleId,
            origin: .defaultHandler,
            modifierFlags: modifiers.rawValue,
            forcedBrowserBundleId: forcedBrowserBundleId,
            forcePicker: forcePicker,
            forcePrivateWindow: forcePrivateWindow
        )
        enqueueOrHandle(request)
    }

    private func handlePickerSelection(
        entry: BrowserEntry, url: URL, isEmail: Bool
    ) {
        var finalURL = url
        finalURL = urlRewriter.applyBrowserRewrites(
            to: finalURL, browser: entry)

        if entry.stripUTMParams {
            finalURL = utmStripper.strip(finalURL)
        } else if settingsStore.globalUTMStrippingEnabled {
            finalURL = utmStripper.strip(finalURL)
        }

        guard let appURL = appURL(for: entry.bundleIdentifier) else {
            YojamLogger.shared.log("Cannot open \(entry.displayName): application not found at \(entry.bundleIdentifier)")
            return
        }

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
            if ProfileLaunchHelper.openPrivateWindowViaAppleScript(
                url: url, appName: appName) {
                return
            }
        }

        // Custom CLI launch: run the app executable with user-defined args
        if let template = customLaunchArgs, !template.isEmpty {
            let execURL: URL
            if appURL.pathExtension == "app" {
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
                execURL = appURL
            }

            var args = shellSplitArguments(template)
                .map { $0.replacingOccurrences(of: "$URL", with: url.absoluteString) }

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
            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    let status = proc.terminationStatus
                    Task { @MainActor in
                        YojamLogger.shared.log(
                            "Custom launch exited with status \(status)")
                    }
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

        if !arguments.isEmpty {
            let execURL: URL
            if appURL.pathExtension == "app" {
                if let bundle = Bundle(url: appURL), let exec = bundle.executableURL {
                    execURL = exec
                } else {
                    let name = appURL.deletingPathExtension().lastPathComponent
                    execURL = appURL
                        .appendingPathComponent("Contents/MacOS")
                        .appendingPathComponent(name)
                }
            } else {
                execURL = appURL
            }

            let process = Process()
            process.executableURL = execURL
            process.arguments = arguments + [url.absoluteString]
            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    let status = proc.terminationStatus
                    Task { @MainActor in
                        YojamLogger.shared.log("Profile launch exited with status \(status)")
                    }
                }
            }
            do {
                try process.run()
                if let bundleId,
                   let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                    app.activate()
                }
            } catch {
                YojamLogger.shared.log("Profile launch failed: \(error.localizedDescription)")
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.arguments = arguments
                Task {
                    try? await NSWorkspace.shared.open(
                        [url], withApplicationAt: appURL, configuration: config)
                }
            }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

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

    /// Split a string of command-line arguments respecting single and double quotes.
    private func shellSplitArguments(_ template: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote: Character? = nil
        for ch in template {
            if let q = inQuote {
                if ch == q { inQuote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                inQuote = ch
            } else if ch == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

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

    /// Resolve a browser entry's identifier to an app/executable URL.
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
                let request = IncomingLinkRequest(
                    url: url,
                    origin: .clipboard
                )
                self?.enqueueOrHandle(request)
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

        self.bringPreferencesToFront(attempts: 5)
        startWindowCloseObserver()
    }

    private func bringPreferencesToFront(attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate()
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                return
            }
            if attempts > 1 {
                self?.bringPreferencesToFront(attempts: attempts - 1)
            }
        }
    }

    private var windowCheckTimer: Timer?
    private var settingsWindowKVO: NSKeyValueObservation?

    private func startWindowCloseObserver() {
        stopWindowCloseObserver()

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

        windowCheckTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.checkWindowServerAndHide() }
        }
    }

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
                  layer == 0
            else { return false }
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
