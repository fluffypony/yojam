import Foundation
import SwiftUI
import TipKit
import YojamCore

struct QuickStartCard: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var ruleEngine: RuleEngine
    var onSwitchTab: ((PreferencesTab) -> Void)?
    /// Scroll + optional highlight. Caller controls the delay / highlight-nil timing.
    var onScrollToSection: ((String, String?) -> Void)?
    @StateObject private var importerOffer: ImporterOfferCoordinator
    @State private var isDefault = DefaultBrowserManager.isDefaultBrowser
    @State private var showingImportSheet = false
    @State private var completedImportOfferThisPresentation = false

    init(
        settingsStore: SettingsStore,
        ruleEngine: RuleEngine,
        onSwitchTab: ((PreferencesTab) -> Void)? = nil,
        onScrollToSection: ((String, String?) -> Void)? = nil,
        discoverImportSources: @escaping ImporterOfferCoordinator.Discovery = {
            ConfigImporter.detectAvailable()
        }
    ) {
        self.settingsStore = settingsStore
        self.ruleEngine = ruleEngine
        self.onSwitchTab = onSwitchTab
        self.onScrollToSection = onScrollToSection
        _importerOffer = StateObject(wrappedValue: ImporterOfferCoordinator(
            currentVersion: SettingsStore.currentImporterOfferVersion,
            discover: discoverImportSources))
    }

    // State-based completion: auto-ticked from live state rather than
    // just "the user clicked the button".
    private var step1Done: Bool { isDefault }
    private var step2Done: Bool {
        // Visited OR the user changed activation mode from factory default
        settingsStore.quickStartVisitedActivation || settingsStore.activationMode != .always
    }
    private var step3Done: Bool {
        // Visited OR at least one browser is enabled
        settingsStore.quickStartVisitedBrowsers
            || !settingsStore.loadBrowsers().filter(\.enabled).isEmpty
    }
    private var step4Done: Bool { settingsStore.quickStartVisitedTester }
    private var importStepVisible: Bool {
        !settingsStore.hasCompletedCurrentImporterOffer
            && importerOffer.offerLabel != nil
    }
    private var numberShift: Int { importStepVisible ? 1 : 0 }

    private var allDone: Bool {
        let coreDone = step1Done && step2Done && step3Done && step4Done
        return coreDone && !importStepVisible
    }

    var body: some View {
        ThemeCalloutCard {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                Text("Get started with Yojam")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
            }

            VStack(alignment: .leading, spacing: 10) {
                if importStepVisible, let importStepLabel = importerOffer.offerLabel {
                    VStack(alignment: .trailing, spacing: 4) {
                        quickStartItem(
                            number: 1,
                            text: importStepLabel
                        ) {
                            showingImportSheet = true
                        }

                        Button("Not now") {
                            completeImportOffer()
                            checkAllDone()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .help("Keep your current rules. You can import later in Advanced settings.")
                        .accessibilityHint(
                            "Keeps your current rules. You can import later in Advanced settings.")
                    }
                }

                quickStartItem(
                    number: 1 + numberShift,
                    text: "Set Yojam as your default browser",
                    isDone: step1Done
                ) {
                    onSwitchTab?(.general)
                    onScrollToSection?("Default Browser", "defaultBrowserButton")
                    if !isDefault {
                        DefaultBrowserManager.promptSetDefault()
                        SetDefaultBrowserTip.hasSetDefault = true
                        for delay in [1.0, 3.0, 6.0, 10.0] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                isDefault = DefaultBrowserManager.isDefaultBrowser
                                checkAllDone()
                            }
                        }
                    }
                }

                quickStartItem(
                    number: 2 + numberShift,
                    text: "Choose when the picker appears",
                    isDone: step2Done
                ) {
                    settingsStore.quickStartVisitedActivation = true
                    onSwitchTab?(.general)
                    onScrollToSection?("Activation", "activationMode")
                    checkAllDone()
                }

                quickStartItem(
                    number: 3 + numberShift,
                    text: "Review your browsers",
                    isDone: step3Done
                ) {
                    settingsStore.quickStartVisitedBrowsers = true
                    onSwitchTab?(.browsers)
                    onScrollToSection?("Active Browsers", "browserList")
                    checkAllDone()
                }

                quickStartItem(
                    number: 4 + numberShift,
                    text: "Try the URL tester",
                    isDone: step4Done
                ) {
                    settingsStore.quickStartVisitedTester = true
                    onSwitchTab?(.pipeline)
                    onScrollToSection?("URL Tester", "urlTester")
                    checkAllDone()
                }
            }
        } onDismiss: {
            withAnimation(.easeOut(duration: 0.2)) {
                settingsStore.hasDismissedQuickStart = true
            }
        }
        .onAppear {
            isDefault = DefaultBrowserManager.isDefaultBrowser
            importerOffer.discoverIfNeeded(
                completedVersion: settingsStore.completedImporterOfferVersion)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportFromOtherAppsSheet(
                settingsStore: settingsStore,
                ruleEngine: ruleEngine,
                offeredSources: importerOffer.availableSources,
                onImport: { completeImportOffer() },
                onDismiss: {
                    showingImportSheet = false
                    if completedImportOfferThisPresentation {
                        checkAllDone()
                    }
                })
        }
    }

    private func checkAllDone() {
        if allDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    settingsStore.hasDismissedQuickStart = true
                }
            }
        }
    }

    private func completeImportOffer() {
        completedImportOfferThisPresentation = true
        settingsStore.completeCurrentImporterOffer()
        importerOffer.markCompleted()
    }

    private func quickStartItem(number: Int, text: String, isDone: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isDone ? Theme.success.opacity(0.2) : Theme.bgHover)
                        .frame(width: 22, height: 22)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.success)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(isDone, color: Theme.textSecondary)
                Spacer()
                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(isDone ? "Completed" : "Not completed")
        .accessibilityHint("Opens this Quick Start step.")
    }
}
