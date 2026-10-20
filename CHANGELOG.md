# Changelog

All notable changes to Applix are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet.

## [0.2.2] - 2026-10-20

### Fixed
- **Applix can be updated over the previous version again.** The version code of the app is now
  derived from the semantic version (major * 100000000 + minor * 100000 + patch), so it always
  grows. The build number that was used before was reset with the 0.2.0 release, and Android
  refuses an update whose version code is lower than the installed one ("App not installed") -
  that is why 0.2.0 and 0.2.1 could not be installed over 0.1.19.
- CI now fails when the version of a release is lower than an already published one, so a
  downgrade can never be published again.
- The VERSION file holds a plain semantic version (0.2.2) - there is no separate build number
  any more that could drift.

## [0.2.1] - 2026-10-20

### Fixed
- **The signing key now survives a reinstall of Applix.** The key stays in the AndroidKeyStore
  (the proven mechanism) and a single backup record of it is kept in the shared Downloads
  folder. That record is not removed when Applix is uninstalled, so on the next start Applix
  restores the very same key automatically - and every app that was signed with it can be
  updated again instead of failing with "signed with a different key".
- The backup is one file with a magic header and a checksum (applix_master_key.aplixkey) - it
  is never appended to and never duplicated. A damaged record is rejected instead of restored.
- Settings → Signing Key shows whether the backup exists and can create or restore it manually.
- The build log states whether the key was taken from the AndroidKeyStore or restored from the
  backup.

## [0.2.0] - 2026-10-20

### Changed
- **The signing goes back to the original iappyxOS mechanism.** The master key lives in the
  AndroidKeyStore of Applix, it is created once and it is never replaced while it exists - the
  same mechanism the project used from the start. All the extra layers (a keystore file in the
  app storage, a copy in the Downloads folder, an import/export flow) are gone again.
- The build log shows the fingerprint of the key that signed the app and the path of the file
  that goes to the system, so it is visible that every build uses the same key.
- The signature of the finished APK is read out of the APK with the platform parser and
  compared with the master key before the install. A mismatch stops the install with a clear
  message instead of letting Android report a broken package.
- The number of bytes that reach the install session is verified before the session is
  committed.
- The package name of a project is logged and never changed by an edit, so an update always
  installs over the existing app.

### Fixed
- The "update required" dialog explains where the signing key lives and that uninstalling
  Applix removes it, and it shows the fingerprint of both the installed app and the current key.
- Settings → Signing Key explains the same instead of offering a key export that cannot work
  with a hardware backed key.

## [0.1.19] - 2026-10-20

### Fixed
- **The signing key now survives the deletion of Applix.** The key was only kept in the private
  storage of the app, so deleting Applix destroyed it and the next build created a new one - the
  apps that were installed before could never be updated again. The key is now mirrored into the
  shared Downloads folder and restored from there automatically when it is missing.
- **The built APK is verified before it is installed.** The signature is read out of the finished
  APK with the platform parser and compared with the master key. A mismatch stops the install
  with a clear message instead of letting Android report it as a broken package.
- **The install logs exactly what goes to the system** (path, size, staged bytes), so a mismatch
  can be traced to the file.
- The package name of a project is never changed by an edit (it is logged now), so an update
  always installs over the existing app.
- Removing an app waits longer for the system to finish the uninstall.

## [0.1.18] - 2026-10-20

### Fixed
- **The master key is now loaded from disk on every build, without exception.**
  The build log now shows "Loaded existing master key from /path/applix_master.p12
  with fingerprint XXXX" when the key was read from disk, or a clear warning when
  the key had to be created. A mismatch can never happen silently.
- **The key is never regenerated while a key file exists.** If the file is present
  but damaged, the build stops with a message instead of signing with a new key.

## [0.1.17] - 2026-10-20

### Fixed
- **The signing key is back to one simple file.** The key is stored as a single keystore file
  again (files/keys/applix_master.p12) instead of several custom files. If the file exists it is
  always used - it is never replaced silently. If it cannot be read the build stops with a clear
  message instead of signing with a new key. The key files of the previous version are migrated
  automatically, so no app loses its signature.
- **"Export key" works again.** The exported file is written to the share folder of the app, which
  is the only place the file provider can share from - that is why the export failed before.
- **Generated apps look like they did before.** The design system no longer overwrites the fonts,
  the line height or the image size of an app, and it now also answers to the variable names the
  system prompt teaches (--primary, --surface, --text, ...), so an app that mixes both systems
  keeps its colors instead of losing them.
- The system theme colors of the device are published under both variable names, so an app that
  follows the "dynamic" style gets the same colors in the preview and in the installed app.

## [0.1.16] - 2026-10-19

### Fixed
- **The signing key can no longer change behind your back.** The master key is stored as plain
  files (PKCS#8 key + X.509 certificate + a fingerprint file) instead of a PKCS#12 keystore.
  Keystore providers differ between Android versions and vendors - a file written by one could
  not be read by the other, and a *new* key was then created silently, which is exactly what
  made every build produce a different signature.
- **A stored key is now used without exception.** If the key files exist they are loaded; if they
  are damaged, the backup copy is used; if that fails too, the build stops with a clear message
  instead of silently signing with a new key.
- Every build now logs which key signed the app ("Signing with master key ...") and the signature
  conflict dialog shows both fingerprints (the installed app and the Applix key), so a mismatch
  is visible instead of mysterious.
- The key can be exported and imported again (Settings → Signing Key). The export is a single
  file with a checksum; the import rejects a file that does not match.

### Changed
- The package installer now knows the package name and the file size of the app it installs, which
  makes the installation smoother and the errors clearer.

## [0.1.15] - 2026-10-19

### Fixed
- **Generated apps keep their signature.** Every app that Applix builds is now signed with one
  stable master key that lives in the private storage of the app. The key is created exactly once
  and is never regenerated, so an update of a generated app always carries the same signature and
  Android accepts it.
  Before, the key lived in the AndroidKeyStore of Applix itself. That key is invalidated when
  Applix is reinstalled with a different signature, when the app data is cleared or after a
  device restore - and a new key was then generated silently. Every app built afterwards was
  signed with a different key than before, which is exactly the "signed with a different key"
  error that blocked updates of the apps users had already installed.
- **The master key can be backed up.** Settings → Signing Key → Export key / Import key. Exporting
  lets the user keep the key; importing it on a new phone (or after a restore) makes the apps
  built with it updatable again.
- The key is checked against the installed app before an update, and the "uninstall & replace"
  dialog now explains that the app was signed with an older Applix key and that this is the last
  time.

## [0.1.14] - 2026-10-19

### Fixed
- **The app no longer sends you back to the API key screen in a loop.** The provider setup
  screen always saves the key and hands the configured provider back, no matter whether you
  leave it with the back button, the system gesture or the new Save button. Before, the system
  back gesture popped without a result and the saved key was read before it had been written.
- The "Generate" button opens the provider setup instead of doing nothing when no usable
  provider is configured, and the AI / Manual switch always shows a clear message about what
  is missing.

### Changed
- **The AI / Manual switch now has an unmistakable state**: the active option uses the primary
  color, a bright border, a check mark and a soft glow, the inactive one is dimmed. When no
  provider is set up yet, the AI option shows an amber warning instead of a silent failure.
- The provider setup screen has a "Save" button next to the back button.

## [0.1.13] - 2026-10-19

### Fixed
- **In-app update can no longer crash the app.** The whole install path is now guarded
  (`Throwable`, not just `Exception`), so a problem in the package installer, in the pending
  intent or in the system dialog is reported as an error instead of taking the app down.
- **The update is checked before it is installed.** The downloaded APK must be signed with the
  same key as the installed app and must have a higher version code - otherwise the install is
  stopped with a clear message ("signed with a different key" / "not newer than the installed
  app") instead of a cryptic system error.
- **A second install path.** If the package installer session is rejected, the APK is handed to
  the system installer through a FileProvider `content://` URI (`ACTION_VIEW`), which is the
  classic and very reliable way to install an APK.
- The FileProvider now covers the folders that are actually used: the built APKs and project
  folders (`files/apps/`), the downloaded updates (`files/updates/`) and the build work
  directory (`files/applix_work/`, the old `iappyxos_work/` entry was stale).
- Hashing the downloaded APK happens in a background isolate, the download progress is throttled
  to 10 updates per second and the install call has a timeout - the app never freezes or waits
  forever.

## [0.1.12] - 2026-10-19

### Added
- **Splash and system bar settings.** A new "Splash & Bars" screen lets you choose the launch
  screen background (a solid color, the gradient of the app icon or the icon itself), whether
  the app icon is shown in the splash, and the colors of the status and navigation bars. The
  settings are stored with the app, written into the project manifest (`app-config.json`) and
  handed to the shell through `app-theme.json`.
- A live preview of the splash screen in the settings.

### Fixed
- **The app icon now shows on Android 8 and newer as well.** The adaptive icon foreground was
  never replaced in the built APK, so the launcher used the static icon of the shell template.
  The icon builder now also renders the adaptive foregrounds (108dp, 5 densities) with the symbol
  inside the 66dp safe zone.

### Compatibility
- Apps that were created before these options existed keep their look: every setting is
  optional and falls back to the colors of the app icon.

## [0.1.11] - 2026-10-19

### Added
- **Built-in code editor.** The files of an app project (index.html, style.css, script.js, ...)
  can now be edited directly in Applix. It is a light, dependency free editor: monospace text
  field, line numbers that follow the scroll, a status bar with the cursor position, a tab bar
  for switching between the project files and a mobile toolbar with the usual insert keys
  (tab, braces, brackets, angle brackets, quotes).
- The editor writes through the project storage, so a saved file is immediately part of the
  next build and of the preview.
- Two entry points: Advanced Settings -> Edit Code while creating or editing an app, and
  "Edit Code" in the app menu in My Apps. The simple creation flow is unchanged.

## [0.1.10] - 2026-10-19

### Added
- **Multi-file projects.** An app is no longer forced into a single HTML file. The project is
  stored on the device as `files/apps/<packageName>/` with `index.html` plus any extra files
  (`style.css`, `script.js`, `app-config.json`, ...), and those files are shipped into the APK
  next to the entry page, so the app can load them with a relative path
  (`<link rel="stylesheet" href="style.css">`, `<script src="script.js">`).
- A "Project files" section in the Create screen: add or remove project files, see their size.
- The preview inlines the project files, so it shows exactly what the installed app shows.
- A small project manifest (`app-config.json`) with the app name, package name, version and the
  list of files.

### Changed
- The project folder moves to its final place (`files/apps/<packageName>/`) as soon as the
  package name is known, and it is removed together with the app when the app is deleted.

### Compatibility
- Apps that only have a single `index.html` keep working exactly as before: the project folder
  is optional, the app record still carries the whole app code, and the build writes the entry
  page when there is no project.

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

[Unreleased]: https://github.com/Konprostart/Applix/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/Konprostart/Applix/releases/tag/v0.2.2
[0.2.1]: https://github.com/Konprostart/Applix/releases/tag/v0.2.1
[0.2.0]: https://github.com/Konprostart/Applix/releases/tag/v0.2.0
[0.1.19]: https://github.com/Konprostart/Applix/releases/tag/v0.1.19
[0.1.18]: https://github.com/Konprostart/Applix/releases/tag/v0.1.18
[0.1.17]: https://github.com/Konprostart/Applix/releases/tag/v0.1.17
[0.1.16]: https://github.com/Konprostart/Applix/releases/tag/v0.1.16
[0.1.15]: https://github.com/Konprostart/Applix/releases/tag/v0.1.15
[0.1.14]: https://github.com/Konprostart/Applix/releases/tag/v0.1.14
[0.1.13]: https://github.com/Konprostart/Applix/releases/tag/v0.1.13
[0.1.12]: https://github.com/Konprostart/Applix/releases/tag/v0.1.12
[0.1.11]: https://github.com/Konprostart/Applix/releases/tag/v0.1.11
[0.1.10]: https://github.com/Konprostart/Applix/releases/tag/v0.1.10
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
