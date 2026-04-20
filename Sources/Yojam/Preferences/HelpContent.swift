import Foundation

// MARK: - Central Help Text Catalog
// Single source of truth for all user-facing help copy.
// Tooltips, popovers, inline explanations, onboarding, and search keywords all draw from here.

enum HelpText {
    // MARK: - General Tab
    enum General {
        static let launchAtLogin = "Yojam starts automatically when you log in, so it's always running when you click a link."
        static let automaticUpdates = "Yojam checks yoj.am for new versions about once a day in the background. You can also check on demand from the menu bar."
        static let defaultBrowser = "Set Yojam as your system default browser so every link goes through it first."

        static let activationMode = "Pick when the browser chooser appears. Smart Fallback is nice once you've settled into a routine."
        static let activationAlways = "The browser picker shows up every time you click a link, so you always choose where it opens."
        static let activationHoldShift = "Links go straight to your default browser. Hold Shift while clicking to bring up the picker instead."
        static let activationSmartFallback = "Yojam learns which browser you pick for each site. It only asks when it hasn't seen the domain before."

        static let defaultSelection = "Which browser is pre-highlighted when the picker opens."
        static let defaultSelectionAlwaysFirst = "Always highlights the first browser in your list."
        static let defaultSelectionLastUsed = "Highlights whichever browser you used last."
        static let defaultSelectionSmart = "Highlights the browser you pick most often for this domain."

        static let pickerLayout = "Auto switches between horizontal and vertical depending on how many browsers you have. The other options lock it to one layout."
        static let verticalThreshold = "With Auto layout, the picker switches to a vertical list once you have more browsers than this number."
        static let invertOrder = "Controls the order browsers appear in the picker. Automatic follows the system UI direction (right-to-left in RTL locales). The other options let you force a specific direction regardless of locale — useful if your go-to browser feels better on the other side."
        static let soundEffects = "Plays a short confirmation sound when you pick a browser. Useful as an auditory confirmation for VoiceOver users."
        static let recentURLs = "Shows recent links in the menu bar so you can re-open one in a different browser."
        static let recentURLsAutoDelete = "Clears old entries from the recent URLs list after this long."
        static let clipboardMonitoring = "When you copy a URL, a small notification pops up so you can route it through Yojam without clicking the link again."
        static let iCloudSync = "Syncs your browser list, rules, and preferences across your Macs. Custom icons and local paths stay on each machine."
    }

    // MARK: - Browsers Tab
    enum Browsers {
        static let dragReorder = "Drag to reorder. The first enabled browser is your default, used when Yojam opens links silently."
        static let privateWindow = "Opens every link in a private window. Safari and Orion use AppleScript for this, which needs Accessibility permission."
        static let stripTrackers = "Strips tracking parameters (utm_source, fbclid, etc.) from URLs before opening them in this browser."
        static let profileSelection = "Pick which browser profile to use. You can add the same browser more than once for different profiles.\n\nSafari profile targeting requires the Yojam Safari Extension to be enabled in each profile. Each enabled extension self-registers its profile on first run.\n\nOrion profiles exist but Yojam does not yet have a supported per-profile launch path. To route to a specific Orion profile, add Orion as a custom app with custom launch args."
        static let customLaunchArgs = "Pass command-line arguments when launching this browser. Use $URL where the link should go.\n\nExamples:\n\u{2022} --new-window $URL\n\u{2022} --app=$URL\n\u{2022} --profile-directory=\"Work\" $URL\n\nLeave blank for normal behavior."
        static let customIcon = "Set a custom icon for this browser in the picker. Stored locally, not synced via iCloud."
        static let suggestedBrowsers = "Browsers detected on your Mac that aren't in your list yet. Click Add to include one."
        static let emailClients = "Apps that handle mailto: links. Turn on the ones you want Yojam to offer for email links."
    }

    // MARK: - Pipeline Tab
    enum Pipeline {
        static let stripTrackingGlobal = "Strips tracking parameters (utm_source, fbclid, gclid, etc.) from every URL before any browser sees it. You can also turn this on per-browser in the Browsers tab."
        static let pipelineOrder = "Links flow through top to bottom: rewrites run first, then tracker stripping, then routing rules pick the browser."
        static let urlTester = "Paste a URL to preview how Yojam would handle it: which rewrites apply, what gets stripped, and where it ends up."
        static let ruleMatchType = "Host (exact): match one host exactly. Host suffix: match the host and any subdomains. Full URL prefix: match the start of the URL (scheme-insensitive). Host + path prefix: match the start of the host+path portion, ignoring query. URL contains: match anywhere in the URL. Regex: full pattern matching."
        static let rulePriority = "Lower numbers run first. When two rules match the same URL, the lower number wins."
        static let ruleSourceApp = "Only applies when the link came from a specific app (e.g. com.apple.mail). Leave blank to match all apps.\n\nFor links from Handoff, AirDrop, the Share Extension, and other non-app sources, Yojam uses synthetic IDs like com.yojam.source.handoff and com.yojam.source.airdrop."
        static let rewriteMatch = "A regex pattern matched against the full URL. Use capture groups like (.*) to grab parts you want to keep."
        static let rewriteReplacement = "The replacement URL. Use $1, $2, etc. to insert captured groups from the match pattern."
    }

    // MARK: - Advanced Tab
    enum Advanced {
        static let debugLogging = "Writes detailed logs for troubleshooting to ~/Library/Logs/Yojam/. Files rotate at 10 MB."
        static let periodicRescan = "How often Yojam checks for newly installed or removed browsers (in seconds)."
        static let learnedPreferences = "Yojam remembers which browser you pick for each domain when Smart selection is active. View & Manage lets you remove specific domains or promote a learned preference into an explicit routing rule."
        static let exportSettings = "Saves your browsers, rules, rewrites, and preferences to a JSON file. Good for backups or moving to another Mac."
        static let importSettings = "Loads settings from a previously exported file. Replaces your current browser list and rules."
        static let importFromOtherApps = "Detects rules from Bumpr, Choosy, and Finicky if they're installed on this Mac. Imported rules are marked with a metadata tag so you can review them afterwards."
        static let flatFileConfig = "Yojam writes a human-editable copy of your config to ~/Library/Application Support/Yojam/config.json. Editing that file is picked up live — useful for dotfiles or scripted changes."
        static let redetectBrowsers = "Scans your system for browsers and rebuilds the list from scratch."
        static let resetAll = "Wipes all settings, rules, and learned preferences back to factory defaults."
        static let uninstall = "Removes native messaging manifests, the login item, and log files. If the checkbox is enabled, also wipes your rules and preferences."
        static let trackerParameterList = "URL parameters that get stripped when tracker removal is on. One per line."
        static let suppressedClipboardDomains = "Domains to skip when clipboard monitoring is on. URLs from these won't trigger the notification."
    }

    // MARK: - Rules Tab extras
    enum Rules {
        static let builtInEditing = "Built-in rules can now be edited, duplicated, or reset to defaults like user-defined rules. Deleted built-ins won't reappear on next launch; use Restore Default Rules to bring them back."
        static let firefoxContainer = "Opens matching links in a specific Firefox container. Requires the Yojam Firefox extension. Leave blank to use the default context."
        static let displayTargeting = "Optional: move the browser window to a specific display after it opens. Requires Accessibility permission (System Settings > Privacy & Security > Accessibility)."
    }

    // MARK: - Integrations Tab
    enum Integrations {
        static let defaultBrowser = "When Yojam is your default browser, all link clicks in other apps go through Yojam's routing pipeline."
        static let weblocHandler = "When enabled, AirDropped links (which arrive as .webloc files) are routed through Yojam instead of opening in the default browser."
        static let yojamScheme = "The yojam:// URL scheme is used by the Share Extension, browser extensions, and automation tools like Shortcuts, Raycast, and Alfred to send links to Yojam."
        static let handoff = "When Handoff is enabled and Yojam is your default browser, pages you're viewing on your iPhone or iPad can be continued on your Mac through Yojam."
        static let shareExtension = "The Share Extension adds \"Open in Yojam\" to the macOS share menu in Safari, Notes, Mail, Finder, and other apps."
        static let safariExtension = "The Safari Web Extension adds a toolbar button, context menu item, and Alt+Shift+Y shortcut to route links through Yojam.\n\nSafari profile targeting is experimental: enable the extension in each profile you want Yojam to recognize, and it will register itself. The existing AppleScript path handles private-window requests only, not per-profile targeting."
        static let servicesMenu = "Highlight any URL in any Cocoa app, right-click, and choose Services > Open in Yojam. You can also assign a global keyboard shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services."
        static let nativeMessaging = "The native messaging host lets browser extensions communicate with Yojam without triggering the OS protocol-handler prompt on every click."
        static let appGroup = "The App Group container (group.org.yojam.shared) is used to share routing configuration between the main app and its extensions."
    }

    // MARK: - Source App Sentinels
    enum Sentinels {
        static let ruleSourceHelp = "For links from Handoff, AirDrop, the Share Extension, and other non-app sources, Yojam uses synthetic bundle IDs. You can target these in rules:\n\n\u{2022} com.yojam.source.handoff\n\u{2022} com.yojam.source.airdrop\n\u{2022} com.yojam.source.share-extension\n\u{2022} com.yojam.source.service\n\u{2022} com.yojam.source.safari-extension\n\u{2022} com.yojam.source.chrome-extension\n\u{2022} com.yojam.source.firefox-extension\n\u{2022} com.yojam.source.url-scheme"
    }

    // MARK: - Picker
    enum Picker {
        static func hoverHint(browserName: String, index: Int) -> String {
            if index < 9 {
                return "Open in \(browserName), press \(index + 1) or Return"
            }
            return "Click or press Return to open in \(browserName)"
        }

        static func selectionHint(browserName: String, index: Int) -> String {
            if index < 9 {
                return "Press \u{21B5} or \(index + 1) to open in \(browserName)"
            }
            return "Press \u{21B5} to open in \(browserName)"
        }
    }
}
