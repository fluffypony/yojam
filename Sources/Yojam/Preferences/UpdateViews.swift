import SwiftUI

/// "Check Now" normally, a primary "Install Update…" once a build is waiting.
/// Disabled while a check the user started is in flight.
struct UpdateActionButton: View {
    @ObservedObject var updateCenter: UpdateCenter
    var checkLabel = "Check Now"

    var body: some View {
        Group {
            if updateCenter.availableUpdate != nil {
                ThemeButton(
                    "Install Update\u{2026}", isPrimary: true,
                    help: "Show what changed and install the update"
                ) {
                    updateCenter.checkForUpdates()
                }
            } else {
                ThemeButton(checkLabel, help: "Ask yoj.am whether a newer version exists") {
                    updateCenter.checkForUpdates()
                }
                .disabled(updateCenter.isChecking)
                .opacity(updateCenter.isChecking ? 0.5 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: updateCenter.isChecking)
        .animation(.easeInOut(duration: 0.15), value: updateCenter.availableUpdate)
    }
}

/// Version, last check, or the waiting update, on one line that stays
/// current as minutes pass.
struct UpdateStatusText: View {
    @ObservedObject var updateCenter: UpdateCenter
    /// Off where the version is already shown, as on the About tab.
    var includesVersion = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 6) {
                if updateCenter.isChecking {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(updateCenter.statusText(now: context.date, includesVersion: includesVersion))
                    .font(.system(size: 11))
                    .foregroundColor(
                        updateCenter.availableUpdate == nil ? Theme.textSecondary : Theme.accent)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: updateCenter.isChecking)
    }
}

/// Sits at the foot of the preferences sidebar while an update waits, so the
/// reminder is visible from every tab.
struct SidebarUpdatePill: View {
    let version: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textInverse)
                    Text("Yojam \(version) is ready to install")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.accent.opacity(isHovering ? 0.18 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Show what changed and install the update")
        .accessibilityLabel("Update available. Yojam \(version) is ready to install.")
    }
}

/// Instant press feedback: a slight scale down on pointer-down, back on
/// release. Skipped under Reduce Motion.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
