<p align="center">
  <img src="logo.png" alt="Yojam" width="400">
</p>

### Open links in whatever browser, app, or profile you need - whatever yo jam is.

I kept running into this problem: I clicked a link in Slack, and it opened in Safari. But I was logged into that AWS account in Chrome Profile 3, and the Figma link should just open in the desktop app, not another browser tab.

Yojam fixes that. Set it as your default browser, and it catches every link you click. Using rules you define, it routes each link exactly where it belongs - or pops up a fast picker right at your cursor so you can choose on the fly.

## What it actually does

- **Rules engine:** Route URLs by domain, prefix, regex, source app, or all links from a source. Send work stuff to your corporate Edge profile and personal stuff to Safari. Each rule can override the target browser's defaults: specific profile, private-window on/off, custom launch args, target display, machine scope, or named Firefox/Orion container.
- **Profile support:** Targets specific profiles in Chrome, Firefox, Brave, Edge, Vivaldi, and Opera. Work profile for work links, personal for everything else.
- **Firefox and Orion containers:** Rules can route into a named container (Work, Personal, Banking, etc.) through the Yojam WebExtension. The link gets reopened inside the right contextual identity instead of the default context.
- **Multi-monitor targeting:** Pin a rule's output to a specific display. Jira on the left screen, Slack-forwarded links on the right, whatever you want.
- **Tracking garbage removal:** Strips `utm_source`, `fbclid`, `gclid`, and 30+ other tracking parameters before the browser ever sees them. Per-browser or globally.
- **URL rewriting:** Regex-based find/replace on URLs. Ships with disabled-by-default examples for Twitter→Nitter, Reddit→Old Reddit, Medium→Scribe.
- **Private windows:** One checkbox to always open a browser in incognito/private mode. Works for Chromium, Firefox, and Safari/Orion (via AppleScript).
- **Email handling:** Catches `mailto:` links and routes them to your preferred client.
- **Clipboard monitor:** Optionally watches your clipboard and offers to open copied links.
- **Auto-learning:** Yojam notices which browser you pick for each domain and starts suggesting it automatically.
- **Import from Bumpr, Choosy, or Finicky:** On first launch, Quick Start finds installed apps and offers an import. Review compatible routes, rewrites, and conversion warnings before Yojam adds selected items. Yojam skips duplicates. Finicky configs are parsed, not run.
- **Flat-file config:** A live-editable JSON copy of your setup at `~/Library/Application Support/Yojam/config.json`. Edits in the file get picked up by the app in real time, and vice-versa. Good for dotfile repos or scripted changes.
- **iCloud sync:** Your rules and browser setups sync across all your Macs, with per-rule machine scope for rules that should only run on one Mac.
- **Shortcuts integration:** "Open URL in Browser" and "Apply URL Rules" intents for automation.
- **Menu bar only:** No dock icon, no Cmd+Tab entry. Just a menu bar icon with Link History and quick access to preferences.

## Receiving links

Yojam picks up links from every source macOS can offer:

- Clicks in any app that opens `http`/`https` URLs (the default-browser path).
- Sign-in windows from apps that use `ASWebAuthenticationSession`, such as Slack and Claude.
- Finder double-clicks on `.html`, `.xhtml`, `.webloc`, `.inetloc`, and `.url` files.
- **Handoff** — pages you continue from another Apple device.
- **AirDrop** — links arrive as `.webloc` files, which Yojam unwraps transparently.
- **macOS Share menu**, via the bundled Share Extension.
- **Services menu** — highlight any URL in any Cocoa app, right-click, choose *Open in Yojam*.
- **Browser extensions** for Safari, Chrome, and Firefox.
- The `yojam://` URL scheme, for Shortcuts, Raycast, Alfred, shell scripts, and any other automation.

Every one of these goes through the same rule engine, tracker scrubber, and rewrite pipeline as a direct click. There is no second-class handling.

Yojam forwards the first URL from a web authentication session to your chosen browser. It cannot see later navigation inside that browser or send the callback to the source app. An app that depends only on the session callback can keep waiting after you finish in the browser. Apps with a separate callback URL handler can still finish the sign-in. Yojam does not claim ephemeral-session support because the chosen browser keeps its cookies and profile state.

## Installing

Install via Homebrew:

```bash
brew install --cask yojam
```

Or grab the DMG from [yoj.am](https://yoj.am) and drag Yojam to your Applications folder. On first launch, Yojam asks to become your default browser.

Yojam checks yoj.am for updates every hour. When a new version is ready, a dot appears on the menu bar icon, the menu gains an *Update to Yojam x.y.z…* entry, Preferences shows an *Install Update* button, and Yojam posts a notification if you allow it. You can also check any time from Preferences > General > Updates, from the About tab, or from the menu bar icon > *Check for Updates…*.

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

## Release engineering

The release script builds the app, signs it with Developer ID, notarises the DMG, and generates signed Sparkle updates. Publishing the website and GitHub release are separate steps.

### Prepare the release

You need Xcode, XcodeGen, `create-dmg`, and the GitHub CLI. The signing Mac also needs:

- A Developer ID Application certificate and access to the app's provisioning profiles.
- `ExportOptions.plist` in the project root, with the `developer-id` export method and your Apple team ID.
- Notarisation credentials in the `YojamNotarize` Keychain profile. Set `YOJAM_NOTARIZE_PROFILE` if you use another profile.
- The existing Sparkle EdDSA key in Keychain. Its public key must match `SUPublicEDKey` in `project.yml`. Back up this key securely: replacing it can prevent installed copies from accepting updates. `YOJAM_SPARKLE_PRIVATE_KEY_FILE` can select an explicit signing key file; the script checks that it matches too.

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle compares the build number, so it must increase with every release.
2. Set the same version in `Extensions/chrome/manifest.json`, `Extensions/firefox/manifest.json`, and `Extensions/safari/manifest.json`.
3. Run `swift test`, then build the app with Xcode and test the changed flows. Check the bundled integrations as well: the Swift package alone does not build them.
4. Commit the release changes. Keep `Package.resolved` committed; the release build uses its pinned dependencies.

### Build and sign

Keep the previous release DMGs in `build/releases/` so Sparkle can generate delta updates. On a fresh checkout, copy those DMGs from the published releases before you build.

```bash
export RS_TEAM_ID="YOUR_APPLE_TEAM_ID"
./scripts/release.sh
```

The script validates the app bundle and signatures, checks the exported version, notarises and staples the DMG, then generates the appcast. Stop if any step fails. `--skip-archive` reuses an existing archive and checks its version; `--skip-notarize` is for local checks, not a public release.

The outputs are:

- `build/Yojam-<version>.dmg`, the signed and notarised installer.
- `build/releases/appcast.xml`, with the version, download URLs, file lengths, and Sparkle signatures.
- The DMGs and any `.delta` files in `build/releases/` that the appcast references. The script signs and verifies these update files.
- `Extensions/dist/yojam-chrome.zip` and `Extensions/dist/yojam-firefox.xpi`. The Firefox XPI from this script is unsigned; Mozilla signing is a separate step.

Mozilla requires two-step authentication on the developer account before its first add-on submission. Before publishing the Firefox package, obtain API credentials from the [AMO Developer Hub](https://addons.mozilla.org/developers/addon/api/key/) and load them into `WEB_EXT_API_KEY` and `WEB_EXT_API_SECRET`. Keep them out of the repository and shell history. Then run:

```bash
./Extensions/sign-firefox.sh
```

This validates the extension, submits it for unlisted Mozilla signing, and replaces `Extensions/dist/yojam-firefox.xpi` only when a signed package returns. Unlisted signing lets Firefox users install the GitHub download without an AMO store listing. If Mozilla holds the submission for review, wait for the signed package before publishing it. Keep a separate copy of that package if you rerun the build: `Extensions/build.sh` recreates `dist/`.

### Publish and verify

1. Tag the release commit as `v<version>` and push the commit and tag.
2. Publish the versioned DMG and every delta referenced by the appcast at `https://yoj.am/releases/`. Keep older files available for clients that cached an earlier feed.
3. Replace `https://yoj.am/yojam.dmg` with the new DMG and publish the generated feed at `https://yoj.am/appcast.xml`. Make the download files available before the feed, or deploy them together atomically. Preserve the generated `/releases/` enclosure URLs and signatures.
4. Create the GitHub release for the tag. Attach the DMG and both extension packages, and include release notes with any installation requirements.
5. Check the live feed and all its enclosure URLs. Verify that the hosted DMG has the same SHA-256 hash as the local release. Open an older installed version, use *Check for Updates*, and complete the update. Check the hourly update reminder too, including Preferences when the menu bar icon is hidden.
6. Once the downloads are live, open the Homebrew cask update:

   ```bash
   brew bump --open-pr yojam
   ```

   If the command reports `Cask is autobumped`, leave the pull request to BrewTestBot. Homebrew runs these version bumps about every three hours. Check the resulting pull request for the version, download URL, and SHA-256 hash. If a pull request already exists, check that one instead of opening a duplicate.

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
| **Always show picker** | Unmatched links show the browser picker; matching rules still fire immediately. |
| **Hold Shift to pick** | Links route via rules or your default. Keep Shift held until the picker appears to choose instead. |
| **Smart + Fallback** | Rules fire automatically. Learned domains auto-route. Everything else shows the picker. |

Shift also acts as a one-off escape hatch in the other modes: it skips matching rules and URL rewrites, then shows the picker with the original link. macOS delivers an external URL separately from the originating click, so keep Shift held until Yojam's picker appears.

## Picker keyboard shortcuts

| Key | Action |
|---|---|
| 1–9 | Jump to browser at that position |
| ←→ / ↑↓ | Move selection |
| Enter / Space | Open in selected browser |
| Cmd+C | Copy URL to clipboard |
| Esc | Dismiss picker |

## Rules

Yojam ships with built-in rules for Zoom, Telegram, Slack, Discord, Spotify, Apple Music, FaceTime, Apple Maps, Microsoft Teams, Figma, Linear, Notion, WhatsApp, Signal, App Store, TestFlight, and Podcasts. They auto-disable when the target app isn't installed and re-enable when it is. Built-in rules are also fully editable - tweak, duplicate, or delete them, and *Restore Default Rules* in Advanced brings them back.

Discord ignores plain web links handed to it, so Yojam converts `discord.com` channel, message, and invite links (and `discord.gg` invites) to `discord://` deep links at launch time. The URL tester shows the converted link.

Add your own rules matching on all URLs, domain (exact), domain suffix, URL prefix, URL substring, or regex. A rule can also filter by source app. Add several apps to the same rule to accept links from any of them; the URL condition still applies.

To send links from several work apps to one browser profile, create a rule in **Link Handling**, select **All URLs**, and add each app under **Source Apps**. Choose the target browser and its **Profile**, then save. You only need one rule, and iCloud sync keeps the source list together. Update each Mac to 1.3.0 or later before you use multi-app rules there.

### Per-rule overrides

Beyond picking the target app or browser, each rule can pin:

- **Profile** - e.g. route `github.com` to Chrome specifically in the *Work* profile, while your other Chrome rules use *Personal*.
- **Private / incognito window** - tri-state (inherit / force on / force off).
- **Browser container** - route Firefox or Orion into a named container. Needs the Yojam WebExtension enabled in the selected browser.
- **Target display** - send the browser window to a particular monitor after it opens (requires Accessibility permission).
- **Custom launch arguments** - pass whatever CLI flags the target needs, with `$URL` as the placeholder.
- **Machine scope** - keep an iCloud-synced rule active only on the Mac where it was created.
- **New instance** - open a separate app instance for custom Chromium `--user-data-dir` setups.

These overrides only apply to the specific rule, so a rule-level private-window toggle won't flip the browser's own default.

### Source-app sentinels for rules

For ingress paths that don't have a real originating app, Yojam uses synthetic bundle identifiers. You can target these in rules to handle links differently depending on how they arrived:

| Sentinel | Ingress path |
|---|---|
| `com.yojam.source.handoff` | Handoff from another Apple device |
| `com.yojam.source.authentication-session` | App sign-in session |
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

Download `yojam-chrome.zip` from the [latest GitHub release](https://github.com/fluffypony/yojam/releases/latest), unzip it, then load the extracted folder as an unpacked extension. Until a stable Chrome Web Store ID is published, the unpacked build uses the `yojam://` fallback and Chrome may ask once before handing the link to Yojam. The no-prompt native-messaging path will be enabled for the store build.

### Firefox

Use Firefox 140 or later. Download `yojam-firefox.xpi` from the [latest GitHub release](https://github.com/fluffypony/yojam/releases/latest), open it in Firefox, and confirm the installation. From Yojam 1.3.0, this download has a Mozilla signature and works in normal Firefox. It is distributed directly through GitHub, without an AMO store listing.

Firefox asks for permission to transfer browsing activity because the extension passes links to Yojam on your Mac. It does not upload those links to a server. To route into a container, create the container in Firefox and enter its name in the rule's **Container** field. The name must match an existing container.

Install a newer XPI from GitHub when you update the extension. Sparkle updates the Mac app; it does not replace the Firefox extension.

### Orion 1.1+

Container routing needs Orion 1.1 or newer and the Firefox build of the Yojam WebExtension. Download `yojam-firefox.xpi` from the [latest GitHub release](https://github.com/fluffypony/yojam/releases/latest). In **Orion > Settings > Advanced**, allow third-party Firefox extensions. Then open **Tools > Extensions > Manage Extensions**, choose **Add Extension**, and install the XPI. See [Orion's WebExtension guide](https://help.kagi.com/orion/browser-extensions/macos-extensions.html) for Orion's current installation and compatibility details.

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

Not limited to browsers. Click **+ Add** in the Browsers tab and pick any `.app` or executable. For apps that don't natively handle URLs, use `$URL` where the link belongs. Without it, Yojam appends the URL after your custom arguments:

```
$URL
--url $URL
--browse $URL
```

Yojam passes these arguments directly - no shell involved.
For Chromium-based browsers, set **Data Dir** when an entry should use a custom `--user-data-dir`; the profile menu reloads from that directory and Yojam opens it as a new app instance. `$HOME` and leading `~/` are expanded without invoking a shell.

## Settings

Six tabs in preferences (menu bar icon > Preferences, or Cmd+,):

- **General** - Activation mode, picker layout and direction, launch at login, clipboard monitoring, iCloud sync, Quick Start
- **Browsers** - Reorder, enable/disable, profiles, private mode, per-browser tracker stripping, custom icons, custom launch args
- **Link Handling** - Routing rules, rewrite rules, global tracker stripping, URL tester. Each rule supports the per-rule overrides listed above.
- **Integrations** - Health dashboard for default browser, .webloc handler, yojam:// scheme, Handoff, Share Extension, Safari extension, native messaging hosts, App Group access. One-click repair buttons for each.
- **Advanced** - Debug logging, tracker parameter list, smart routing data, import from Bumpr/Choosy/Finicky, flat-file config panel, import/export settings, uninstall, reset
- **About** - Version info, license, links

On first launch Yojam shows a Quick Start card above the tabs. It guides you through default-browser registration. If Bumpr, Choosy, or Finicky is installed, it also offers to import compatible routes and rewrites.

The URL tester on the Link Handling tab lets you paste a URL and see exactly what Yojam would do - which rewrites fire, whether trackers get stripped, which rule matches, and where it ends up.

Settings can be exported as JSON and imported on another machine.

## Permissions

- **App Group** `group.org.yojam.shared` — shared storage between the main app and its extensions.
- **iCloud Key-Value Store** — for settings sync (off by default).
- **Apple Events** — for AppleScript-based private windows in Safari and Orion.
- **Accessibility** — only required if you use per-rule display targeting to move browser windows after they open. Granted in System Settings > Privacy & Security > Accessibility.

The first time certain features are used, macOS will show:
- A protocol-handler confirmation for `yojam://` (from browser extension fallback path).
- A prompt to enable the Share Extension (System Settings > Extensions > Sharing).
- A prompt to enable the Safari Web Extension (Safari > Settings > Extensions).

## Privacy

Everything happens locally on your Mac. Yojam doesn't phone home, track your clicks, or send your data anywhere. The Share Extension and browser extensions only hand a URL to the local Yojam process. The native messaging host only forwards URLs you explicitly trigger — it never reads page contents. Nothing hits the network.

The only network activity is iCloud sync (uses your own Apple ID, off by default) and checking for updates via yoj.am (can be disabled in Preferences).

## Troubleshooting

- **Handoff link doesn't appear** — Confirm Yojam is your default browser, and that Handoff is on in System Settings > General > AirDrop & Handoff.
- **Services menu item missing or does nothing** — Open Preferences > Integrations and click *Repair* next to Services menu. macOS keeps its own list of service providers and can keep pointing at an old copy of Yojam after an update or an OS upgrade. If the entry still does not appear, check System Settings > Keyboard > Keyboard Shortcuts > Services and make sure *Open in Yojam* is ticked. Releases before 1.2.4 declared the service in a way macOS treats as legacy, which left it switched off by default.
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
