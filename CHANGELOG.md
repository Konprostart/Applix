# Changelog

All notable changes to Applix are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet.

## [0.1.9] - 2026-10-19

### Fixed
- **Building an app no longer deletes the APKs of your other apps.** The finished APK was kept
  in the scratch work directory, which was wiped after every build. Built APKs now live in a
  stable `files/apps/` folder and the work directory is a pure scratch area.
- **Deleting an app now also deletes its APK** (about 40 MB each) from the device, both from My
  Apps and from Settings → Clear All Apps.
- The WebView of a generated app is paused while the app is in the background - animations and
  rendering stop burning CPU and battery (JavaScript timers keep running, so background work is
  not affected).
- A WebView renderer crash (usually out of memory) no longer takes the app down: the app closes
  cleanly with a message instead of "keeps stopping".
- The AI conversation is bounded to the newest messages plus the first one, so a long chat can no
  longer grow the memory without limit (every message carries the whole app code).
- Only the newest update download is kept on the device - the old 40 MB APKs are removed.

## [0.1.8] - 2026-10-19

### Fixed
- **No more "update available" for the version that is already installed.** The notice was kept
  in the app's storage and shown again after every restart, even after the update had been
  installed. The stored notice is now checked against the running version and removed as soon as
  it is obsolete.
- Version parsing strips the build suffix, so "0.1.7+8" is compared as 0.1.7 and not as 0.1.78.

## [0.1.7] - 2026-10-19

### Fixed
- **API key storage is now visible.** The key is still written to the encrypted store, but the
  setup screen now says "API key saved" after every save, and it warns you when the encrypted
  store is not available on the device instead of silently dropping the key. The key never lands
  in SharedPreferences.
- **The model list refreshes correctly.** Tapping refresh now saves the key and the base URL
  first, so the request is made with the key you just typed. When the server does not return a
  model list (or cannot be reached), the usual local models are offered as a fallback and you
  can still type any model ID.
- **"Create Prompt for AI" now works and keeps your work.** The manual prompt is saved on the
  device together with your description, so it survives leaving the screen or restarting the
  app, and it is restored the next time you open the Create screen. The button shows a
  "Creating prompt..." state while it works and confirms with a message when the prompt is
  ready.

## [0.1.6] - 2026-10-19

### Fixed
- **The app could crash while an in-app update was running.** The install was driven by the
  Activity's coroutine scope, which Android cancels as soon as the Activity is destroyed - and
  the Activity IS destroyed while the system replaces the app with the new version. The
  cancelled continuation was then resumed by the install status broadcast, and the resulting
  uncaught `IllegalStateException` inside the broadcast receiver killed the app right when the
  system install dialog was supposed to appear. The install now:
  - runs in a process-lifetime scope and uses the application context for the pending intent,
    the receiver and the install dialog, so it survives the Activity being destroyed,
  - resumes the continuation at most once and only while it is still active,
  - catches every failure inside the status receiver - an exception in a broadcast receiver
    always takes the whole app down,
  - reports a clean error if the system install dialog cannot be shown,
  - catches failures of the install session commit and of the receiver registration.
- The `FLAG_MUTABLE` flag on the install callback is now documented as mandatory: the package
  installer fills the status into that pending intent, and an immutable one would never report
  the result.

## [0.1.5] - 2026-10-19

### Fixed
- **In-app update could fail with "package is invalid"** - the update APK was downloaded into
  the cache directory (which Android may purge at any moment) and the install session was
  committed without checking that every byte had reached it. The update now:
  - downloads into the app's private files directory and is never deleted before the install,
  - verifies the number of received bytes against the expected size and refuses a truncated
    download,
  - re-verifies the SHA-256 of the very file that is about to be installed (natively, right
    before the install) and aborts on a mismatch,
  - counts the bytes written into the package installer session and aborts instead of
    committing an incomplete package,
  - installs on the IO dispatcher - copying ~40 MB into the install session on the main
    thread blocked the UI.
- The update install has its own channel instead of reusing the WiFi Direct channel, and it
  checks the "install unknown apps" permission up front.
- When an install fails, the app explains why and offers a way out: opening the app settings
  (for the missing permission) or the release page (for a manual install). The downloaded file
  is kept so the install can be retried.
- Building and installing a generated app no longer copies the APK into the install session on
  the main thread either.

## [0.1.4] - 2026-10-19

### Added
- **Applix UI Kit** - a complete design system (tokens, typography, spacing, elevation, motion
  and ready-made components for app bars, cards, list rows, buttons, FABs, inputs, chips,
  switches, empty states, skeletons, toasts, bottom sheets and stats) that is injected into every
  generated app as the first stylesheet. Even an average AI result now looks like a native app.
- **UI Kit section in the spec** - the AI is told to build every screen from the `.ax-*`
  components instead of inventing its own CSS.
- **New `ui` bridge module** - `iappyx.ui.*` gives generated apps native chrome:
  status/navigation bar colors, edge-to-edge and immersive mode, screen insets, orientation
  lock, native toasts, native alert/confirm dialogs, haptic feedback, the Android share sheet,
  app settings, keep-screen-on and screen info.
- **8 starter apps** - polished HTML starting points (Todo, Notes, Calculator, Counter,
  Stopwatch, Compass, Device Info, Alarm) that a beginner can build and customise in one tap.
- **Design contract** - every generation request now carries a concrete design contract
  (style, components, spacing, type scale, required states).
- **Visual QA with automatic polish** - after generation, the app is audited for the things
  that make a result look like a web page (missing UI Kit classes, small touch targets, no
  theme color, wrong font stack, content under the status bar, no empty/loading state) and one
  automatic AI pass fixes them.
- **Automatic app icons** - a fresh app now gets a monogram on a generated gradient instead of a
  flat colour.

### Changed
- **Native app shell** - the overscroll glow and pinch-zoom are gone, apps open with a native
  splash screen showing their own icon, and the system bars follow the app theme instead of
  always being dark.
- The starter template in the spec now uses the UI Kit and the correct viewport
  (`viewport-fit=cover`).

## [0.1.3] - 2026-10-19

### Added
- **In-app updates** - the app checks GitHub Releases for a newer version (silently once a day,
  or on demand via Settings → About → Check for updates) and shows a banner on My Apps when one
  is available. The update can be downloaded and installed straight from the app.
- Update downloads are verified against the SHA-256 checksum published with every release, and
  every release now ships a `.sha256` file next to each APK.
- Release checks use ETags and are throttled to once a day, so they never burn through the
  GitHub API rate limit.

### Notes
- Android always asks for confirmation before installing, and an update keeps your generated
  apps and settings because every release is signed with the same key.

## [0.1.2] - 2026-10-19

### Added
- **[Applix Showcase](https://github.com/Konprostart/Applix-showcase)** - a public repository of
  community apps that can be browsed and built from inside the app (Create → Showcase). It
  launches with four example apps: Todo List, Compass, Alarm Test and Bundle Explorer.
- Apps can be submitted straight from the app: My Apps → menu → Submit to Showcase opens a
  pull request against the showcase repository, and CI regenerates the app index on merge.
- Showcase repository tooling: `tools/build_index.py` builds and validates the index, and a
  GitHub Actions workflow keeps it in sync.

## [0.1.1] - 2026-10-19

### Changed
- **Applix launcher icon** — the launcher icon, the adaptive icon and the in-app logo now use the
  Applix mark everywhere. All PNG variants (legacy, round, adaptive foreground) are generated from
  `docs/brand/applix-logo.svg` with `python3 tools/gen_icons.py --apply`.
- **Splash screen** — the launch window is brand dark now, so the app no longer flashes white
  before the first frame.
- Demo template count in Settings and in the docs matches the real number (59).

### Fixed
- The round launcher icon (`@mipmap/ic_launcher_round`) was only defined for Android 8.0+ - the
  PNG variants are now generated for every density, so older devices get it too.
- The built-in icon renderer used a wrong coordinate mapping and vertical instead of diagonal
  gradients, so generated icons did not match the SVG brand mark.

## [0.1.0] - 2026-10-19

First public release of Applix.

### Added
- **Applix container app** — an Android app that turns a description into a real, installed APK
  with its own launcher icon. Building, signing and installing happen entirely on-device.
- **Three creation modes** — AI-generated app, website-as-app wrapper, and manual prompt flow.
- **Native bridge API** — 35 modules (audio, camera, device, location, NFC, sensors, storage,
  bluetooth, SSH, SMB, HTTP client/server, and more) with 281 documented methods, exposed to
  generated apps as `window.iappyx` (with `window.applix` as an alias).
- **AI providers** — Anthropic, OpenRouter, OpenAI, plus any OpenAI-compatible endpoint
  (Ollama, LM Studio, vLLM, ...) with a configurable base URL and an optional API key.
- **Bridge linter** — detects bridge calls that are not documented in the spec, shows them
  before the build, and offers a one-pass AI auto-repair.
- **Preview** — runs the generated app in a sandboxed test environment with a live console,
  before anything is built.
- **Icon editor** — pick an icon, or generate one from the app name.
- **Demo apps** — 57 ready-made apps that exercise the native bridges.
- **Full and web shell templates** — the container ships both a full bridge-enabled shell and a
  lightweight web-only shell for website wrappers.
- **Release pipeline** — versioning driven by the `VERSION` file, a `CHANGELOG.md` that CI
  validates, and automatic GitHub Releases with the container and shell APKs on every `v*` tag.

### Changed
- Project renamed to Applix (`com.konprostart.applix`); `window.applix` kept as an alias for
  `window.iappyx` so existing generated apps keep working.
- Built and published from a public GitHub repository with CI checks on every push.

### Security
- The container APK is signed with a dedicated release key in CI; the key never leaves the
  GitHub Actions secrets and is never committed to the repository.

[Unreleased]: https://github.com/Konprostart/Applix/compare/v0.1.9...HEAD
[0.1.9]: https://github.com/Konprostart/Applix/releases/tag/v0.1.9
[0.1.8]: https://github.com/Konprostart/Applix/releases/tag/v0.1.8
[0.1.7]: https://github.com/Konprostart/Applix/releases/tag/v0.1.7
[0.1.6]: https://github.com/Konprostart/Applix/releases/tag/v0.1.6
[0.1.5]: https://github.com/Konprostart/Applix/releases/tag/v0.1.5
[0.1.4]: https://github.com/Konprostart/Applix/releases/tag/v0.1.4
[0.1.3]: https://github.com/Konprostart/Applix/releases/tag/v0.1.3
[0.1.2]: https://github.com/Konprostart/Applix/releases/tag/v0.1.2
[0.1.1]: https://github.com/Konprostart/Applix/releases/tag/v0.1.1
[0.1.0]: https://github.com/Konprostart/Applix/releases/tag/v0.1.0
