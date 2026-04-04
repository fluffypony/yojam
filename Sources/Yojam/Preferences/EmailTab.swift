import SwiftUI

struct EmailTab: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var browserManager: BrowserManager

    var body: some View {
        VStack(alignment: .leading) {
            Text("Email Clients").font(.headline).padding()
            Text("Choose which app opens mailto: links.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            List {
                ForEach(browserManager.emailClients) { client in
                    HStack {
                        Image(nsImage: browserManager.icon(for: client))
                            .resizable().frame(width: 24, height: 24)
                        Text(client.displayName)
                        Spacer()
                        Circle()
                            .fill(client.isInstalled ? .green : .gray)
                            .frame(width: 8, height: 8)
                    }
                }.onMove { source, dest in
                    browserManager.emailClients.move(
                        fromOffsets: source, toOffset: dest)
                    settingsStore.saveEmailClients(
                        browserManager.emailClients)
                }
            }
        }
    }
}
