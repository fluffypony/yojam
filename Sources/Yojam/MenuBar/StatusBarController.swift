import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    struct LinkHistoryMenuEntry: Equatable {
        let title: String
        let url: URL
    }

    private var statusItem: NSStatusItem!
    private let browserManager: BrowserManager
    private let recentURLsManager: RecentURLsManager
    private let settingsStore: SettingsStore
    private let updateCenter: UpdateCenter
    private let onReopen: (URL) -> Void
    private let onOpenPreferences: () -> Void
    private let onToggleEnabled: () -> Void
    private var clipboardWindow: ClipboardNotificationWindow?
    private var cancellables = Set<AnyCancellable>()

    /// Accent dot on the status item while an update waits.
    private var updateBadge: CALayer?
    private static let updateBadgeDiameter: CGFloat = 6

    private let onShowQuickStart: () -> Void
    private let onShowKeyboardShortcuts: () -> Void

    init(browserManager: BrowserManager,
         recentURLsManager: RecentURLsManager,
         settingsStore: SettingsStore,
         updateCenter: UpdateCenter,
         onReopen: @escaping (URL) -> Void,
         onOpenPreferences: @escaping () -> Void,
         onToggleEnabled: @escaping () -> Void,
         onShowQuickStart: @escaping () -> Void = {},
         onShowKeyboardShortcuts: @escaping () -> Void = {}) {
        self.browserManager = browserManager
        self.recentURLsManager = recentURLsManager
        self.settingsStore = settingsStore
        self.updateCenter = updateCenter
        self.onReopen = onReopen
        self.onOpenPreferences = onOpenPreferences
        self.onToggleEnabled = onToggleEnabled
        self.onShowQuickStart = onShowQuickStart
        self.onShowKeyboardShortcuts = onShowKeyboardShortcuts
        super.init()
        setupStatusItem()
        updateCenter.$availableUpdate
            .removeDuplicates()
            .sink { [weak self] update in
                self?.setUpdateBadge(for: update)
            }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.size = NSSize(width: 18, height: 18)
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
        if let update = updateCenter.availableUpdate {
            let updateItem = NSMenuItem(
                title: "Update to Yojam \(update.version)\u{2026}",
                action: #selector(installUpdateClicked),
                keyEquivalent: "")
            updateItem.target = self
            updateItem.image = Self.updateMenuImage()
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

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
                title: "Link History", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for url in recentURLsManager.recentURLs.prefix(10) {
                let entry = Self.linkHistoryMenuEntry(for: url)
                let item = NSMenuItem(
                    title: "  \(entry.title)",
                    action: #selector(reopenURL(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = entry.url
                menu.addItem(item)
            }
            let clearHistoryItem = NSMenuItem(
                title: "Clear Link History",
                action: #selector(clearLinkHistoryClicked),
                keyEquivalent: "")
            clearHistoryItem.target = self
            menu.addItem(clearHistoryItem)
            menu.addItem(.separator())
        }

        let activeBrowsers = browserManager.browsers.filter(\.enabled).count
        let activeClients = browserManager.emailClients.filter(\.enabled).count
        let activePhoneClients = browserManager.phoneClients.filter(\.enabled).count
        let statsItem = NSMenuItem(
            title: "\(activeBrowsers) browser\(activeBrowsers == 1 ? "" : "s"), \(activeClients) mail client\(activeClients == 1 ? "" : "s"), \(activePhoneClients) phone client\(activePhoneClients == 1 ? "" : "s")",
            action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        menu.addItem(.separator())

        let quickStartItem = NSMenuItem(
            title: "Quick Start\u{2026}",
            action: #selector(quickStartClicked),
            keyEquivalent: "")
        quickStartItem.target = self
        menu.addItem(quickStartItem)

        let shortcutsItem = NSMenuItem(
            title: "Keyboard Shortcuts\u{2026}",
            action: #selector(keyboardShortcutsClicked),
            keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(preferencesClicked),
            keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Yojam",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private static func updateMenuImage() -> NSImage? {
        guard let symbol = NSImage(
            systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        else { return nil }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [NSColor(Theme.accent)])
        let image = symbol.withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    @objc private func toggleClicked() {
        onToggleEnabled()
    }

    @objc private func reopenURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onReopen(url) }
    }

    @objc private func clearLinkHistoryClicked() {
        recentURLsManager.clear()
    }

    static func linkHistoryMenuEntry(for url: URL) -> LinkHistoryMenuEntry {
        guard let host = url.host else {
            return LinkHistoryMenuEntry(title: url.absoluteString, url: url)
        }

        var title = host
        if let port = url.port {
            title += ":\(port)"
        }
        if !url.path.isEmpty && url.path != "/" {
            title += url.path
        }
        return LinkHistoryMenuEntry(title: title, url: url)
    }

    @objc private func quickStartClicked() { onShowQuickStart() }
    @objc private func keyboardShortcutsClicked() { onShowKeyboardShortcuts() }
    @objc private func preferencesClicked() { onOpenPreferences() }
    @objc private func checkForUpdatesClicked() { updateCenter.checkForUpdates() }
    @objc private func installUpdateClicked() { updateCenter.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesClicked) {
            return !updateCenter.isChecking
        }
        return true
    }

    // MARK: - Update badge

    /// Shows or hides the accent dot at the status item's bottom-right corner,
    /// clear of the glyph's arms. The dot is the one reminder that costs the
    /// user nothing; the menu carries the action.
    private func setUpdateBadge(for update: UpdateCenter.AvailableUpdate?) {
        guard let button = statusItem.button else { return }
        if let update {
            button.toolTip = "Yojam \(update.version) is available. Open the menu to update."
            guard updateBadge == nil else { return }
            button.wantsLayer = true
            guard let hostLayer = button.layer else { return }

            let diameter = Self.updateBadgeDiameter
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            dot.cornerRadius = diameter / 2
            dot.backgroundColor = NSColor(Theme.accent).cgColor
            dot.contentsScale = button.window?.backingScaleFactor ?? 2
            // NSButton is flipped, so its layer's origin is the top-left;
            // honour whichever way this layer is set up to keep the dot low.
            let inset = diameter / 2 + 2
            dot.position = CGPoint(
                x: button.bounds.maxX - inset,
                y: hostLayer.isGeometryFlipped ? button.bounds.maxY - inset : inset)
            hostLayer.addSublayer(dot)
            updateBadge = dot
            Self.animateBadgeIn(dot)
        } else {
            button.toolTip = nil
            guard let dot = updateBadge else { return }
            updateBadge = nil
            Self.animateBadgeOut(dot)
        }
    }

    private static func animateBadgeIn(_ dot: CALayer) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let timing = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        fade.timingFunction = timing
        dot.add(fade, forKey: "badgeFadeIn")

        guard !reduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1
        scale.duration = 0.2
        scale.timingFunction = timing
        dot.add(scale, forKey: "badgeScaleIn")
    }

    private static func animateBadgeOut(_ dot: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { dot.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        dot.add(fade, forKey: "badgeFadeOut")
        CATransaction.commit()
    }

    func showClipboardNotification(
        for url: URL, onOpen: @escaping () -> Void
    ) {
        clipboardWindow?.dismiss()
        // §17: Pass window identity to dismiss callback to prevent race on rapid copies
        clipboardWindow = ClipboardNotificationWindow(
            url: url, onOpen: onOpen,
            onDismiss: { [weak self] window in
                if self?.clipboardWindow === window {
                    self?.clipboardWindow = nil
                }
            },
            settingsStore: settingsStore)
        clipboardWindow?.showWithAutoDismiss()
    }
}
