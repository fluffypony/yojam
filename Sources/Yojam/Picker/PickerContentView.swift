import SwiftUI

struct PickerContentView: View {
    let url: URL
    let entries: [BrowserEntry]
    @State var selectedIndex: Int
    let layout: PickerLayout
    let onSelect: (BrowserEntry) -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    private static let selectionColor = Color.white.opacity(0.15)
    private static let selectionBorder = Color.white.opacity(0.5)

    var body: some View {
        VStack(spacing: 6) {
            switch layout {
            case .smallHorizontal:  smallHorizontalLayout
            case .bigHorizontal:    bigHorizontalLayout
            case .smallVertical:    smallVerticalLayout
            case .bigVertical:      bigVerticalLayout
            case .auto:             smallHorizontalLayout
            }
            Text(entries[safe: selectedIndex]?.fullDisplayName ?? "")
                .font(.system(size: 12, weight: .medium))
            Text(url.absoluteString)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(12)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { selectCurrent(); return .handled }
        // §48: Space opens selected entry (same as Return), not always first
        .onKeyPress(.space) { selectCurrent(); return .handled }
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

    // MARK: - Small Horizontal (icon strip with number badges)

    private var smallHorizontalLayout: some View {
        HStack(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) {
                index, entry in
                VStack(spacing: 2) {
                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(" ").font(.system(size: 10))
                    }
                    PickerIconView(
                        entry: entry, isSelected: index == selectedIndex, size: 36
                    )
                }
                .onTapGesture { selectedIndex = index; selectCurrent() }
                .onHover { if $0 { selectedIndex = index } }
                .accessibilityLabel("Open in \(entry.fullDisplayName)")
            }
        }
    }

    // MARK: - Big Horizontal (icon + label + number badge)

    private var bigHorizontalLayout: some View {
        HStack(spacing: 10) {
            ForEach(Array(entries.enumerated()), id: \.element.id) {
                index, entry in
                VStack(spacing: 2) {
                    if index < 9 {
                        Text("\(index + 1)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(" ").font(.system(size: 10))
                    }
                    VStack(spacing: 4) {
                        PickerIconView(
                            entry: entry, isSelected: index == selectedIndex, size: 56
                        )
                        Text(entry.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(width: 66)
                    }
                }
                .onTapGesture { selectedIndex = index; selectCurrent() }
                .onHover { if $0 { selectedIndex = index } }
                .accessibilityLabel("Open in \(entry.fullDisplayName)")
            }
        }
    }

    // MARK: - Small Vertical (compact list)

    private var smallVerticalLayout: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(Array(entries.enumerated()), id: \.element.id) {
                    index, entry in
                    HStack(spacing: 6) {
                        PickerIconView(
                            entry: entry,
                            isSelected: index == selectedIndex, size: 24)
                        Text(entry.fullDisplayName)
                            .font(.system(size: 12))
                        Spacer()
                        if index < 9 {
                            Text("\(index + 1)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == selectedIndex
                                  ? Self.selectionColor : .clear)
                    )
                    .onTapGesture { selectedIndex = index; selectCurrent() }
                    .onHover { if $0 { selectedIndex = index } }
                    .accessibilityLabel("Open in \(entry.fullDisplayName)")
                }
            }
        }.frame(maxHeight: 370)
    }

    // MARK: - Big Vertical (spacious list)

    private var bigVerticalLayout: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.element.id) {
                    index, entry in
                    HStack(spacing: 10) {
                        PickerIconView(
                            entry: entry,
                            isSelected: index == selectedIndex, size: 40)
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
                                  ? Self.selectionColor : .clear)
                    )
                    .onTapGesture { selectedIndex = index; selectCurrent() }
                    .onHover { if $0 { selectedIndex = index } }
                    .accessibilityLabel("Open in \(entry.fullDisplayName)")
                }
            }
        }.frame(maxHeight: 470)
    }

    // MARK: - Navigation

    private func move(_ delta: Int) {
        let newIndex = selectedIndex + delta
        if newIndex >= 0, newIndex < entries.count {
            selectedIndex = newIndex
        }
    }

    private func selectCurrent() {
        guard entries.indices.contains(selectedIndex) else { return }
        onSelect(entries[selectedIndex])
    }

    private func selectFirst() {
        guard !entries.isEmpty else { return }
        onSelect(entries[0])
    }

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

    private static let sharedIconResolver = IconResolver.shared

    var body: some View {
        let image: NSImage = {
            if let data = entry.customIconData, let img = NSImage(data: data) { return img }
            return Self.sharedIconResolver.icon(forBundleIdentifier: entry.bundleIdentifier)
        }()
        Image(nsImage: image)
            .resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2)
                    .strokeBorder(
                        Color.white.opacity(0.6),
                        lineWidth: isSelected ? 2 : 0)
            )
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
}
