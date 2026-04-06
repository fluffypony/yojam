import SwiftUI

struct QuickStartCard: View {
    @ObservedObject var settingsStore: SettingsStore
    var onSwitchTab: ((PreferencesTab) -> Void)?
    var onScrollToSection: ((String) -> Void)?
    @State private var isDefault = DefaultBrowserManager.isDefaultBrowser

    var body: some View {
        ThemeCalloutCard {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                Text("Get started with Yojam")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textInverse)
            }

            VStack(alignment: .leading, spacing: 10) {
                quickStartItem(
                    number: 1,
                    text: "Set Yojam as your default browser",
                    isDone: isDefault
                ) {
                    if !isDefault {
                        DefaultBrowserManager.promptSetDefault()
                        for delay in [1.0, 3.0, 6.0, 10.0] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                isDefault = DefaultBrowserManager.isDefaultBrowser
                            }
                        }
                    }
                }

                quickStartItem(
                    number: 2,
                    text: "Choose when the picker appears"
                ) {
                    onScrollToSection?("Activation")
                }

                quickStartItem(
                    number: 3,
                    text: "Review your browsers"
                ) {
                    onSwitchTab?(.browsers)
                }

                quickStartItem(
                    number: 4,
                    text: "Try the URL tester"
                ) {
                    onSwitchTab?(.pipeline)
                }
            }
        } onDismiss: {
            withAnimation(.easeOut(duration: 0.2)) {
                settingsStore.hasDismissedQuickStart = true
            }
        }
        .onAppear { isDefault = DefaultBrowserManager.isDefaultBrowser }
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
    }
}
