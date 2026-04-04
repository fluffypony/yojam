import Foundation

enum KnownAppAllowlist {
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "com.operasoftware.Opera",
        "org.chromium.Chromium", "app.zen-browser.zen",
        "com.google.Chrome.canary", "org.mozilla.firefoxdeveloperedition",
    ]

    static let emailClients: Set<String> = [
        "com.apple.mail", "com.google.Gmail", "com.microsoft.Outlook",
        "com.readdle.smartemail-macos", "com.fastmail.app", "com.freron.MailMate",
    ]
}
