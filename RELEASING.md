# Releasing Dramatic Events

How updates work and how to ship a new version.

## How macOS app versioning works

`DramaticEvents/Info.plist` has two version keys:

| Key | Meaning |
|---|---|
| `CFBundleShortVersionString` | The **public version** users see (e.g. `1.0.1`). |
| `CFBundleVersion` | The **build number**. macOS uses this to compare versions when deciding "is this newer than what's installed?". |

For this project, **keep both fields identical** (e.g. both `1.0.1`). They only need to differ for App Store apps with multiple TestFlight builds per release.

### SemVer at a glance

`MAJOR.MINOR.PATCH` (e.g. `1.0.1`):

- **PATCH** (`1.0.0` → `1.0.1`): bug fix, copy tweak, internal refactor.
- **MINOR** (`1.0.x` → `1.1.0`): new feature that doesn't break anything.
- **MAJOR** (`1.x.x` → `2.0.0`): breaking change — settings format incompatible with the old version, dropped feature, etc.

When in doubt, bump PATCH.

## How updates reach users

The app has an `UpdateChecker` that hits the GitHub Releases API whenever the user opens **Settings…**:

```
GET https://api.github.com/repos/ulvosama/dramatic-events/releases/latest
```

It reads the response's `tag_name`, strips a leading `v` if present, and compares with the local `CFBundleShortVersionString`. If the remote tag is newer, the Settings panel shows:

> **Update available — v1.0.1**
> [ Download v1.0.1 ]

Clicking Download opens the DMG asset URL in Safari. The user drags the new app over the old one in `/Applications`.

The user-facing direct-download link is **stable across versions**:

```
https://github.com/ulvosama/dramatic-events/releases/latest/download/Dramatic-Events.dmg
```

GitHub redirects this to the latest release's `Dramatic-Events.dmg` asset, so the README badge keeps working forever as long as you upload a DMG with that exact filename to every release.

## The release loop

Every time you want to ship a new version:

### 1. Bump versions

Edit `DramaticEvents/Info.plist` — change both `CFBundleShortVersionString` and `CFBundleVersion`. They should match.

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.1</string>     <!-- was 1.0.0 -->
<key>CFBundleVersion</key>
<string>1.0.1</string>     <!-- was 1.0.0 -->
```

### 2. Build the DMG

```bash
./package-dmg.sh
```

This:
1. Calls `./build.sh` which compiles all Swift sources into `build/Dramatic Events.app` and ad-hoc signs it.
2. Stages the .app + an `Applications` symlink into a temp folder.
3. Runs `hdiutil create … -format UDZO` to produce `build/Dramatic-Events.dmg`.

### 3. Commit and tag

```bash
git commit -am "Release 1.0.1"
git tag v1.0.1
git push --follow-tags
```

The tag must start with `v` and exactly match the version string. The app's update checker tolerates the `v` prefix (`v1.0.1` is treated as `1.0.1`).

### 4. Create the GitHub release

```bash
gh release create v1.0.1 'build/Dramatic-Events.dmg' \
    --title "Dramatic Events v1.0.1" \
    --notes "$(cat <<'EOF'
- Fixed: countdown jitter on Retina displays
- Added: support for AIFF audio files
- Changed: settings window now remembers position
EOF
)"
```

That's it. Every running copy of the app, the next time the user opens **Settings…**, will see the new version and a Download button.

### 5. (Optional) Verify

```bash
# Confirm the asset is reachable at the stable URL
curl -L --head -o /dev/null -w "%{http_code}\n" \
    https://github.com/ulvosama/dramatic-events/releases/latest/download/Dramatic-Events.dmg
# Expect: 200
```

## When something goes wrong

### "I tagged the wrong version"

```bash
git tag -d v1.0.1
git push origin :refs/tags/v1.0.1
gh release delete v1.0.1 --yes
# Re-do steps 1–4 with the right version
```

### "The DMG won't open on a friend's Mac — 'damaged' warning"

The bundle is ad-hoc signed (no Apple Developer ID). On first open, Gatekeeper may show "can't be opened because Apple cannot check it for malicious software." Fix: right-click the app → **Open** → **Open** in the dialog. macOS only nags once per app per machine.

To remove the warning entirely you'd need to:
- Enroll in the Apple Developer Program ($99/year)
- Sign with `codesign --sign "Developer ID Application: …"`
- Submit for **notarization** via `xcrun notarytool`

Not worth it for sharing with friends.

### "Update check fails — Couldn't reach update server"

- Repo went private — flip it back to public.
- GitHub API rate limit hit (60 req/hour for unauthenticated). Unlikely unless friends mass-open Settings.
- The release must be published, not draft. Draft releases don't show up in `/releases/latest`.

## Files this all touches

```
DramaticEvents/Info.plist          ← bump version here
DramaticEvents/UpdateChecker.swift  ← repo owner/name baked in
build.sh                            ← compile + sign
package-dmg.sh                      ← package
```

If you ever rename the GitHub repo, also update the constants at the top of `UpdateChecker.swift`:

```swift
static let owner = "ulvosama"
static let repo  = "dramatic-events"
```
