# Changelog

All notable changes to Applix are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet.

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

[Unreleased]: https://github.com/Konprostart/Applix/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/Konprostart/Applix/releases/tag/v0.1.2
[0.1.1]: https://github.com/Konprostart/Applix/releases/tag/v0.1.1
[0.1.0]: https://github.com/Konprostart/Applix/releases/tag/v0.1.0
