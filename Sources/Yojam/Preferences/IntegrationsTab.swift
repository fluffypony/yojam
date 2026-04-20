import SafariServices
import SwiftUI
import YojamCore

struct IntegrationsTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var scrollToSection: String?

    // P7: Cache integration status at appear to avoid LaunchServices IPC in body
    @State private var isDefaultBrowser = false
    @State private var isWeblocHandler = false
    @State private var isYojamSchemeRegistered = false
    @State private var isChromeHostInstalled = false
    @State private var isChromeHostMisconfigured = false
    @State private var isFirefoxHostInstalled = false
    @State private var isAppGroupAccessible = false

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(
                title: "Integrations",
                subtitle: "Check the status of each entry point and repair if needed.")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        systemSection
                        extensionsSection
                        browserHostsSection
                        appGroupSection
                    }
                    .padding(32)
                }
                .scrollIndicators(.visible)
                .onChange(of: scrollToSection) { _, section in
                    guard let section else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToSection = nil
                    }
                }
            }
        }
        .background(Theme.bgApp)
        .onAppear { refreshStatus() }
        // Registration is async (system confirmation dialog + Launch Services
        // propagation). Re-check each time Yojam comes back to the front so
        // the status flips to green as soon as the change lands.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    /// Poll the registration state for a few seconds after invoking
    /// `promptSetDefault`. Launch Services can take a noticeable moment to
    /// propagate, so a single delayed refresh regularly missed the update.
    private func scheduleRegistrationPolling() {
        for delay in [0.5, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { refreshStatus() }
        }
    }

    /// Deep link to System Settings > Privacy & Security > Extensions > Sharing.
    /// The `?Sharing` anchor works on macOS 14+; if it doesn't resolve the
    /// general Extensions pane is a safe fallback.
    private func openSharingExtensionsSettings() {
        let primary = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?Sharing")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!
        if !NSWorkspace.shared.open(primary) {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Deep link to System Settings > General > AirDrop & Handoff.
    /// `AirDrop-Handoff-Settings.extension` is the current pane ID on macOS
    /// 14+; the older `com.apple.Handoff` key is kept as a fallback.
    private func openHandoffSettings() {
        let primary = URL(string: "x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.Handoff")!
        if !NSWorkspace.shared.open(primary) {
            NSWorkspace.shared.open(fallback)
        }
    }

    /// Open the Safari Settings > Extensions pane focused on the Yojam
    /// extension. Uses SFSafariApplication, which is the only sanctioned way
    /// to deep-link into Safari's extension preferences.
    private func openSafariExtensionSettings() {
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: "com.yojam.app.SafariExtension"
        ) { error in
            if let error {
                Task { @MainActor in
                    YojamLogger.shared.log(
                        "showPreferencesForExtension failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func refreshStatus() {
        isDefaultBrowser = DefaultBrowserManager.isDefaultBrowser
        isWeblocHandler = DefaultBrowserManager.isWeblocHandler
        isYojamSchemeRegistered = DefaultBrowserManager.isYojamSchemeRegistered
        isChromeHostInstalled = NativeMessagingInstaller.isManifestInstalled(for: "Chrome")
        isChromeHostMisconfigured = NativeMessagingInstaller.resolveChromeExtensionIds().isEmpty
        isFirefoxHostInstalled = NativeMessagingInstaller.isManifestInstalled(for: "Firefox")
        isAppGroupAccessible = UserDefaults(suiteName: SharedRoutingStore.suiteName) != nil
    }

    // MARK: - System Registrations

    @ViewBuilder
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSectionTitle(text: "System Registrations")
            ThemePanel {
                IntegrationRow(
                    name: "Default browser",
                    icon: "globe",
                    status: isDefaultBrowser ? .ok : .warning,
                    detail: isDefaultBrowser
                        ? "Yojam is your default browser"
                        : "Yojam is not the default browser",
                    helpText: HelpText.Integrations.defaultBrowser,
                    action: ("Set as Default", {
                        DefaultBrowserManager.promptSetDefault()
                        // Delay refresh — promptSetDefault uses async NSWorkspace APIs
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { refreshStatus() }
                    })
                )
                IntegrationRow(
                    name: ".webloc handler",
                    icon: "doc.text",
                    status: isWeblocHandler ? .ok : .notInstalled,
                    detail: isWeblocHandler
                        ? "Yojam handles internet-location files"
                        : "Not registered for .webloc files",
                    helpText: HelpText.Integrations.weblocHandler,
                    action: ("Register", {
                        DefaultBrowserManager.promptSetDefault()
                        scheduleRegistrationPolling()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "yojam:// scheme",
                    icon: "link",
                    status: isYojamSchemeRegistered ? .ok : .notInstalled,
                    detail: isYojamSchemeRegistered
                        ? "Registered"
                        : "Not registered",
                    helpText: HelpText.Integrations.yojamScheme,
                    action: ("Register", {
                        DefaultBrowserManager.promptSetDefault()
                        scheduleRegistrationPolling()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Handoff",
                    icon: "hand.raised",
                    status: .unknown,
                    detail: "Toggled in System Settings > General > AirDrop & Handoff. Yojam can't see whether it's on.",
                    helpText: HelpText.Integrations.handoff,
                    action: ("Open Settings", { openHandoffSettings() }),
                    isLast: true
                )
            }
        }
        .id("System Registrations")
    }

    // MARK: - Extensions

    @ViewBuilder
    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSectionTitle(text: "Extensions")
            ThemePanel {
                IntegrationRow(
                    name: "Share Extension",
                    icon: "square.and.arrow.up",
                    status: .unknown,
                    detail: "Enable in System Settings > Privacy & Security > Extensions > Sharing",
                    helpText: HelpText.Integrations.shareExtension,
                    action: ("Open Settings", { openSharingExtensionsSettings() }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Safari extension",
                    icon: "safari",
                    status: .unknown,
                    detail: "Enable in Safari > Settings > Extensions",
                    helpText: HelpText.Integrations.safariExtension,
                    action: ("Open Safari", { openSafariExtensionSettings() }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Services menu",
                    icon: "contextualmenu.and.cursorarrow",
                    status: .ok,
                    detail: "\"Open in Yojam\" appears in the Services menu",
                    helpText: HelpText.Integrations.servicesMenu,
                    isLast: true
                )
            }
        }
        .id("Extensions")
    }

    // MARK: - Browser Native Messaging Hosts

    @ViewBuilder
    private var browserHostsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSectionTitle(text: "Browser Native Messaging",
                             helpText: HelpText.Integrations.nativeMessaging)
            ThemePanel {
                IntegrationRow(
                    name: "Chrome / Chromium",
                    icon: "network",
                    status: isChromeHostMisconfigured ? .warning
                        : isChromeHostInstalled ? .ok : .notInstalled,
                    detail: isChromeHostMisconfigured
                        ? "Manifest installed but uses placeholder extension ID"
                        : isChromeHostInstalled
                            ? "Manifest installed"
                            : "Not installed",
                    helpText: HelpText.Integrations.nativeMessaging,
                    action: ("Install", {
                        NativeMessagingInstaller.reconcileInstalled()
                        refreshStatus()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Firefox",
                    icon: "flame",
                    status: isFirefoxHostInstalled ? .ok : .notInstalled,
                    detail: isFirefoxHostInstalled
                        ? "Manifest installed"
                        : "Not installed",
                    helpText: HelpText.Integrations.nativeMessaging,
                    action: ("Install", {
                        NativeMessagingInstaller.reconcileInstalled()
                        refreshStatus()
                    }),
                    isLast: false
                )
                // Reinstall all button
                ThemePanelRow(isLast: true) {
                    Spacer()
                    ThemeButton("Reinstall All Browser Helpers", isPrimary: true) {
                        NativeMessagingInstaller.reconcileInstalled()
                        refreshStatus()
                    }
                    Spacer()
                }
            }
        }
        .id("Browser Native Messaging")
    }

    // MARK: - App Group

    @ViewBuilder
    private var appGroupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeSectionTitle(text: "App Group Storage")
            ThemePanel {
                IntegrationRow(
                    name: "Shared container",
                    icon: "externaldrive",
                    status: isAppGroupAccessible ? .ok : .error,
                    detail: isAppGroupAccessible
                        ? "App Group container is accessible"
                        : "Cannot access App Group container",
                    helpText: HelpText.Integrations.appGroup,
                    isLast: true
                )
            }
        }
        .id("App Group Storage")
    }

}

// MARK: - Integration Row

private enum IntegrationStatus {
    case ok, warning, error, notInstalled, unknown

    /// Nil when the row is purely informational and shouldn't render a status
    /// indicator — avoids colliding with the adjacent ThemeHelpIcon, which is
    /// itself an info-circle.
    var icon: String? {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .notInstalled: "xmark.circle.fill"
        case .unknown: nil
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.success
        case .warning: Color.orange
        case .error: Theme.danger
        case .notInstalled: Theme.danger
        case .unknown: Theme.textSecondary
        }
    }
}

private struct IntegrationRow: View {
    let name: String
    let icon: String
    let status: IntegrationStatus
    let detail: String
    var helpText: String? = nil
    var action: (String, () -> Void)? = nil
    var isLast: Bool = false

    var body: some View {
        ThemePanelRow(isLast: isLast, helpText: helpText) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if let statusIcon = status.icon {
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(status.color)
            }

            if let (label, handler) = action {
                ThemeButton(label) {
                    handler()
                }
            }
        }
    }
}
