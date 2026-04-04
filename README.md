# Yojam

macOS has one default browser slot. If you use more than one browser,
that's a problem.

Yojam sits in that slot instead. When you click a link anywhere -- Slack,
Mail, Notes, Terminal -- Yojam catches it and shows a picker at your
cursor. Pick a browser, hit Enter, done. The whole thing takes under
80ms.

It also routes URLs to native apps automatically. Zoom links open Zoom.
Spotify links open Spotify. Telegram links open Telegram. You get a
sensible set of these rules out of the box and can add your own,
including regex patterns.

## What it does

- **Browser picker** -- a floating strip of icons at your cursor. Keyboard
  navigable (arrow keys, 1-9 number keys, Return to confirm, Space to
  open in your default browser, Escape to cancel).
- **URL rules** -- pattern-match URLs to specific apps. Ships with ~20
  built-in rules (Zoom, Slack, Discord, Figma, etc.). Supports domain,
  prefix, contains, and regex matching.
- **Browser profiles** -- Chrome, Firefox, Brave, Edge, Vivaldi profiles
  each appear as separate picker entries. Your "Chrome -- Work" and
  "Chrome -- Personal" are distinct choices.
- **URL rewriting** -- transform URLs before opening (Twitter to Nitter,
  Reddit to Old Reddit, etc.). Regex with capture groups.
- **UTM stripping** -- removes tracking parameters (utm_source, fbclid,
  gclid, and 30+ others). Configurable at global, per-browser, and
  per-rule levels.
- **Clipboard monitoring** -- detects copied URLs and offers to route
  them. Opt-in, polls only on pasteboard change.
- **Modifier+click intercept** -- hold Cmd+Shift (configurable) while
  clicking any link to force the picker, regardless of activation mode.
  Requires Accessibility permissions.
- **mailto: handling** -- routes email links to your preferred mail
  client.
- **iCloud sync** -- sync browser lists, rules, and settings across Macs.
  Off by default.
- **Shortcuts.app** -- exposes "Open URL in Browser", "Get Browser List",
  and "Apply URL Rules" actions.
- **Auto-detection** -- watches /Applications for new browsers via
  FSEvents, workspace notifications, and periodic rescans.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ to build from source
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the
  Xcode project

## Building

```sh
brew install xcodegen
cd yojam
xcodegen generate
open Yojam.xcodeproj
```

Build and run the `Yojam` scheme. On first launch it asks to become the
default browser -- say yes, or nothing works.

The app runs as a menu bar utility (no dock icon). Look for the globe
icon in the menu bar.

For a release build: Product -> Archive -> Distribute -> Developer ID
(notarized).

Note: `swift build` alone produces a bare executable, not an app bundle.
The Xcode project is required for URL scheme registration, entitlements,
and code signing to work.

## Configuration

Everything lives in the Preferences window (click the menu bar icon ->
Preferences, or Cmd+,).

### Activation modes

| Mode | What happens |
|------|-------------|
| Always | Picker appears on every link |
| Hold Shift | Links go to your default browser; hold Shift to get the picker |
| Smart + Fallback | Rules fire first; picker only shows when nothing matches |

### Adding rules

Preferences -> URL Rules -> Add Rule. Pick a match type (domain,
contains, regex, etc.), enter the pattern, choose the target app.
There's a live test field -- paste a URL and see if it matches before
saving.

## Privacy and Permissions

Yojam needs Accessibility permissions if you want to use the Universal
Click Modifier (holding Cmd+Shift while clicking links in any app).
Without it, Yojam still works for every URL opened through normal
system means.

All data stays local unless you turn on iCloud sync. No analytics. No
network calls. No telemetry.

## Why not Finicky, Choosy, or Browserosaurus?

Finicky requires writing JavaScript config files. It's powerful but
setting it up feels like work. Choosy costs money and hasn't been
updated in a while. Browserosaurus is an Electron app -- a massive
memory footprint for something that should consume almost nothing.

Yojam is native Swift/AppKit/SwiftUI, runs entirely in the background,
and has a proper preferences UI.

## License

BSD 3-Clause. See LICENSE.
