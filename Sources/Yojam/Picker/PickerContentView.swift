import SwiftUI

struct PickerContentView: View {
    let url: URL
    let entries: [BrowserEntry]
    @State var selectedIndex: Int
    let isVertical: Bool
    let onSelect: (BrowserEntry) -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if isVertical { verticalLayout } else { horizontalLayout }
            Text(entries[safe: selectedIndex]?.fullDisplayName ?? "")
                .font(.system(size: 12, weight: .medium))
            Text(url.absoluteString)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(12)
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { selectCurrent(); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command)
                && press.characters == "c" {
                onCopy(); return .handled
            }
            if press.modifiers.isEmpty,
               let digit = press.characters.first?.wholeNumberValue,
               digit >= 1 && digit <= 9 {
                selectByNumber(digit - 1); return .handled
            }
            return .ignored
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.element.id) {
                index, entry in
                PickerIconView(
                    entry: entry, isSelected: index == selectedIndex, size: 40
                )
                .onTapGesture { selectedIndex = index; selectCurrent() }
                .onHover { if $0 { selectedIndex = index } }
                .accessibilityLabel("Open in \(entry.fullDisplayName)")
            }
        }
    }

    private var verticalLayout: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.element.id) {
                    index, entry in
                    HStack(spacing: 8) {
                        PickerIconView(
                            entry: entry,
                            isSelected: index == selectedIndex, size: 32)
                        Text(entry.fullDisplayName)
                            .font(.system(size: 13))
                        Spacer()
                        if index < 9 {
                            Text("\(index + 1)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == selectedIndex
                                  ? Color.accentColor.opacity(0.15) : .clear)
                    )
                    .onTapGesture { selectedIndex = index; selectCurrent() }
                    .onHover { if $0 { selectedIndex = index } }
                }
            }
        }.frame(maxHeight: 400)
    }

    private func move(_ delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0, newIndex < entries.count {
            selectedIndex = newIndex
        }
    }

    private func selectCurrent() { onSelect(entries[selectedIndex]) }

    private func selectByNumber(_ index: Int) {
        if index < entries.count {
            selectedIndex = index; selectCurrent()
        }
    }
}

struct PickerIconView: View {
    let entry: BrowserEntry
    let isSelected: Bool
    let size: CGFloat

    @State private var iconResolver = IconResolver()

    var body: some View {
        Image(nsImage: iconResolver.icon(
            forBundleIdentifier: entry.bundleIdentifier))
            .resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2)
                    .strokeBorder(
                        Color.accentColor,
                        lineWidth: isSelected ? 2 : 0)
            )
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
}
