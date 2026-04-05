import AppKit
import Combine

@MainActor
final class BrowserManager: ObservableObject {
    @Published var browsers: [BrowserEntry] = []
    @Published var suggestedBrowsers: [BrowserEntry] = []
    @Published var emailClients: [BrowserEntry] = []

    private let settingsStore: SettingsStore
    private let iconResolver = IconResolver()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.browsers = settingsStore.loadBrowsers()
        self.emailClients = settingsStore.loadEmailClients()
        if UserDefaults.standard.data(forKey: "browsers") == nil { performInitialDetection() }
        if UserDefaults.standard.data(forKey: "emailClients") == nil { addDefaultEmailClients() }
        deduplicateProfileEntries()
        refreshProfileSuggestions()
    }

    /// Remove duplicate profile entries and profile entries with empty names
    /// that may have been created by earlier versions of profile discovery.
    private func deduplicateProfileEntries() {
        var seen = Set<String>() // "bundleId|profileId"
        var cleaned: [BrowserEntry] = []
        for entry in browsers {
            // §20: Check empty name BEFORE inserting into seen set
            if entry.profileId != nil,
               let profileName = entry.profileName,
               profileName.isEmpty {
                continue
            }
            let key = "\(entry.bundleIdentifier)|\(entry.profileId ?? "")"
            guard seen.insert(key).inserted else { continue }
            cleaned.append(entry)
        }
        if cleaned.count != browsers.count {
            browsers = cleaned
            for i in browsers.indices { browsers[i].position = i }
            save()
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
                  bundleId != Bundle.main.bundleIdentifier,
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
                  bundleId != Bundle.main.bundleIdentifier,
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
    func lastUsedIndex(isEmail: Bool) -> Int {
        let key = isEmail ? "lastUsedEmailId" : "lastUsedBrowserId"
        guard let idString = UserDefaults.standard.string(forKey: key),
              let uuid = UUID(uuidString: idString) else { return 0 }
        let list = isEmail ? emailClients : browsers
        return list.firstIndex(where: { $0.id == uuid }) ?? 0
    }

    func recordLastUsed(_ entry: BrowserEntry, isEmail: Bool) {
        let key = isEmail ? "lastUsedEmailId" : "lastUsedBrowserId"
        UserDefaults.standard.set(entry.id.uuidString, forKey: key)
    }

    /// Regenerate suggested browser entries for profiles not yet in the active list.
    func refreshProfileSuggestions() {
        let discovery = ProfileDiscovery()
        // Collect all (bundleId, profileId) pairs already active
        let activeKeys = Set(browsers.map { "\($0.bundleIdentifier)|\($0.profileId ?? "")" })

        // For each unique bundle ID in the active list, discover profiles
        let activeBundleIds = Set(browsers.map(\.bundleIdentifier))
        var profileSuggestions: [BrowserEntry] = []
        for bundleId in activeBundleIds {
            let profiles = discovery.discoverProfiles(for: bundleId)
            let named = profiles.filter { !$0.name.isEmpty }
            guard named.count > 1 else { continue }
            let baseName = browsers.first(where: { $0.bundleIdentifier == bundleId })?.displayName ?? bundleId
            for profile in named {
                let key = "\(bundleId)|\(profile.id)"
                if !activeKeys.contains(key) {
                    profileSuggestions.append(BrowserEntry(
                        bundleIdentifier: bundleId,
                        displayName: baseName,
                        profileId: profile.id,
                        profileName: profile.name,
                        source: .suggested))
                }
            }
        }

        // Merge: keep non-profile suggestions + add fresh profile suggestions
        suggestedBrowsers = suggestedBrowsers.filter { $0.profileId == nil } + profileSuggestions
    }

    func handleAppInstalled(bundleId: String, appURL: URL) {
        iconResolver.invalidateCache(for: bundleId)
        // Update all matching entries (multiple profiles share a bundle ID)
        var found = false
        for i in browsers.indices where browsers[i].bundleIdentifier == bundleId {
            browsers[i].isInstalled = true
            browsers[i].lastSeenAt = Date()
            found = true
        }
        if found { save(); return }

        guard let bundle = Bundle(url: appURL),
              let schemes = bundle.infoDictionary?["CFBundleURLTypes"]
                  as? [[String: Any]]
        else { return }
        let handlesHTTP = schemes.contains { dict in
            (dict["CFBundleURLSchemes"] as? [String])?.contains(where: {
                $0.lowercased() == "http" || $0.lowercased() == "https"
            }) ?? false
        }
        guard handlesHTTP, bundleId != Bundle.main.bundleIdentifier else { return }
        let name = bundle.infoDictionary?["CFBundleName"] as? String ?? "Unknown"
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
