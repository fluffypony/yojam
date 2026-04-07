<p align="center">
  <img src="logo.png" alt="Yojam" width="400">
</p>

### Open links in whatever browser, app, or profile you need - whatever yo jam is.

I kept running into this problem: I clicked a link in Slack, and it opened in Safari. But I was logged into that AWS account in Chrome Profile 3, and the Figma link should just open in the desktop app, not another browser tab.

Yojam fixes that. Set it as your default browser, and it catches every link you click. Using rules you define, it routes each link exactly where it belongs - or pops up a fast picker right at your cursor so you can choose on the fly.

## What it actually does

- **Rules engine:** Route URLs by domain, prefix, regex, or source app. Send work stuff to your corporate Edge profile and personal stuff to Safari.
- **Profile support:** Targets specific profiles in Chrome, Firefox, Brave, Edge, Vivaldi, and Opera. Work profile for work links, personal for everything else.
- **Tracking garbage removal:** Strips `utm_source`, `fbclid`, `gclid`, and 30+ other tracking parameters before the browser ever sees them. Per-browser or globally.
- **URL rewriting:** Regex-based find/replace on URLs. Ships with disabled-by-default examples for Twitter→Nitter, Reddit→Old Reddit, Medium→Scribe.
- **Private windows:** One checkbox to always open a browser in incognito/private mode. Works for Chromium, Firefox, and Safari/Orion (via AppleScript).
- **Email handling:** Catches `mailto:` links and routes them to your preferred client.
- **Clipboard monitor:** Optionally watches your clipboard and offers to open copied links.
- **Auto-learning:** Yojam notices which browser you pick for each domain and starts suggesting it automatically.
- **iCloud sync:** Your rules and browser setups sync across all your Macs.
- **Shortcuts integration:** "Open URL in Browser" and "Apply URL Rules" intents for automation.
- **Menu bar only:** No dock icon, no Cmd+Tab entry. Just a menu bar icon with recent URLs and quick access to preferences.

## Receiving links

Yojam picks up links from every source macOS can offer:

- Clicks in any app that opens `http`/`https` URLs (the default-browser path).
- Finder double-clicks on `.html`, `.xhtml`, `.webloc`, `.inetloc`, and `.url` files.
- **Handoff** — pages you continue from another Apple device.
- **AirDrop** — links arrive as `.webloc` files, which Yojam unwraps transparently.
- **macOS Share menu**, via the bundled Share Extension.
- **Services menu** — highlight any URL in any Cocoa app, right-click, choose *Open in Yojam*.
- **Browser extensions** for Safari, Chrome, and Firefox.
- The `yojam://` URL scheme, for Shortcuts, Raycast, Alfred, shell scripts, and any other automation.

Every one of these goes through the same rule engine, tracker scrubber, and rewrite pipeline as a direct click. There is no second-class handling.

## Installing

Download the latest release from [yojam.org](https://yojam.org). Open the DMG and drag Yojam to your Applications folder. On first launch, Yojam asks to become your default browser.

Yojam checks for updates automatically. You can also check manually from the menu bar icon > "Check for Updates..."

## Building from source

You need macOS 14+ and Xcode 16+. Yojam uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) for the project file.

```bash
# Install xcodegen if you haven't
brew install xcodegen

# Generate the Xcode project and build
xcodegen generate
open Yojam.xcodeproj
```

Build and run from Xcode. On first launch, Yojam asks to become your default browser - say yes, that's how it intercepts links.

> **Note:** `swift build` / `swift run` compiles the code and runs tests, but won't produce a working `.app` bundle. macOS requires a proper app bundle with Info.plist and URL scheme registration to function as a default browser. The Share Extension, Safari Web Extension, and native messaging host are Xcode-only targets produced by `xcodegen generate && xcodebuild`.

### Building the extensions

- The **Share Extension**, **Safari Web Extension**, and **native messaging host** are Xcode-only targets. `swift build` only builds the bare Yojam executable and `YojamCore` library.
- `Extensions/build.sh` produces `dist/yojam-chrome.zip` and `dist/yojam-firefox.xpi` from the shared WebExtension source. Signing and store submission are out of scope for this script.

## How it works

When you click a link anywhere on your Mac, Yojam processes it through a pipeline:

1. **Global rewrites** - URL transformations (regex find/replace)
2. **Tracker scrubbing** - Strips tracking parameters (skipped for `mailto:` so subjects and bodies stay intact)
3. **Rule matching** - Checks the clean URL against your routing rules top-to-bottom. First match wins.
4. **Browser-specific rewrites** - Per-browser transforms after the target is determined
5. **Open or pick** - If a rule matches, the link fires immediately. Otherwise, the picker appears at your cursor.

## Activation modes

| Mode | What happens |
|---|---|
| **Always show picker** | Every link shows the browser picker |
| **Hold Shift to pick** | Links route via rules or your default. Hold Shift to force the picker. |
| **Smart + Fallback** | Rules fire automatically. Learned domains auto-route. Everything else shows the picker. |

## Picker keyboard shortcuts

| Key | Action |
|---|---|
| 1–9 | Jump to browser at that position |
| ←→ / ↑↓ | Move selection |
| Enter / Space | Open in selected browser |
| Cmd+C | Copy URL to clipboard |
| Esc | Dismiss picker |

## Rules

Yojam ships with built-in rules for Zoom, Telegram, Slack, Discord, Spotify, Apple Music, FaceTime, Apple Maps, Microsoft Teams, Figma, Linear, Notion, WhatsApp, Signal, App Store, TestFlight, and Podcasts. They auto-disable when the target app isn't installed and re-enable when it is.

Add your own rules matching on domain (exact), domain suffix, URL prefix, URL substring, or regex. Rules can optionally filter by source app - only route GitHub links from Slack to your work browser, for example.

### Source-app sentinels for rules

For ingress paths that don't have a real originating app, Yojam uses synthetic bundle identifiers. You can target these in rules to handle links differently depending on how they arrived:

| Sentinel | Ingress path |
|---|---|
| `com.yojam.source.handoff` | Handoff from another Apple device |
| `com.yojam.source.airdrop` | AirDropped .webloc files |
| `com.yojam.source.share-extension` | Share menu |
| `com.yojam.source.service` | Services menu |
| `com.yojam.source.safari-extension` | Safari extension |
| `com.yojam.source.chrome-extension` | Chrome/Chromium extension |
| `com.yojam.source.firefox-extension` | Firefox extension |
| `com.yojam.source.url-scheme` | `yojam://` URL scheme |

For example, you could write a rule like: *Source App = `com.yojam.source.handoff` → always open in Work profile*.

## Share Extension

The Share Extension adds "Open in Yojam" to the macOS share menu. It shows up in Safari, Notes, Mail, Finder, Reminders, Photos, and other apps that support the share sheet. One tap forwards the URL to Yojam silently.

To enable it: **System Settings > Privacy & Security > Extensions > Sharing**, then turn on Yojam.

## Services menu

The "Open in Yojam" entry appears in the Services menu in every Cocoa app. Highlight any URL text, right-click, and pick it from the Services submenu.

To add a global keyboard shortcut: **System Settings > Keyboard > Keyboard Shortcuts > Services**, find "Open in Yojam", and assign a shortcut.

## Browser extensions

### Safari

Ships inside Yojam.app. Enable it in **Safari > Settings > Extensions**.

### Chrome / Brave / Edge / Vivaldi / Arc

Load from `Extensions/dist/yojam-chrome.zip` (or install from the Chrome Web Store once published). The native messaging host is installed automatically on Yojam's first launch. If something breaks, repair it from **Preferences > Integrations > Reinstall Browser Helpers**.

### Firefox

Install the `.xpi` from `Extensions/dist/` (or from AMO once published).

### What each extension does

- **Toolbar button** — click to send the current tab to Yojam.
- **Context menu** — right-click any link and choose "Open Link in Yojam", or right-click the page background for "Open Page in Yojam".
- **Keyboard shortcut** — `Alt+Shift+Y` sends the current tab to Yojam.

## `yojam://` URL scheme

Yojam registers a `yojam://` URL scheme for automation. Any app, script, or shortcut can trigger it:

```
yojam://route?url=<percent-encoded>&source=<bundle-id>&browser=<bundle-id>&pick=1&private=1
yojam://settings
```

Parameters:
- `url` (required): the target URL. Must decode to `http`, `https`, or `mailto`.
- `source` (optional): bundle identifier for source-app rule matching.
- `browser` (optional): force a specific target browser by bundle ID, skipping rules.
- `pick=1` (optional): force the picker regardless of activation mode.
- `private=1` (optional): open in private/incognito window if the target browser supports it.

Example Shortcuts recipe: create a Shortcut with an "Open URL" action pointing at `yojam://route?url=` followed by the URL you want to route.

## Custom apps

Not limited to browsers. Click **+ Add** in the Browsers tab and pick any `.app` or executable. For apps that don't natively handle URLs, set custom launch arguments using `$URL` as a placeholder:

```
$URL
--url $URL
--browse $URL
```

Yojam runs the executable directly with these arguments - no shell involved.

## Settings

Five tabs in preferences (menu bar icon > Preferences, or Cmd+,):

- **General** - Activation mode, picker layout, launch at login, clipboard monitoring, iCloud sync
- **Browsers** - Reorder, enable/disable, profiles, private mode, per-browser tracker stripping, custom icons, custom launch args
- **URL Pipeline** - Routing rules, rewrite rules, global tracker stripping, URL tester
- **Integrations** - Health dashboard for default browser, .webloc handler, yojam:// scheme, Handoff, Share Extension, Safari extension, native messaging hosts, App Group access. One-click repair buttons for each.
- **Advanced** - Debug logging, tracker parameter list, smart routing data, import/export settings, reset

The URL tester on the Pipeline tab lets you paste a URL and see exactly what Yojam would do - which rewrites fire, whether trackers get stripped, which rule matches, and where it ends up.

Settings can be exported as JSON and imported on another machine.

## Permissions

- **App Group** `group.org.yojam.shared` — shared storage between the main app and its extensions.
- **iCloud Key-Value Store** — for settings sync (off by default).
- **Apple Events** — for AppleScript-based private windows in Safari and Orion.

The first time certain features are used, macOS will show:
- A protocol-handler confirmation for `yojam://` (from browser extension fallback path).
- A prompt to enable the Share Extension (System Settings > Extensions > Sharing).
- A prompt to enable the Safari Web Extension (Safari > Settings > Extensions).

## Privacy

Everything happens locally on your Mac. Yojam doesn't phone home, track your clicks, or send your data anywhere. The Share Extension and browser extensions only hand a URL to the local Yojam process. The native messaging host only forwards URLs you explicitly trigger — it never reads page contents. Nothing hits the network.

The only network activity is iCloud sync (uses your own Apple ID, off by default) and checking for updates via yojam.org (can be disabled in Preferences).

## Troubleshooting

- **Handoff link doesn't appear** — Confirm Yojam is your default browser, and that Handoff is on in System Settings > General > AirDrop & Handoff.
- **Share Extension missing** — Enable it in System Settings > Privacy & Security > Extensions > Sharing.
- **Browser extension button does nothing** — Go to Preferences > Integrations and click "Reinstall Browser Helpers" to rewrite native messaging manifests.
- **Safari extension not showing** — Enable it in Safari > Settings > Extensions.
- **AirDropped link file opens in Finder instead** — Set Yojam as the default handler for `.webloc` from Preferences > Integrations.
- **Pre-release settings missing** — This release stores all routing state in an App Group container. If you upgraded from a pre-release build, your old preferences in `~/Library/Preferences/com.yojam.app.plist` are not read. Reconfigure from Preferences.

## License

BSD 3-Clause. See LICENSE.

## Why I built this

There are other browser pickers out there. I wanted one that felt invisible most of the time, stripped trackers globally, supported browser profiles as first-class citizens, and let me pass custom CLI arguments when I needed to do something weird.

## Contributing

This project follows a hard-cut policy: we delete old-state compatibility code rather than carrying it forward. Any temporary migration or compatibility code must be called out in the same diff with why it exists, why the canonical path is insufficient, exact deletion criteria, and the task that tracks its removal.
