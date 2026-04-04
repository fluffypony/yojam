import SwiftUI
import UniformTypeIdentifiers

struct BrowsersTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @State private var selectedBrowserId: UUID?
    @State private var showingFilePicker = false
    @State private var profileDiscovery = ProfileDiscovery()

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedBrowserId) {
                    Section("Active") {
                        ForEach(browserManager.browsers) { browser in
                            BrowserRow(browser: browser,
                                       icon: browserManager.icon(for: browser))
                                .tag(browser.id)
                        }
                        .onMove {
                            browserManager.moveBrowser(from: $0, to: $1)
                        }
                    }
                    if !browserManager.suggestedBrowsers.isEmpty {
                        Section("Suggested") {
                            ForEach(browserManager.suggestedBrowsers) { entry in
                                HStack {
                                    Image(nsImage: browserManager.icon(for: entry))
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                    Text(entry.fullDisplayName)
                                        .font(.system(size: 13))
                                    Spacer()
                                    Button("Add") {
                                        browserManager.confirmSuggested(entry)
                                    }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    Button(action: {
                        if let id = selectedBrowserId,
                           let idx = browserManager.browsers.firstIndex(
                               where: { $0.id == id }) {
                            browserManager.removeBrowser(at: idx)
                            selectedBrowserId = nil
                        }
                    }) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedBrowserId == nil)
                    Spacer()
                    Button("Rescan") {
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
                    }.controlSize(.small)
                }.padding(8)
            }.frame(minWidth: 220, idealWidth: 300)

            Group {
                if let selectedId = selectedBrowserId,
                   let index = browserManager.browsers.firstIndex(
                       where: { $0.id == selectedId }
                   ) {
                    Form {
                        TextField("Name:",
                                  text: $browserManager.browsers[index]
                                      .displayName)
                        Toggle("Enabled",
                               isOn: $browserManager.browsers[index].enabled)
                        Toggle("Strip UTM Parameters",
                               isOn: $browserManager.browsers[index]
                                   .stripUTMParams)
                        Toggle("Open in Private Window",
                               isOn: $browserManager.browsers[index]
                                   .openInPrivateWindow)
                        HStack {
                            Text("Custom Icon:")
                            Spacer()
                            if browserManager.browsers[index].customIconData != nil {
                                Button("Remove") {
                                    browserManager.browsers[index].customIconData = nil
                                }.controlSize(.small)
                            }
                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.image]
                                if panel.runModal() == .OK, let url = panel.url,
                                   let data = try? Data(contentsOf: url) {
                                    browserManager.browsers[index].customIconData = data
                                }
                            }.controlSize(.small)
                        }
                        let profiles = profileDiscovery.discoverProfiles(
                            for: browserManager.browsers[index].bundleIdentifier)
                        if !profiles.isEmpty {
                            Picker("Profile", selection: $browserManager.browsers[index].profileId) {
                                Text("None").tag(nil as String?)
                                ForEach(profiles) { profile in
                                    Text(profile.name).tag(profile.id as String?)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped).padding()
                } else {
                    VStack {
                        Spacer()
                        Text("Select a browser")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }.frame(minWidth: 280, idealWidth: 320)
        }
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
}

private struct BrowserRow: View {
    let browser: BrowserEntry
    let icon: NSImage

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(browser.fullDisplayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(browser.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .opacity(browser.enabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        if !browser.isInstalled { return .gray }
        return browser.enabled ? .green : .red
    }
}
