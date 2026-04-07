import SwiftUI
import UniformTypeIdentifiers
import TipKit
import YojamCore

struct BrowsersTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @Binding var scrollToSection: String?
    @State private var expandedBrowserId: UUID?
    @State private var profileDiscovery = ProfileDiscovery()
    @State private var draggedBrowserId: UUID?
    @State private var cachedProfiles: [String: [BrowserProfile]] = [:]
    @State private var hoveredBrowserId: UUID?
    @State private var draggedEmailId: UUID?

    private let browserOrderTip = BrowserOrderTip()
    private let customArgsTip = CustomLaunchArgsTip()

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(
                title: "Browsers",
                subtitle: "Manage installed browsers and per-app behavior."
            ) {
                HStack(spacing: 8) {
                    ThemeButton("Rescan", help: "Check for newly installed browsers") { rescanBrowsers() }
                    ThemeButton("+ Add", isPrimary: true, help: "Add a browser or app manually") { addCustomApp() }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        browsersSection.id("Active Browsers")
                        if !browserManager.suggestedBrowsers.isEmpty {
                            suggestedSection.id("Suggested Browsers")
                        }
                        emailSection.id("Email Clients")
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: scrollToSection) { _, section in
                    guard let section else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    scrollToSection = nil
                }
            }
        }
        .background(Theme.bgApp)
        .onDisappear { savePendingDisplayName(for: expandedBrowserId) }
        .onChange(of: expandedBrowserId) { oldId, _ in
            savePendingDisplayName(for: oldId)
        }
    }

    // MARK: - Browsers List

    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Active Browsers")
            ThemeInlineHelp(text: HelpText.Browsers.dragReorder)
            TipView(browserOrderTip)
            if browserManager.browsers.isEmpty {
                ThemePanel {
                    ThemeEmptyState(
                        icon: "globe",
                        title: "No browsers set up",
                        message: "Scan for installed browsers or add one manually.",
                        action: { rescanBrowsers() },
                        actionLabel: "Rescan")
                }
            } else {
                ThemePanel {
                    ForEach(Array(browserManager.browsers.enumerated()), id: \.element.id) { index, browser in
                        VStack(spacing: 0) {
                            browserRow(browser: browser, index: index)
                                .onDrag {
                                    draggedBrowserId = browser.id
                                    BrowserOrderTip.hasReordered = true
                                    return NSItemProvider(object: browser.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: BrowserDropDelegate(
                                    currentId: browser.id,
                                    draggedId: $draggedBrowserId,
                                    browserManager: browserManager
                                ))
                            if expandedBrowserId == browser.id {
                                browserDetailView(index: index)
                            }
                            if index < browserManager.browsers.count - 1 {
                                Divider().background(Theme.borderSubtle)
                            }
                        }
                    }
                }
            }
        }
    }

    private func browserRow(browser: BrowserEntry, index: Int) -> some View {
        HStack(spacing: 0) {
            // Drag handle
            Text("\u{22EE}\u{22EE}")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24, height: 36)
                .contentShape(Rectangle())
                .padding(.trailing, 8)
                .help("Drag to reorder")

            // Icon
            Image(nsImage: browserManager.icon(for: browser))
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.trailing, 12)

            // Name
            Text(browser.fullDisplayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                if ProfileLaunchHelper.supportsPrivateWindow(browserBundleId: browser.bundleIdentifier) {
                    inlineCheckbox("Private window", isOn: Binding(
                        get: { browser.openInPrivateWindow },
                        set: { newValue in
                            guard var entry = browserManager.browsers.first(where: { $0.id == browser.id }) else { return }
                            entry.openInPrivateWindow = newValue
                            browserManager.updateBrowser(entry)
                        }
                    ), helpTip: HelpText.Browsers.privateWindow)
                }
                inlineCheckbox("Remove tracking", isOn: Binding(
                    get: { browser.stripUTMParams },
                    set: { newValue in
                        guard var entry = browserManager.browsers.first(where: { $0.id == browser.id }) else { return }
                        entry.stripUTMParams = newValue
                        browserManager.updateBrowser(entry)
                    }
                ), helpTip: HelpText.Browsers.stripTrackers)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedBrowserId = expandedBrowserId == browser.id ? nil : browser.id
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .rotationEffect(.degrees(expandedBrowserId == browser.id ? 180 : 0))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.bgHover.opacity(0.001))
                        )
                }
                .buttonStyle(.plain)
                .help("Show browser details")

                ThemeToggle(isOn: Binding(
                    get: { browser.enabled },
                    set: { newValue in
                        guard var entry = browserManager.browsers.first(where: { $0.id == browser.id }) else { return }
                        entry.enabled = newValue
                        browserManager.updateBrowser(entry)
                    }
                ), helpTip: "Include this browser in the picker")
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(hoveredBrowserId == browser.id ? Theme.bgHover.opacity(0.5) : Color.clear)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expandedBrowserId = expandedBrowserId == browser.id ? nil : browser.id
            }
        }
        .onHover { hovering in
            hoveredBrowserId = hovering ? browser.id : nil
        }
        .opacity(browser.enabled ? 1 : 0.5)
    }

    private func browserDetailView(index: Int) -> some View {
        let browserId = browserManager.browsers[safe: index]?.id
        return VStack(spacing: 12) {
            if let browserId, let browser = browserManager.browsers.first(where: { $0.id == browserId }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                        ThemeTextField(
                            placeholder: "Name",
                            text: Binding(
                                get: {
                                    browserManager.browsers.first(where: { $0.id == browserId })?.displayName ?? ""
                                },
                                set: { newValue in
                                    guard let idx = browserManager.browsers.firstIndex(where: { $0.id == browserId }) else { return }
                                    browserManager.browsers[idx].displayName = newValue
                                }))
                            .onSubmit {
                                guard let entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
                                browserManager.updateBrowser(entry)
                            }
                    }

                    let profiles = cachedProfiles[browser.bundleIdentifier] ?? []
                    if !profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("Profile")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                                ThemeHelpIcon(text: HelpText.Browsers.profileSelection)
                            }
                            Picker("", selection: Binding<String?>(
                                get: {
                                    browserManager.browsers.first(where: { $0.id == browserId })?.profileId
                                },
                                set: { (newId: String?) in
                                    guard var entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
                                    entry.profileId = newId
                                    entry.profileName = profiles.first(where: { $0.id == newId })?.name
                                    browserManager.updateBrowser(entry)
                                }
                            )) {
                                Text("None").tag(nil as String?)
                                ForEach(profiles) { profile in
                                    Text(profile.name).tag(profile.id as String?)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityLabel("Browser profile")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Custom Launch Args")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                        ThemeHelpIcon(text: HelpText.Browsers.customLaunchArgs)
                    }
                    HStack(spacing: 8) {
                        ThemeTextField(
                            placeholder: "e.g. $URL or --url $URL",
                            text: Binding(
                                get: {
                                    browserManager.browsers.first(where: { $0.id == browserId })?.customLaunchArgs ?? ""
                                },
                                set: { newValue in
                                    guard var entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
                                    entry.customLaunchArgs = newValue.isEmpty ? nil : newValue
                                    browserManager.updateBrowser(entry)
                                    CustomLaunchArgsTip.hasEditedArgs = true
                                }),
                            isMono: true)
                        Text("Use $URL for the link")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                TipView(customArgsTip)

                HStack(spacing: 12) {
                    Text("Bundle: \(browser.bundleIdentifier)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)

                    Spacer()

                    HStack(spacing: 8) {
                        if browser.customIconData != nil {
                            ThemeButton("Remove Icon") {
                                guard var entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
                                entry.customIconData = nil
                                browserManager.updateBrowser(entry)
                            }
                        }
                        ThemeButton("Custom Icon...", help: HelpText.Browsers.customIcon) {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.image]
                            if panel.runModal() == .OK, let url = panel.url {
                                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                                let size = attrs?[.size] as? UInt64 ?? 0
                                guard size < 5_000_000 else { return }
                                guard let data = try? Data(contentsOf: url) else { return }
                                guard var entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
                                entry.customIconData = data
                                browserManager.updateBrowser(entry)
                            }
                        }
                        ThemeDangerButton(label: "Remove") {
                            expandedBrowserId = nil
                            if let idx = browserManager.browsers.firstIndex(where: { $0.id == browserId }) {
                                browserManager.removeBrowser(at: idx)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 12)
        .background(Theme.bgInput.opacity(0.5))
        .task(id: browserId) {
            guard let browserId,
                  let browser = browserManager.browsers.first(where: { $0.id == browserId }),
                  cachedProfiles[browser.bundleIdentifier] == nil else { return }
            let bundleId = browser.bundleIdentifier
            let discovery = profileDiscovery
            let profiles = await Task.detached {
                discovery.discoverProfiles(for: bundleId)
            }.value
            cachedProfiles[bundleId] = profiles
        }
    }

    // MARK: - Suggested

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Suggested Browsers")
            ThemeInlineHelp(text: HelpText.Browsers.suggestedBrowsers)
            ThemePanel {
                ForEach(Array(browserManager.suggestedBrowsers.enumerated()), id: \.element.id) { index, entry in
                    ThemePanelRow(isLast: index == browserManager.suggestedBrowsers.count - 1) {
                        Image(nsImage: browserManager.icon(for: entry))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(entry.fullDisplayName)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.leading, 8)
                        Spacer()
                        ThemeButton("Add") {
                            browserManager.confirmSuggested(entry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Email

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Email Clients")
            ThemeInlineHelp(text: HelpText.Browsers.emailClients)
            if browserManager.emailClients.isEmpty {
                ThemePanel {
                    ThemeEmptyState(
                        icon: "envelope",
                        title: "No email clients found",
                        message: "Yojam will fall back to your system default for mailto: links.")
                }
            } else {
                ThemePanel {
                    ForEach(Array(browserManager.emailClients.enumerated()), id: \.element.id) { index, client in
                        ThemePanelRow(isLast: index == browserManager.emailClients.count - 1) {
                            Text("\u{22EE}\u{22EE}")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.textSecondary.opacity(0.5))
                                .help("Drag to reorder")
                                .onDrag {
                                    draggedEmailId = client.id
                                    return NSItemProvider(object: client.id.uuidString as NSString)
                                }
                            Image(nsImage: browserManager.icon(for: client))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text(client.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                                .padding(.leading, 8)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(client.isInstalled ? Theme.success : Theme.textSecondary)
                                    .frame(width: 6, height: 6)
                                Text(client.isInstalled ? "Installed" : "Not Found")
                                    .font(.system(size: 10))
                                    .foregroundColor(client.isInstalled ? Theme.success : Theme.textSecondary)
                            }
                            .padding(.trailing, 8)
                            ThemeToggle(isOn: Binding(
                                get: {
                                    browserManager.emailClients.first(where: { $0.id == client.id })?.enabled ?? client.enabled
                                },
                                set: { newValue in
                                    guard let idx = browserManager.emailClients.firstIndex(where: { $0.id == client.id }) else { return }
                                    browserManager.emailClients[idx].enabled = newValue
                                    settingsStore.saveEmailClients(browserManager.emailClients)
                                }
                            ))
                        }
                        .onDrop(of: [.text], delegate: EmailDropDelegate(
                            currentId: client.id,
                            draggedId: $draggedEmailId,
                            browserManager: browserManager,
                            settingsStore: settingsStore
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Add Custom App / Executable

    private func addCustomApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an application or executable"
        panel.allowedContentTypes = [.application, .unixExecutable, .executable]
        panel.allowsOtherFileTypes = true
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
            guard bundleId != Bundle.main.bundleIdentifier else { return }
            let name = bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let handlesURLs = NSWorkspace.shared.urlsForApplications(
                toOpen: URL(string: "https://example.com")!)
                .contains { Bundle(url: $0)?.bundleIdentifier == bundleId }
            browserManager.addBrowser(BrowserEntry(
                bundleIdentifier: bundleId,
                displayName: name,
                position: browserManager.browsers.count,
                source: .manual,
                customLaunchArgs: handlesURLs ? nil : "$URL"))
        } else {
            let path = url.path
            let name = url.lastPathComponent
            browserManager.addBrowser(BrowserEntry(
                bundleIdentifier: path,
                displayName: name,
                position: browserManager.browsers.count,
                source: .manual,
                customLaunchArgs: "$URL"))
        }
    }

    // MARK: - Helpers

    private func savePendingDisplayName(for browserId: UUID?) {
        guard let browserId,
              let entry = browserManager.browsers.first(where: { $0.id == browserId }) else { return }
        let persisted = settingsStore.loadBrowsers()
        if let saved = persisted.first(where: { $0.id == browserId }),
           saved.displayName != entry.displayName {
            browserManager.updateBrowser(entry)
        }
    }

    @ViewBuilder
    private func inlineCheckbox(_ label: String, isOn: Binding<Bool>, helpTip: String? = nil) -> some View {
        let button = Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? Theme.accent : Theme.textSecondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        if let helpTip {
            button.help(helpTip)
        } else {
            button
        }
    }

    private func rescanBrowsers() {
        let handlers = NSWorkspace.shared.urlsForApplications(
            toOpen: URL(string: "https://example.com")!)
        let knownIds = Set(browserManager.browsers.map(\.bundleIdentifier))
        for appURL in handlers {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier,
                  !knownIds.contains(bundleId) else { continue }
            browserManager.handleAppInstalled(bundleId: bundleId, appURL: appURL)
        }
    }
}

// MARK: - Drag & Drop Delegate

struct BrowserDropDelegate: DropDelegate {
    let currentId: UUID
    @Binding var draggedId: UUID?
    let browserManager: BrowserManager

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId, draggedId != currentId else { return }
        guard let fromIndex = browserManager.browsers.firstIndex(where: { $0.id == draggedId }),
              let toIndex = browserManager.browsers.firstIndex(where: { $0.id == currentId })
        else { return }
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                browserManager.moveBrowser(
                    from: IndexSet(integer: fromIndex),
                    to: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}

struct EmailDropDelegate: DropDelegate {
    let currentId: UUID
    @Binding var draggedId: UUID?
    let browserManager: BrowserManager
    let settingsStore: SettingsStore

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId, draggedId != currentId else { return }
        guard let fromIndex = browserManager.emailClients.firstIndex(where: { $0.id == draggedId }),
              let toIndex = browserManager.emailClients.firstIndex(where: { $0.id == currentId })
        else { return }
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                browserManager.emailClients.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                settingsStore.saveEmailClients(browserManager.emailClients)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        true
    }
}
