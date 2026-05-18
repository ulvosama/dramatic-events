import Foundation

/// Persistent app settings backed by `UserDefaults`. The chosen audio file
/// is copied into Application Support so it stays available even if the user
/// moves or deletes the original.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let soundPath              = "soundPath"
        static let trimStart              = "trimStart"
        static let startupDrama           = "startupDrama"
        static let volume                 = "volume"
        static let macOSNotifications     = "macOSNotifications"
        static let suppressWhenInMeeting  = "suppressWhenInMeeting"
        static let pendingUpdate          = "pendingUpdateVersion"
    }

    /// Version string of an update that [[Updater]] has downloaded and staged,
    /// waiting to be swapped in on next quit. `nil` when nothing is pending.
    var pendingUpdateVersion: String? {
        get { defaults.string(forKey: Key.pendingUpdate) }
        set { defaults.set(newValue, forKey: Key.pendingUpdate) }
    }

    /// Sound playback volume (0.0…1.0). Defaults to 1.0.
    var volume: Double {
        get {
            if defaults.object(forKey: Key.volume) == nil { return 1.0 }
            return defaults.double(forKey: Key.volume)
        }
        set { defaults.set(max(0, min(1, newValue)), forKey: Key.volume) }
    }

    /// When true, the dramatic sound is skipped if [[MeetingPresenceDetector]]
    /// thinks the user is already in another meeting (overlapping calendar
    /// event, in-call app subprocess, or Focus / DND on). The visual urgent
    /// state still fires either way. Defaults to true.
    var suppressSoundWhenInMeeting: Bool {
        get {
            if defaults.object(forKey: Key.suppressWhenInMeeting) == nil { return true }
            return defaults.bool(forKey: Key.suppressWhenInMeeting)
        }
        set { defaults.set(newValue, forKey: Key.suppressWhenInMeeting) }
    }

    /// When true, fires a macOS Notification Center alert when a meeting
    /// goes live. Useful for users in fullscreen apps where the menu bar
    /// is hidden. Defaults to true.
    var macOSNotificationsEnabled: Bool {
        get {
            if defaults.object(forKey: Key.macOSNotifications) == nil { return true }
            return defaults.bool(forKey: Key.macOSNotifications)
        }
        set { defaults.set(newValue, forKey: Key.macOSNotifications) }
    }

    /// When true, plays a 20-second dramatic sequence ("Going live in 10s…
    /// We're live!") every time the app launches and Calendar access is granted.
    /// Defaults to true so first-time users immediately experience the value.
    var startupDramaEnabled: Bool {
        get {
            // First-run default = true.
            if defaults.object(forKey: Key.startupDrama) == nil { return true }
            return defaults.bool(forKey: Key.startupDrama)
        }
        set { defaults.set(newValue, forKey: Key.startupDrama) }
    }

    /// Path to the user-chosen sound. `nil` means "use the bundled default".
    var soundURL: URL? {
        get {
            guard let s = defaults.string(forKey: Key.soundPath),
                  FileManager.default.fileExists(atPath: s) else { return nil }
            return URL(fileURLWithPath: s)
        }
        set { defaults.set(newValue?.path, forKey: Key.soundPath) }
    }

    /// Where in the audio file the 10-second slice begins.
    var trimStart: TimeInterval {
        get { defaults.double(forKey: Key.trimStart) }
        set { defaults.set(newValue, forKey: Key.trimStart) }
    }

    /// The URL we'll actually play — user choice if set, otherwise bundled fallback.
    var effectiveSoundURL: URL? {
        if let u = soundURL { return u }
        return Bundle.main.url(forResource: "bbc_news_theme", withExtension: "mp3")
    }

    /// True when a custom sound is in use (drives the 2-second fade-in).
    var usesCustomSound: Bool { soundURL != nil }

    /// Display name for the current sound (file name).
    var soundDisplayName: String {
        if let u = soundURL { return u.lastPathComponent }
        return "bbc_news_theme.mp3 (default)"
    }

    /// `~/Library/Application Support/Dramatic Events/`
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Dramatic Events", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }()

    /// Copy `sourceURL` into Application Support and remember it.
    /// Returns the destination URL on success.
    @discardableResult
    func setCustomSound(from sourceURL: URL) throws -> URL {
        // Wipe any previous sound.* (extension may differ).
        if let existing = try? FileManager.default.contentsOfDirectory(
            at: Settings.supportDir,
            includingPropertiesForKeys: nil) {
            for f in existing where f.deletingPathExtension().lastPathComponent == "sound" {
                try? FileManager.default.removeItem(at: f)
            }
        }
        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let dest = Settings.supportDir
            .appendingPathComponent("sound")
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        soundURL = dest
        trimStart = 0
        return dest
    }

    /// Forget the custom sound (revert to bundled default).
    func resetSound() {
        if let u = soundURL {
            try? FileManager.default.removeItem(at: u)
        }
        soundURL = nil
        trimStart = 0
    }
}
