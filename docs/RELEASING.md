# Releasing Applix

A release is a git tag (`vX.Y.Z`). Pushing the tag runs
[`.github/workflows/release.yml`](../.github/workflows/release.yml), which builds the APKs and
publishes them as a GitHub Release.

## One-time setup: signing key and secrets

The container APK is signed with a dedicated release key. The key never enters the repository —
it lives only in GitHub Actions secrets.

**1. Generate the key** (on your computer, once):

```bash
keytool -genkeypair -v \
  -keystore applix-release.jks \
  -alias applix \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass 'YOUR_PASSWORD' \
  -dname "CN=Applix, O=Konprostart, C=NL"
```

Use **one password** for the keystore and the key — modern `keytool` creates a PKCS12 keystore,
where the key password must equal the store password. If you really need two different
passwords, add `-storetype JKS -keypass 'YOUR_KEY_PASSWORD'`.

**2. Keep a backup.** This key is the app's identity: if you lose it, you can never ship an
update for an already installed Applix. Store it outside the repo (password manager, offline
drive) — not in git, not in cloud sync.

**3. Add the four GitHub secrets** (repository → Settings → Secrets and variables → Actions):

```bash
gh secret set APPLIX_KEYSTORE_BASE64   < base64.applix-release.jks
gh secret set APPLIX_KEYSTORE_PASSWORD < <(printf '%s' 'YOUR_PASSWORD')
gh secret set APPLIX_KEY_ALIAS         < <(printf '%s' 'applix')
gh secret set APPLIX_KEY_PASSWORD      < <(printf '%s' 'YOUR_PASSWORD')
```

where `base64.applix-release.jks` is the base64 encoding of the keystore file:

```bash
base64 -w0 applix-release.jks > base64.applix-release.jks
```

macOS: `base64 < applix-release.jks | tr -d '\n' > base64.applix-release.jks`

Without these secrets the release workflow fails on purpose — a release is never published with
a debug signature.

## Cutting a release

**1. Bump the version.** Edit the `VERSION` file at the repo root:

```
0.1.0+1
```

Format: `<major>.<minor>.<patch>[+<build>]`. The build number is an integer that must increase
for every release. `+1` is the first build of `0.1.0`.

**2. Sync the version everywhere:**

```bash
python3 tools/sync_version.py
```

This updates `src/container_app/pubspec.yaml`, both shell templates and
`src/container_app/lib/version.dart`. Commit the changes — CI fails if they drift.

**3. Update the changelog.** In `CHANGELOG.md`, move the entries under `## [Unreleased]` into a
new section:

```markdown
## [0.1.1] - 2026-10-20
```

`python3 tools/changelog.py --check` verifies that the current version has a section.

**4. Commit, tag and push:**

```bash
git add -A
git commit -m "release: v0.1.0"
git tag v0.1.0
git push origin main
git push origin v0.1.0
```

**5. Watch the release.** The workflow appears under Actions → `release`. It verifies the tag
against `VERSION`, checks that the tag is on `main`, validates the changelog, builds the shell
templates and the container app, signs the container APK with the release key, and publishes:

- `Applix-<version>-container.apk` — the signed Applix app
- `Applix-<version>-shell-full.apk` — full bridge shell template
- `Applix-<version>-shell-web.apk` — web-only shell template

If anything fails, delete the tag (`git push origin :refs/tags/v0.1.0`), fix the problem, and
push the tag again.

## What CI checks on every push

| Check | Script |
| --- | --- |
| Version metadata in sync | `python3 tools/sync_version.py --check` |
| Changelog documents the current version | `python3 tools/changelog.py --check` |
| Bridge index matches `SPEC.md` | `python3 tools/gen_bridge_index.py --check` |
| Container unit tests | `flutter test` in `src/container_app` |

## Local release build

```bash
./build.sh
```

Builds locally with a debug signature unless `src/container_app/key.properties` exists
(see README → Signing). The output is `bin/Applix.apk`.
