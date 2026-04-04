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
        if browsers.isEmpty { performInitialDetection() }
        if emailClients.isEmpty { addDefaultEmailClients() }
    }

    private func performInitialDetection() {
        let httpHandlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        var position = 0
        for appURL in httpHandlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != "com.yojam.app" else { continue }
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
        let mailBundleIds: [(String, String)] = [
            ("com.apple.mail", "Mail"),
            ("com.google.Gmail", "Gmail"),
            ("com.microsoft.Outlook", "Outlook"),
            ("com.readdle.smartemail-macos", "Spark"),
        ]
        var pos = 0
        for (bundleId, name) in mailBundleIds {
            if NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleId
            ) != nil {
                emailClients.append(BrowserEntry(
                    bundleIdentifier: bundleId, displayName: name,
                    position: pos, source: .autoDetected))
                pos += 1
            }
        }
        settingsStore.saveEmailClients(emailClients)
    }

    // MARK: - CRUD

    func addBrowser(_ entry: BrowserEntry) {
        var e = entry; e.position = browsers.count
        browsers.append(e); save()
    }

    func confirmSuggested(_ entry: BrowserEntry) {
        suggestedBrowsers.removeAll { $0.id == entry.id }
        addBrowser(entry)
    }

    func removeBrowser(at index: Int) {
        browsers.remove(at: index); reindex(); save()
    }

    func moveBrowser(from source: IndexSet, to destination: Int) {
        browsers.move(fromOffsets: source, toOffset: destination)
        reindex(); save()
    }

    func toggleBrowser(_ id: UUID) {
        if let idx = browsers.firstIndex(where: { $0.id == id }) {
            browsers[idx].enabled.toggle(); save()
        }
    }

    func updateBrowser(_ entry: BrowserEntry) {
        if let idx = browsers.firstIndex(where: { $0.id == entry.id }) {
            browsers[idx] = entry; save()
        }
    }

    func icon(for entry: BrowserEntry) -> NSImage {
        if let data = entry.customIconData, let img = NSImage(data: data) { return img }
        return iconResolver.icon(forBundleIdentifier: entry.bundleIdentifier)
    }

    func lastUsedIndex(isEmail: Bool) -> Int {
        let key = isEmail ? "lastUsedEmailIndex" : "lastUsedBrowserIndex"
        return UserDefaults.standard.integer(forKey: key)
    }

    func recordLastUsed(_ entry: BrowserEntry, isEmail: Bool) {
        let list = isEmail ? emailClients : browsers
        let key = isEmail ? "lastUsedEmailIndex" : "lastUsedBrowserIndex"
        if let idx = list.firstIndex(where: { $0.id == entry.id }) {
            UserDefaults.standard.set(idx, forKey: key)
        }
    }

    func handleAppInstalled(bundleId: String, appURL: URL) {
        if let idx = browsers.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            browsers[idx].isInstalled = true
            browsers[idx].lastSeenAt = Date()
            save()
            return
        }
        guard let bundle = Bundle(url: appURL),
              let schemes = bundle.infoDictionary?["CFBundleURLTypes"]
                  as? [[String: Any]]
        else { return }
        let handlesHTTP = schemes.contains { dict in
            (dict["CFBundleURLSchemes"] as? [String])?.contains(where: {
                $0.lowercased() == "http" || $0.lowercased() == "https"
            }) ?? false
        }
        guard handlesHTTP, bundleId != "com.yojam.app" else { return }
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
        if let idx = browsers.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            browsers[idx].isInstalled = false; save()
        }
    }

    private func reindex() {
        for i in browsers.indices { browsers[i].position = i }
    }

    private func save() { settingsStore.saveBrowsers(browsers) }
}
