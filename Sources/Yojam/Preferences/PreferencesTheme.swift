import SwiftUI

// MARK: - Color Palette

enum Theme {
    // Backgrounds
    static let bgApp       = Color(red: 0.094, green: 0.094, blue: 0.094)   // #181818
    static let bgSidebar   = Color(red: 0.133, green: 0.133, blue: 0.133)   // #222222
    static let bgPanel     = Color(red: 0.118, green: 0.118, blue: 0.118)   // #1e1e1e
    static let bgInput     = Color(red: 0.067, green: 0.067, blue: 0.067)   // #111111
    static let bgHover     = Color(red: 0.165, green: 0.165, blue: 0.165)   // #2a2a2a
    static let bgActive    = Color(red: 0.200, green: 0.200, blue: 0.200)   // #333333

    // Borders
    static let borderSubtle = Color(red: 0.176, green: 0.176, blue: 0.176)  // #2d2d2d
    static let borderStrong = Color(red: 0.251, green: 0.251, blue: 0.251)  // #404040

    // Text
    static let textPrimary   = Color(red: 0.878, green: 0.878, blue: 0.878) // #e0e0e0
    static let textSecondary = Color(red: 0.533, green: 0.533, blue: 0.533) // #888888
    static let textInverse   = Color.white

    // Accent
    static let accent      = Color(red: 0.914, green: 0.118, blue: 0.388)   // #E91E63
    static let accentHover  = Color(red: 0.847, green: 0.082, blue: 0.341)  // #D81557
    static let accentBlue   = Color(red: 0.310, green: 0.349, blue: 0.639)  // #4F59A3
    static let danger       = Color(red: 1.0, green: 0.302, blue: 0.310)    // #ff4d4f
    static let success      = Color(red: 0.298, green: 0.686, blue: 0.314)  // #4CAF50

    // Radii
    static let radiusSm: CGFloat = 4
    static let radiusMd: CGFloat = 6
    static let radiusLg: CGFloat = 10
}

// MARK: - Reusable Components

/// A dark panel container with subtle border and rounded corners.
struct ThemePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.bgPanel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
    }
}

/// A single row inside a ThemePanel.
struct ThemePanelRow<Content: View>: View {
    let isLast: Bool
    let content: Content
    init(isLast: Bool = false, @ViewBuilder content: () -> Content) {
        self.isLast = isLast
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if !isLast {
                Divider()
                    .background(Theme.borderSubtle)
            }
        }
    }
}

/// Uppercase section title.
struct ThemeSectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(Theme.textSecondary)
            .padding(.bottom, 12)
    }
}

/// Content header with title + subtitle + optional trailing content.
struct ThemeContentHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String = "", @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.textInverse)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)
            Divider().background(Theme.borderSubtle)
        }
    }
}

/// A pink accent toggle matching the design.
struct ThemeToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .labelsHidden()
    }
}

/// Standard button matching the design.
struct ThemeButton: View {
    let label: String
    let isPrimary: Bool
    let action: () -> Void

    init(_ label: String, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.isPrimary = isPrimary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(isPrimary ? Theme.textInverse : Theme.textPrimary)
                .background(isPrimary ? Theme.accent : Theme.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(isPrimary ? Theme.accent : Theme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Danger button for destructive actions.
struct ThemeDangerButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundColor(Theme.danger)
                .background(Theme.danger.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(Theme.danger.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Small icon button for edit/delete actions in tables.
struct ThemeIconButton: View {
    let systemName: String
    let isDanger: Bool
    let action: () -> Void

    init(systemName: String, isDanger: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isDanger = isDanger
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // hover color managed by SwiftUI's natural behavior
        }
    }
}

/// Type badge (Rule / Rewrite)
struct ThemeBadge: View {
    let text: String
    let isRewrite: Bool

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(isRewrite ? Theme.accent : Color(red: 0.549, green: 0.596, blue: 0.949))
            .background(
                (isRewrite ? Theme.accent : Theme.accentBlue).opacity(0.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Dark text field matching the design.
struct ThemeTextField: View {
    let placeholder: String
    @Binding var text: String
    var isMono: Bool = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(isMono ? .system(size: 11, design: .monospaced) : .system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(Theme.textPrimary)
            .background(Theme.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSm)
                    .stroke(Theme.borderSubtle, lineWidth: 1)
            )
    }
}

/// A picker styled to match the dark theme.
struct ThemeDropdown<SelectionValue: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: SelectionValue
    let content: Content

    init(_ label: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
            }
            Picker("", selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}
