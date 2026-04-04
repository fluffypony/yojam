import SwiftUI
import UniformTypeIdentifiers

struct BrowsersTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager
    @State private var selectedBrowser: BrowserEntry?
    @State private var showingFilePicker = false

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Browsers").font(.headline).padding(.horizontal)
                List(selection: $selectedBrowser) {
                    Section("Active") {
                        ForEach(browserManager.browsers) { browser in
                            HStack {
                                Image(nsImage: browserManager.icon(
                                    for: browser))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading) {
                                    Text(browser.fullDisplayName)
                                        .font(.system(size: 13))
                                    Text(browser.bundleIdentifier)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Circle()
                                    .fill(browser.isInstalled
                                          ? .green : .gray)
                                    .frame(width: 8, height: 8)
                            }.tag(browser)
                        }
                        .onMove {
                            browserManager.moveBrowser(from: $0, to: $1)
                        }
                    }
                    if !browserManager.suggestedBrowsers.isEmpty {
                        Section("Suggested") {
                            ForEach(browserManager.suggestedBrowsers) {
                                entry in
                                HStack {
                                    Text(entry.displayName); Spacer()
                                    Button("Add") {
                                        browserManager.confirmSuggested(
                                            entry)
                                    }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "plus")
                    }
                    Spacer()
                }.padding(8)
            }.frame(minWidth: 250)

            if let browser = selectedBrowser,
               let index = browserManager.browsers.firstIndex(
                   where: { $0.id == browser.id }
               ) {
                Form {
                    TextField("Name:",
                              text: $browserManager.browsers[index]
                                  .displayName)
                    Toggle("Enabled",
                           isOn: $browserManager.browsers[index].enabled)
                    Toggle("Strip UTM",
                           isOn: $browserManager.browsers[index]
                               .stripUTMParams)
                    Toggle("Open in Private Window",
                           isOn: $browserManager.browsers[index]
                               .openInPrivateWindow)
                }.formStyle(.grouped).padding()
            } else {
                VStack {
                    Spacer()
                    Text("Select a browser")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
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
