# Writing

**Always invoke the humanizer skill for every piece of user-facing text.**

This includes, without exception:
- README.md sections
- Tooltips, alerts, error dialogs, onboarding copy
- Share Extension display name and any extension UI strings
- Browser extensions: `manifest.json` description fields, popup HTML copy,
  options-page labels, `_locales/en/messages.json`
- Services menu item title
- User-visible `YojamLogger` messages
- Commit messages and release notes
- App Store / Chrome Web Store / AMO descriptions

Do not ship any new copy that hasn't been passed through the humanizer skill.
The existing strings in the README and preferences UI are the tonal reference:
short sentences, plain words, second person, no marketing voice, no
"seamlessly", no "effortlessly", no "powerful", no em-dash drama.

Source code comments (`//`) are exempt.

# Architecture

- All routing logic lives in `YojamCore`. Do not duplicate rule evaluation,
  URL rewriting, or UTM stripping inside extensions, the native host, or the
  Safari handler. They all call into `YojamCore`.
- All ingress paths funnel through `AppDelegate.enqueueOrHandle(_:)`.
- Hard-cut product policy is in force. Do not write migration shims, dual
  codepaths, or fallback reads from legacy locations unless the user
  explicitly asks for one. Prefer fail-fast diagnostics and explicit recovery
  steps in the README. Any temporary migration code must carry an inline
  comment with: why it exists, why the canonical path is insufficient, exact
  deletion criteria, and the ADR/task that tracks its removal.
- Keep browser-extension source in `Extensions/` under one shared WebExtension
  tree. Per-browser divergence goes in manifest overlays and nowhere else.
- When adding macOS extensions, update `project.yml` (xcodegen) and the
  relevant entitlements and Info.plist files. Do not assume `Package.swift`
  alone can ship app extensions -- it cannot.
- Extension-safe targets (`YojamCore`, `YojamShareExtension`,
  `YojamSafariExtension`) must build with
  `APPLICATION_EXTENSION_API_ONLY = YES`.

# Tests

Every new ingress path must ship with:
1. A unit test exercising the ingress adapter.
2. Tests proving it produces the same output as the other ingress paths
   for an identical target URL.

Before committing, run `swift test` for the `YojamCore` unit layer.

# Build system

- The canonical build artifact is produced by `xcodegen generate && xcodebuild`.
- `swift build` produces only the bare Yojam executable and `YojamCore` library.
- `Package.swift` is for shared-library development and tests only.
- `.appex` bundles (Share Extension, Safari Web Extension) and the native
  messaging host binary are Xcode-only targets defined in `project.yml`.
- `Extensions/build.sh` produces `dist/yojam-chrome.zip` and
  `dist/yojam-firefox.xpi`. Signing and store submission are out of scope.
