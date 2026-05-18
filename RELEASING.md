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

It reads the response's `tag_name`, strips a leading `v` if present, and compares with the local `CFBundleShortVersionString`.

### Silent updates (v1.3.0+)

If the remote tag is newer **and** the release carries a `Dramatic-Events.zip`
asset, the app updates itself with no user action:

1. `Updater` downloads the `.zip`, unpacks it with `ditto`, and strips the
   `com.apple.quarantine` xattr — so the swapped-in bundle launches without a
   Gatekeeper prompt even though it's only ad-hoc signed.
2. The unpacked bundle is staged in `~/Library/Application Support/Dramatic Events/Update/`.
3. On the next quit, a detached helper waits for the app to exit, then swaps
   the bundle in place. No DMG, no drag, no relaunch — the new version is just
   there next time the app opens.

The Settings panel shows "Update v1.3.0 ready — installs automatically the
next time you quit". If the release has **no** `.zip` asset, or staging fails,
it falls back to the old manual flow: a `[ Download ]` button that opens the
DMG so the user drags the app into `/Applications` themselves.

> **This means every release from v1.3.0 onward MUST include the `.zip`
> asset** — `package-dmg.sh` builds it; just remember to upload it (step 4).
> The first version a user runs that has the updater (v1.3.0) still has to be
> installed manually once; updates after that are silent.

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
4. Runs `ditto -c -k --keepParent` to produce `build/Dramatic-Events.zip` — the asset the in-app updater downloads.

### 3. Commit and tag

```bash
git commit -am "Release 1.0.1"
git tag v1.0.1
git push --follow-tags
```

The tag must start with `v` and exactly match the version string. The app's update checker tolerates the `v` prefix (`v1.0.1` is treated as `1.0.1`).

### 4. Create the GitHub release

Upload **both** the DMG and the ZIP — the ZIP is what the silent updater pulls:

```bash
gh release create v1.0.1 'build/Dramatic-Events.dmg' 'build/Dramatic-Events.zip' \
    --title "Dramatic Events v1.0.1" \
    --notes "$(cat <<'EOF'
- Fixed: countdown jitter on Retina displays
- Added: support for AIFF audio files
- Changed: settings window now remembers position
EOF
)"
```

That's it. Every running copy of the app (v1.3.0+) will detect the release
within 6 hours — or immediately when the user opens **Settings…** — download
the ZIP, and silently install it on the next quit.

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
DramaticEvents/Updater.swift        ← silent download/stage/install-on-quit
build.sh                            ← compile + sign
package-dmg.sh                      ← package (DMG + ZIP)
```

If you ever rename the GitHub repo, also update the constants at the top of `UpdateChecker.swift`:

```swift
static let owner = "ulvosama"
static let repo  = "dramatic-events"
```
