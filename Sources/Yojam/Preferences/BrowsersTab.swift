import SwiftUI
import UniformTypeIdentifiers

struct BrowsersTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @State private var showingFilePicker = false
    @State private var expandedBrowserId: UUID?
    @State private var profileDiscovery = ProfileDiscovery()

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(
                title: "Browsers",
                subtitle: "Manage installed browsers and per-app behavior."
            ) {
                HStack(spacing: 8) {
                    ThemeButton("Rescan") { rescanBrowsers() }
                    ThemeButton("+ Add", isPrimary: true) { showingFilePicker = true }
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    browsersSection
                    if !browserManager.suggestedBrowsers.isEmpty {
                        suggestedSection
                    }
                    emailSection
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .background(Theme.bgApp)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.application]
        ) { result in
            if case .success(let url) = result,
               let bundle = Bundle(url: url),
               let bundleId = bundle.bundleIdentifier {
                let name = bundle.infoDictionary?["CFBundleName"]
                    as? String
                    ?? url.deletingPathExtension().lastPathComponent
                browserManager.addBrowser(BrowserEntry(
                    bundleIdentifier: bundleId,
                    displayName: name,
                    position: browserManager.browsers.count,
                    source: .manual))
            }
        }
    }

    // MARK: - Browsers List

    private var browsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Active Browsers")
            ThemePanel {
                ForEach(Array(browserManager.browsers.enumerated()), id: \.element.id) { index, browser in
                    VStack(spacing: 0) {
                        browserRow(browser: browser, index: index)
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

    private func browserRow(browser: BrowserEntry, index: Int) -> some View {
        HStack(spacing: 0) {
            // Drag handle
            Text("\u{22EE}\u{22EE}")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 20)
                .padding(.trailing, 8)

            // Icon
            Image(nsImage: browserManager.icon(for: browser))
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.trailing, 12)

            // Name
            VStack(alignment: .leading, spacing: 1) {
                Text(browser.fullDisplayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Inline options
            HStack(spacing: 16) {
                inlineCheckbox("Incognito", isOn: Binding(
                    get: { browser.openInPrivateWindow },
                    set: { browserManager.browsers[index].openInPrivateWindow = $0; browserManager.save() }
                ))
                inlineCheckbox("Strip UTM", isOn: Binding(
                    get: { browser.stripUTMParams },
                    set: { browserManager.browsers[index].stripUTMParams = $0; browserManager.save() }
                ))

                // Expand/edit button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedBrowserId = expandedBrowserId == browser.id ? nil : browser.id
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .rotationEffect(.degrees(expandedBrowserId == browser.id ? 180 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 20)

                ThemeToggle(isOn: Binding(
                    get: { browser.enabled },
                    set: { browserManager.browsers[index].enabled = $0; browserManager.save() }
                ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .opacity(browser.enabled ? 1 : 0.5)
    }

    private func browserDetailView(index: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Display Name")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                    ThemeTextField(placeholder: "Name", text: $browserManager.browsers[index].displayName)
                }

                let profiles = profileDiscovery.discoverProfiles(
                    for: browserManager.browsers[index].bundleIdentifier)
                if !profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                        Picker("", selection: $browserManager.browsers[index].profileId) {
                            Text("None").tag(nil as String?)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(profile.id as String?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            HStack(spacing: 12) {
                Text("Bundle: \(browserManager.browsers[index].bundleIdentifier)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                HStack(spacing: 8) {
                    if browserManager.browsers[index].customIconData != nil {
                        ThemeButton("Remove Icon") {
                            browserManager.browsers[index].customIconData = nil
                            browserManager.save()
                        }
                    }
                    ThemeButton("Custom Icon...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.url,
                           let data = try? Data(contentsOf: url) {
                            browserManager.browsers[index].customIconData = data
                            browserManager.save()
                        }
                    }
                    ThemeDangerButton(label: "Remove") {
                        expandedBrowserId = nil
                        browserManager.removeBrowser(at: index)
                    }
                }
            }
        }
        .padding(.horizontal, 52)
        .padding(.vertical, 12)
        .background(Theme.bgInput.opacity(0.5))
    }

    // MARK: - Suggested

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Suggested Browsers")
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
            ThemePanel {
                ForEach(Array(browserManager.emailClients.enumerated()), id: \.element.id) { index, client in
                    ThemePanelRow(isLast: index == browserManager.emailClients.count - 1) {
                        Image(nsImage: browserManager.icon(for: client))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(client.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.leading, 8)
                        Spacer()
                        Circle()
                            .fill(client.isInstalled ? Theme.success : Theme.textSecondary)
                            .frame(width: 6, height: 6)
                            .padding(.trailing, 8)
                        ThemeToggle(isOn: Binding(
                            get: { client.enabled },
                            set: { newValue in
                                browserManager.emailClients[index].enabled = newValue
                                settingsStore.saveEmailClients(browserManager.emailClients)
                            }
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func inlineCheckbox(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? Theme.accent : Theme.textSecondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
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
