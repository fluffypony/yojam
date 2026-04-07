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

> **Note:** `swift build` / `swift run` compiles the code and runs tests, but won't produce a working `.app` bundle. macOS requires a proper app bundle with Info.plist and URL scheme registration to function as a default browser.

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

## Custom apps

Not limited to browsers. Click **+ Add** in the Browsers tab and pick any `.app` or executable. For apps that don't natively handle URLs, set custom launch arguments using `$URL` as a placeholder:

```
$URL
--url $URL
--browse $URL
```

Yojam runs the executable directly with these arguments - no shell involved.

## Settings

Four tabs in preferences (menu bar icon → Preferences, or ⌘,):

- **General** - Activation mode, picker layout, launch at login, clipboard monitoring, iCloud sync
- **Browsers** - Reorder, enable/disable, profiles, private mode, per-browser tracker stripping, custom icons, custom launch args
- **URL Pipeline** - Routing rules, rewrite rules, global tracker stripping, URL tester
- **Advanced** - Debug logging, tracker parameter list, smart routing data, import/export settings, reset

The URL tester on the Pipeline tab lets you paste a URL and see exactly what Yojam would do - which rewrites fire, whether trackers get stripped, which rule matches, and where it ends up.

Settings can be exported as JSON and imported on another machine.

## Privacy

Everything happens locally on your Mac. Yojam doesn't phone home, track your clicks, or send your data anywhere. The only network activity is iCloud sync (uses your own Apple ID, off by default) and checking for updates via yojam.org (can be disabled in Preferences).

## License

BSD 3-Clause. See LICENSE.

## Why I built this

There are other browser pickers out there. I wanted one that felt invisible most of the time, stripped trackers globally, supported browser profiles as first-class citizens, and let me pass custom CLI arguments when I needed to do something weird.
