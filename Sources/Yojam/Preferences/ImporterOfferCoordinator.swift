import Combine
import Foundation
import SwiftUI

@MainActor
final class ImporterOfferCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case detecting
        case unavailable
        case available([ConfigImporter.Source])
        case completed
    }

    typealias Discovery = () -> [ConfigImporter.Source]

    @Published private(set) var state: State = .idle

    private let currentVersion: Int
    private let discover: Discovery

    init(currentVersion: Int, discover: @escaping Discovery) {
        self.currentVersion = currentVersion
        self.discover = discover
    }

    var availableSources: [ConfigImporter.Source] {
        guard case .available(let sources) = state else { return [] }
        return sources
    }

    var offerLabel: String? {
        guard !availableSources.isEmpty else { return nil }
        return "Import from \(Self.sourceList(availableSources))"
    }

    func discoverIfNeeded(completedVersion: Int) {
        guard state == .idle else { return }
        guard completedVersion < currentVersion else {
            state = .completed
            return
        }

        state = .detecting
        let found = discover()
        let ordered = ConfigImporter.Source.allCases.filter(found.contains)
        state = ordered.isEmpty ? .unavailable : .available(ordered)
    }

    func markCompleted() {
        state = .completed
    }

    static func sourceList(_ sources: [ConfigImporter.Source]) -> String {
        let names = sources.map(\.displayName)
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) or \(names[1])"
        default:
            let last = names[names.index(before: names.endIndex)]
            return "\(names.dropLast().joined(separator: ", ")), or \(last)"
        }
    }
}

struct ExistingImporterOfferCard: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    @StateObject private var coordinator = ImporterOfferCoordinator(
        currentVersion: SettingsStore.currentImporterOfferVersion,
        discover: { ConfigImporter.detectAvailable() })
    @State private var showsImportSheet = false
    @State private var completedImport = false

    var body: some View {
        Group {
            if coordinator.offerLabel != nil {
                ThemeCalloutCard {
                    Text("Import existing rules")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textInverse)
                    Text(
                        "Yojam found "
                            + ImporterOfferCoordinator.sourceList(coordinator.availableSources)
                            + " on this Mac. Review the rules before import.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                    HStack(spacing: 8) {
                        ThemeButton("Not now") { completeOffer() }
                        ThemeButton("Review Import", isPrimary: true) {
                            showsImportSheet = true
                        }
                    }
                } onDismiss: {
                    completeOffer()
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Import existing rules from another app")
            }
        }
        .onAppear {
            coordinator.discoverIfNeeded(
                completedVersion: settingsStore.completedImporterOfferVersion)
        }
        .sheet(isPresented: $showsImportSheet) {
            ImportFromOtherAppsSheet(
                settingsStore: settingsStore,
                ruleEngine: ruleEngine,
                offeredSources: coordinator.availableSources,
                onImport: { completedImport = true },
                onDismiss: {
                    showsImportSheet = false
                    if completedImport {
                        completeOffer()
                    }
                })
        }
    }

    private func completeOffer() {
        settingsStore.completeCurrentImporterOffer()
        coordinator.markCompleted()
    }
}
