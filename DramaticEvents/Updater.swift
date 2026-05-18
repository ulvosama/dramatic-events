import AppKit

/// Silent in-place updater. When a newer release is detected, its zipped
/// `.app` is downloaded, unpacked, de-quarantined, and staged. The bundle
/// swap happens at quit time via a detached helper script — so the user
/// never sees a DMG, a Gatekeeper prompt, or a surprise relaunch. The new
/// version is simply there the next time they open the app.
///
/// Why this avoids the Gatekeeper prompt: the first-launch "unidentified
/// developer" check is triggered by the `com.apple.quarantine` xattr, which
/// browsers attach to downloads. Because *this app* installs the update, it
/// strips that xattr from the staged bundle before swapping it in — so the
/// ad-hoc-signed app launches silently. (The very first install from the
/// DMG still prompts once; only notarization removes that.)
enum Updater {

    /// Where the unpacked, ready-to-install bundle waits.
    private static var stagingDir: URL {
        Settings.supportDir.appendingPathComponent("Update", isDirectory: true)
    }
    private static var stagedAppURL: URL {
        stagingDir.appendingPathComponent("Dramatic Events.app")
    }

    // MARK: – Staging

    /// Downloads `zipURL`, unpacks it, strips the quarantine flag, validates
    /// the bundle, and records `version` as pending. Idempotent: if `version`
    /// is already staged this returns immediately. `completion` runs on the
    /// main queue with whether a usable update is now staged.
    static func stageUpdate(zipURL: URL, version: String,
                            completion: @escaping (Bool) -> Void) {
        if Settings.shared.pendingUpdateVersion == version, isStagedBundleValid() {
            DispatchQueue.main.async { completion(true) }
            return
        }
        URLSession.shared.downloadTask(with: zipURL) { tmpURL, _, error in
            guard let tmpURL = tmpURL, error == nil else {
                NSLog("Updater: download failed: \(error?.localizedDescription ?? "?")")
                DispatchQueue.main.async { completion(false) }
                return
            }
            // tmpURL is valid only until this closure returns — unpack synchronously.
            let ok = unpackAndStage(zipFile: tmpURL, version: version)
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    private static func unpackAndStage(zipFile: URL, version: String) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: stagingDir)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        } catch {
            NSLog("Updater: cannot create staging dir: \(error)")
            return false
        }

        // `ditto` correctly expands macOS zips and preserves the code signature.
        guard run("/usr/bin/ditto", ["-x", "-k", zipFile.path, stagingDir.path]) else {
            NSLog("Updater: ditto extraction failed")
            return false
        }

        guard let appURL = locateApp(in: stagingDir) else {
            NSLog("Updater: no .app found in update zip")
            return false
        }
        if appURL != stagedAppURL {
            try? fm.removeItem(at: stagedAppURL)
            do { try fm.moveItem(at: appURL, to: stagedAppURL) }
            catch { NSLog("Updater: cannot normalize staged path: \(error)"); return false }
        }

        // Strip quarantine so the swapped-in bundle launches without a prompt.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedAppURL.path])

        guard isStagedBundleValid() else {
            NSLog("Updater: staged bundle failed validation")
            return false
        }

        Settings.shared.pendingUpdateVersion = version
        NSLog("Updater: staged update v\(version) — will install on quit")
        return true
    }

    // MARK: – Install on quit

    /// True if a usable update is staged and ready to install.
    static func hasPendingUpdate() -> Bool {
        Settings.shared.pendingUpdateVersion != nil && isStagedBundleValid()
    }

    /// Call from `applicationWillTerminate`. If an update is staged and the
    /// running bundle sits in a writable location, spawns a detached helper
    /// that waits for this process to exit, then swaps the bundle in place.
    /// No relaunch — the user quit; they get the new version on next open.
    static func installPendingUpdateOnQuit() {
        guard hasPendingUpdate() else { return }

        let dest = Bundle.main.bundleURL
        let parent = dest.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            NSLog("Updater: \(parent.path) not writable — skipping in-place install")
            return
        }

        // Move-aside-then-swap so a failed swap can be rolled back.
        let script = """
        #!/bin/sh
        PID="$1"; SRC="$2"; DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        sleep 0.3
        BACKUP="${DEST}.old"
        rm -rf "$BACKUP"
        if mv "$DEST" "$BACKUP"; then
          if mv "$SRC" "$DEST"; then
            rm -rf "$BACKUP"
          else
            mv "$BACKUP" "$DEST"
          fi
        fi
        """
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("de-update-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Updater: cannot write install helper: \(error)")
            return
        }

        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [scriptURL.path,
                          String(ProcessInfo.processInfo.processIdentifier),
                          stagedAppURL.path,
                          dest.path]
        do {
            try task.run()   // detached — outlives us, reparented to launchd
            NSLog("Updater: install helper spawned")
        } catch {
            NSLog("Updater: cannot spawn install helper: \(error)")
        }
    }

    /// Clears stale staging state once the running app already *is* the
    /// pending version (i.e. the swap succeeded on a previous quit).
    static func clearStagingIfInstalled() {
        guard let pending = Settings.shared.pendingUpdateVersion else { return }
        if !UpdateChecker.isNewer(pending, than: UpdateChecker.currentVersion) {
            try? FileManager.default.removeItem(at: stagingDir)
            Settings.shared.pendingUpdateVersion = nil
        }
    }

    // MARK: – Helpers

    private static func isStagedBundleValid() -> Bool {
        let exec = stagedAppURL.appendingPathComponent("Contents/MacOS/DramaticEvents")
        return FileManager.default.isExecutableFile(atPath: exec.path)
    }

    /// Finds the `.app` in the extracted zip — at the top level, or one
    /// folder down if the archive nested it.
    private static func locateApp(in dir: URL) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        if let direct = items.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        for sub in items {
            let isDir = (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            if let nested = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) {
                return nested
            }
        }
        return nil
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) -> Bool {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
