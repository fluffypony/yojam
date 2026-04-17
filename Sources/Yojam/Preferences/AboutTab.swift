import SwiftUI
import AppKit

struct AboutTab: View {
    @Binding var scrollToSection: String?

    var body: some View {
        VStack(spacing: 0) {
            ThemeContentHeader(title: "About", subtitle: "Version, credits, and license.")

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        headerSection.id("About")
                        linksSection.id("Links")
                        licenseSection.id("License")
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: scrollToSection) { _, section in
                    guard let section else { return }
                    withAnimation { proxy.scrollTo(section, anchor: .top) }
                    scrollToSection = nil
                }
            }
        }
        .background(Theme.bgApp)
    }

    // MARK: - Header

    private var headerSection: some View {
        ThemePanel {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)

                Text("Yojam")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Theme.textInverse)

                Text("Version \(Self.shortVersion) (\(Self.buildNumber))")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)

                Text("© 2026 Riccardo Spagni")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "Links")
            ThemePanel {
                ThemePanelRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Website")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("yoj.am")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Visit") {
                        openURL("https://yoj.am")
                    }
                }
                ThemePanelRow(isLast: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source Code")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("github.com/fluffypony/yojam")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ThemeButton("Open") {
                        openURL("https://github.com/fluffypony/yojam")
                    }
                }
            }
        }
    }

    // MARK: - License

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemeSectionTitle(text: "License")
            VStack(alignment: .leading, spacing: 8) {
                Text("Yojam is released under the BSD 3-Clause License.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                ScrollView {
                    Text(Self.licenseText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(height: 220)
                .background(Theme.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private static let licenseText: String = """
BSD 3-Clause License

Copyright (c) 2026, Riccardo Spagni
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""
}
