import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let browserManager: BrowserManager
    private let recentURLsManager: RecentURLsManager
    private let settingsStore: SettingsStore
    private let onReopen: (URL) -> Void
    private let onOpenPreferences: () -> Void
    private let onToggleEnabled: () -> Void
    private var clipboardWindow: ClipboardNotificationWindow?

    init(browserManager: BrowserManager,
         recentURLsManager: RecentURLsManager,
         settingsStore: SettingsStore,
         onReopen: @escaping (URL) -> Void,
         onOpenPreferences: @escaping () -> Void,
         onToggleEnabled: @escaping () -> Void) {
        self.browserManager = browserManager
        self.recentURLsManager = recentURLsManager
        self.settingsStore = settingsStore
        self.onReopen = onReopen
        self.onOpenPreferences = onOpenPreferences
        self.onToggleEnabled = onToggleEnabled
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Build menu directly into the provided menu to avoid NSMenuItem ownership issues
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(in: menu)
    }

    private func buildMenu(in menu: NSMenu) {
        let enabledItem = NSMenuItem(
            title: settingsStore.isEnabled
                ? "Yojam Active" : "Yojam Paused",
            action: #selector(toggleClicked),
            keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(.separator())

        if !recentURLsManager.recentURLs.isEmpty {
            let header = NSMenuItem(
                title: "Recent URLs", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for url in recentURLsManager.recentURLs.prefix(10) {
                let item = NSMenuItem(
                    title: "  \(url.host ?? url.absoluteString)",
                    action: #selector(reopenURL(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = url
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let activeBrowsers = browserManager.browsers.filter(\.enabled).count
        let activeClients = browserManager.emailClients.filter(\.enabled).count
        let statsItem = NSMenuItem(
            title: "\(activeBrowsers) browser\(activeBrowsers == 1 ? "" : "s"), \(activeClients) mail client\(activeClients == 1 ? "" : "s")",
            action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(preferencesClicked),
            keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Yojam",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func toggleClicked() {
        onToggleEnabled()
    }

    @objc private func reopenURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onReopen(url) }
    }

    @objc private func preferencesClicked() { onOpenPreferences() }

    func showClipboardNotification(
        for url: URL, onOpen: @escaping () -> Void
    ) {
        clipboardWindow?.dismiss()
        clipboardWindow = ClipboardNotificationWindow(
            url: url, onOpen: onOpen,
            onDismiss: { [weak self] in self?.clipboardWindow = nil },
            settingsStore: settingsStore)
        clipboardWindow?.showWithAutoDismiss()
    }
}
