import SwiftUI
import YojamCore

struct IntegrationsTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @Binding var scrollToSection: String?

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
                    status: DefaultBrowserManager.isDefaultBrowser ? .ok : .warning,
                    detail: DefaultBrowserManager.isDefaultBrowser
                        ? "Yojam is your default browser"
                        : "Yojam is not the default browser",
                    helpText: "When Yojam is your default browser, all link clicks in other apps go through Yojam's routing pipeline.",
                    action: ("Set as Default", {
                        DefaultBrowserManager.promptSetDefault()
                    })
                )
                IntegrationRow(
                    name: ".webloc handler",
                    icon: "doc.text",
                    status: DefaultBrowserManager.isWeblocHandler ? .ok : .info,
                    detail: DefaultBrowserManager.isWeblocHandler
                        ? "Yojam handles internet-location files"
                        : "Not registered for .webloc files",
                    helpText: "When enabled, AirDropped links (which arrive as .webloc files) are routed through Yojam instead of opening in the default browser.",
                    action: ("Register", {
                        DefaultBrowserManager.promptSetDefault()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "yojam:// scheme",
                    icon: "link",
                    status: DefaultBrowserManager.isYojamSchemeRegistered ? .ok : .warning,
                    detail: DefaultBrowserManager.isYojamSchemeRegistered
                        ? "Registered"
                        : "Not registered",
                    helpText: "The yojam:// URL scheme is used by the Share Extension, browser extensions, and automation tools like Shortcuts, Raycast, and Alfred to send links to Yojam.",
                    action: ("Register", {
                        DefaultBrowserManager.promptSetDefault()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Handoff",
                    icon: "hand.raised",
                    status: .info,
                    detail: "Check System Settings > General > AirDrop & Handoff",
                    helpText: "When Handoff is enabled and Yojam is your default browser, pages you're viewing on your iPhone or iPad can be continued on your Mac through Yojam.",
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
                    status: .info,
                    detail: "Enable in System Settings > Privacy & Security > Extensions > Sharing",
                    helpText: "The Share Extension adds \"Open in Yojam\" to the macOS share menu in Safari, Notes, Mail, Finder, and other apps.",
                    isLast: false
                )
                IntegrationRow(
                    name: "Safari extension",
                    icon: "safari",
                    status: .info,
                    detail: "Enable in Safari > Settings > Extensions",
                    helpText: "The Safari Web Extension adds a toolbar button, context menu item, and Alt+Shift+Y shortcut to route links through Yojam.",
                    isLast: false
                )
                IntegrationRow(
                    name: "Services menu",
                    icon: "contextualmenu.and.cursorarrow",
                    status: .ok,
                    detail: "\"Open in Yojam\" appears in the Services menu",
                    helpText: "Highlight any URL in any Cocoa app, right-click, and choose Services > Open in Yojam. You can also assign a global keyboard shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services.",
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
                             helpText: "The native messaging host lets browser extensions communicate with Yojam without triggering the OS protocol-handler prompt on every click.")
            ThemePanel {
                IntegrationRow(
                    name: "Chrome / Chromium",
                    icon: "network",
                    status: NativeMessagingInstaller.isManifestInstalled(for: "Chrome") ? .ok : .notInstalled,
                    detail: NativeMessagingInstaller.isManifestInstalled(for: "Chrome")
                        ? "Manifest installed"
                        : "Not installed",
                    helpText: "Installs the native messaging host manifest so the Chrome extension can route links directly without a protocol-handler prompt.",
                    action: ("Install", {
                        NativeMessagingInstaller.installAll()
                    }),
                    isLast: false
                )
                IntegrationRow(
                    name: "Firefox",
                    icon: "flame",
                    status: NativeMessagingInstaller.isManifestInstalled(for: "Firefox") ? .ok : .notInstalled,
                    detail: NativeMessagingInstaller.isManifestInstalled(for: "Firefox")
                        ? "Manifest installed"
                        : "Not installed",
                    helpText: "Installs the native messaging host manifest for Firefox.",
                    action: ("Install", {
                        NativeMessagingInstaller.installAll()
                    }),
                    isLast: false
                )
                // Reinstall all button
                ThemePanelRow(isLast: true) {
                    Spacer()
                    ThemeButton("Reinstall All Browser Helpers", isPrimary: true) {
                        NativeMessagingInstaller.installAll()
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
                    status: appGroupAccessible ? .ok : .error,
                    detail: appGroupAccessible
                        ? "App Group container is accessible"
                        : "Cannot access App Group container",
                    helpText: "The App Group container (group.org.yojam.shared) is used to share routing configuration between the main app and its extensions. If this fails, check that the App Group entitlement is configured correctly.",
                    isLast: true
                )
            }
        }
        .id("App Group Storage")
    }

    private var appGroupAccessible: Bool {
        UserDefaults(suiteName: SharedRoutingStore.suiteName) != nil
    }
}

// MARK: - Integration Row

private enum IntegrationStatus {
    case ok, warning, error, info, notInstalled

    var icon: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        case .notInstalled: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.success
        case .warning: Color.orange
        case .error: Theme.danger
        case .info: Theme.textSecondary
        case .notInstalled: Theme.textSecondary
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

            Image(systemName: status.icon)
                .font(.system(size: 14))
                .foregroundColor(status.color)

            if let (label, handler) = action {
                ThemeButton(label) {
                    handler()
                }
            }
        }
    }
}
