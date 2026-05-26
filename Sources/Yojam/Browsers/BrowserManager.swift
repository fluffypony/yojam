import AppKit
import Combine
import YojamCore

@MainActor
final class BrowserManager: ObservableObject {
    @Published var browsers: [BrowserEntry] = []
    @Published var suggestedBrowsers: [BrowserEntry] = []
    @Published var emailClients: [BrowserEntry] = []

    private let settingsStore: SettingsStore
    private let iconResolver = IconResolver.shared

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.browsers = settingsStore.loadBrowsers()
        self.emailClients = settingsStore.loadEmailClients()
        if settingsStore.sharedStore.defaults.data(forKey: "browsers") == nil { performInitialDetection() }
        if settingsStore.sharedStore.defaults.data(forKey: "emailClients") == nil { addDefaultEmailClients() }
        deduplicateProfileEntries()
        refreshProfileSuggestions()
    }

    /// Remove duplicate profile entries and profile entries with empty names
    /// that may have been created by earlier versions of profile discovery.
    private func deduplicateProfileEntries() {
        let cleanedInput = browsers.compactMap { entry -> BrowserEntry? in
            guard !(entry.profileId != nil && (entry.profileName ?? "").isEmpty) else {
                return nil
            }
            return Self.clearingDefaultProfileSelectionIfNeeded(entry)
        }
        let mergeResult = SyncConflictResolver.mergeBrowserListsWithAliases(
            local: cleanedInput,
            remote: [])
        if mergeResult.entries != browsers {
            browsers = mergeResult.entries
            save()
            let rules = settingsStore.loadRules()
            let remapped = SyncConflictResolver.remapRuleBrowserTargets(
                rules,
                aliases: mergeResult.idAliases)
            if remapped != rules {
                settingsStore.saveRules(remapped)
            }
        }
    }

    private func performInitialDetection() {
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var position = 0
        var seenBundleIds = Set<String>()
        for appURL in httpHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  !YojamBundleIDs.isOwnedByYojam(bundleId),
                  !seenBundleIds.contains(bundleId) else { continue }
            seenBundleIds.insert(bundleId)
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? appURL.deletingPathExtension().lastPathComponent
            let entry = BrowserEntry(
                bundleIdentifier: bundleId, displayName: name,
                position: position,
                source: KnownAppAllowlist.browsers.contains(bundleId)
                    ? .autoDetected : .suggested
            )
            if KnownAppAllowlist.browsers.contains(bundleId) {
                browsers.append(entry); position += 1
            } else {
                suggestedBrowsers.append(entry)
            }
        }
        save()
    }

    private func addDefaultEmailClients() {
        let mailtoHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "mailto:test@example.com")!)
        var seenBundleIds = Set<String>()
        var pos = 0
        for appURL in mailtoHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  !YojamBundleIDs.isOwnedByYojam(bundleId),
                  !seenBundleIds.contains(bundleId) else { continue }
            seenBundleIds.insert(bundleId)
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? appURL.deletingPathExtension().lastPathComponent
            emailClients.append(BrowserEntry(
                bundleIdentifier: bundleId, displayName: name,
                position: pos, source: .autoDetected))
            pos += 1
        }
        // Add known clients not already found (no iOS-only bundle IDs)
        let knownMailClients: [(String, String)] = [
            ("com.apple.mail", "Mail"),
            ("com.microsoft.Outlook", "Outlook"),
            ("com.readdle.smartemail-macos", "Spark"),
        ]
        for (bundleId, name) in knownMailClients {
            guard !seenBundleIds.contains(bundleId),
                  NSWorkspace.shared.urlForApplication(
                      withBundleIdentifier: bundleId) != nil else { continue }
            emailClients.append(BrowserEntry(
                bundleIdentifier: bundleId, displayName: name,
                position: pos, source: .autoDetected))
            pos += 1
        }
        settingsStore.saveEmailClients(emailClients)
    }

    // MARK: - CRUD

    func addBrowser(_ entry: BrowserEntry) {
        var e = entry; e.position = browsers.count
        browsers.append(e); save()
        refreshProfileSuggestions()
    }

    func addBrowsers(_ entries: [BrowserEntry]) {
        for var entry in entries {
            entry.position = browsers.count
            browsers.append(entry)
        }
        save()
    }

    func confirmSuggested(_ entry: BrowserEntry) {
        suggestedBrowsers.removeAll { $0.id == entry.id }
        addBrowser(entry)  // addBrowser calls refreshProfileSuggestions()
    }

    func removeBrowser(at index: Int) {
        browsers.remove(at: index); reindex(); save()
        refreshProfileSuggestions()
    }

    func moveBrowser(from source: IndexSet, to destination: Int) {
        browsers.move(fromOffsets: source, toOffset: destination)
        reindex(); save()
    }

    func toggleBrowser(_ id: UUID) {
        if let idx = browsers.firstIndex(where: { $0.id == id }) {
            browsers[idx].enabled.toggle()
            browsers[idx].lastModifiedAt = Date()
            save()
        }
    }

    func updateBrowser(_ entry: BrowserEntry) {
        if let idx = browsers.firstIndex(where: { $0.id == entry.id }) {
            var updated = entry
            updated.lastModifiedAt = Date()
            browsers[idx] = updated
            save()
        }
    }

    func icon(for entry: BrowserEntry) -> NSImage {
        if let data = entry.customIconData, let img = NSImage(data: data) { return img }
        return iconResolver.icon(forBundleIdentifier: entry.bundleIdentifier)
    }

    // §11: Store and retrieve by UUID instead of positional index
    func lastUsedId(isEmail: Bool) -> UUID? {
        let key = isEmail ? "lastUsedEmailId" : "lastUsedBrowserId"
        guard let idString = settingsStore.sharedStore.defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: idString)
    }

    func recordLastUsed(_ entry: BrowserEntry, isEmail: Bool) {
        let key = isEmail ? "lastUsedEmailId" : "lastUsedBrowserId"
        settingsStore.sharedStore.defaults.set(entry.id.uuidString, forKey: key)
    }

    /// Regenerate suggested browser entries for profiles not yet in the active list.
    /// P5/B-PROFILEDISC: Runs file I/O in Task.detached, publishes results back on main.
    func refreshProfileSuggestions() {
        let activeKeys = Set(browsers.map { Self.profileSuggestionKey(for: $0) })
        let discoveryTargets = Array(browsers.reduce(into: [String: BrowserEntry]()) { targets, entry in
            let key = "\(entry.bundleIdentifier)|\(entry.userDataDirectory ?? "")"
            targets[key] = targets[key] ?? entry
        }.values)

        Task.detached { [activeKeys, discoveryTargets] in
            let discovery = ProfileDiscovery()
            var profileSuggestions: [BrowserEntry] = []
            for target in discoveryTargets {
                let bundleId = target.bundleIdentifier
                let profiles = discovery.discoverProfiles(
                    for: bundleId,
                    userDataDirectory: target.userDataDirectory)
                let suggestedProfiles = profiles.filter { Self.shouldSuggestProfile($0) }
                guard !suggestedProfiles.isEmpty else { continue }
                let baseName = target.displayName
                for profile in suggestedProfiles {
                    let key = Self.profileSuggestionKey(
                        bundleIdentifier: bundleId,
                        profileId: profile.id,
                        userDataDirectory: target.userDataDirectory)
                    if !activeKeys.contains(key) {
                        profileSuggestions.append(BrowserEntry(
                            bundleIdentifier: bundleId,
                            displayName: baseName,
                            profileId: profile.id,
                            profileName: profile.name,
                            source: .suggested,
                            userDataDirectory: target.userDataDirectory))
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.suggestedBrowsers = self.suggestedBrowsers.filter { $0.profileId == nil } + profileSuggestions
            }
        }
    }

    nonisolated static func shouldSuggestProfile(_ profile: BrowserProfile) -> Bool {
        let normalizedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !profile.isDefault else { return false }
        guard ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
               "org.mozilla.nightly"].contains(profile.browserBundleId) else {
            return true
        }
        switch normalizedName.lowercased() {
        case "default", "default-release", "dev-edition-default":
            return false
        default:
            return true
        }
    }

    nonisolated static func clearingDefaultProfileSelectionIfNeeded(
        _ entry: BrowserEntry
    ) -> BrowserEntry {
        guard entry.profileId != nil,
              entry.source != .manual,
              Self.isFirefoxBundle(entry.bundleIdentifier),
              Self.isFirefoxDefaultProfileName(entry.profileName ?? entry.profileId ?? "") else {
            return entry
        }
        var cleaned = entry
        cleaned.profileId = nil
        cleaned.profileName = nil
        cleaned.lastModifiedAt = Date()
        return cleaned
    }

    nonisolated private static func isFirefoxBundle(_ bundleIdentifier: String) -> Bool {
        ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
         "org.mozilla.nightly"].contains(bundleIdentifier)
    }

    nonisolated private static func isFirefoxDefaultProfileName(_ name: String) -> Bool {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "default", "default-release", "dev-edition-default":
            return true
        default:
            return false
        }
    }

    nonisolated private static func profileSuggestionKey(for entry: BrowserEntry) -> String {
        Self.profileSuggestionKey(
            bundleIdentifier: entry.bundleIdentifier,
            profileId: entry.profileId,
            userDataDirectory: entry.userDataDirectory)
    }

    nonisolated private static func profileSuggestionKey(
        bundleIdentifier: String,
        profileId: String?,
        userDataDirectory: String?
    ) -> String {
        "\(bundleIdentifier)|\(userDataDirectory ?? "")|\(profileId ?? "")"
    }

    func handleAppInstalled(bundleId: String, appURL: URL) {
        iconResolver.invalidateCache(for: bundleId)
        // Update all matching browser entries (multiple profiles share a bundle ID)
        var browsersChanged = false
        for i in browsers.indices where browsers[i].bundleIdentifier == bundleId {
            browsers[i].isInstalled = true
            browsers[i].lastSeenAt = Date()
            browsersChanged = true
        }
        if browsersChanged { save() }

        // Also update email client entries
        var emailChanged = false
        for i in emailClients.indices where emailClients[i].bundleIdentifier == bundleId {
            emailClients[i].isInstalled = true
            emailClients[i].lastSeenAt = Date()
            emailChanged = true
        }
        if emailChanged { saveEmailClients() }

        if browsersChanged { return }

        // ChangeReconciler only calls this for apps from urlsForApplications(toOpen: https://)
        // so the redundant CFBundleURLTypes HTTP check is unnecessary and can reject
        // valid handlers. Use CFBundleCopyInfoDictionaryForURL to avoid Bundle cache staleness.
        guard !YojamBundleIDs.isOwnedByYojam(bundleId) else { return }
        let infoDict = CFBundleCopyInfoDictionaryForURL(appURL as CFURL) as NSDictionary?
        let name = infoDict?["CFBundleName"] as? String ?? "Unknown"
        let entry = BrowserEntry(
            bundleIdentifier: bundleId, displayName: name, source: .suggested
        )
        if KnownAppAllowlist.browsers.contains(bundleId) {
            addBrowser(entry)
        } else if !suggestedBrowsers.contains(where: {
            $0.bundleIdentifier == bundleId
        }) {
            suggestedBrowsers.append(entry)
        }
    }

    func handleAppRemoved(bundleId: String) {
        // Update all matching browser entries
        for i in browsers.indices where browsers[i].bundleIdentifier == bundleId {
            browsers[i].isInstalled = false
        }
        save()
        // Also update email clients
        var emailChanged = false
        for i in emailClients.indices where emailClients[i].bundleIdentifier == bundleId {
            emailClients[i].isInstalled = false
            emailChanged = true
        }
        if emailChanged {
            settingsStore.saveEmailClients(emailClients)
        }
    }

    func saveEmailClients() {
        settingsStore.saveEmailClients(emailClients)
    }

    private func reindex() {
        for i in browsers.indices { browsers[i].position = i }
    }

    func save() { settingsStore.saveBrowsers(browsers) }
}
