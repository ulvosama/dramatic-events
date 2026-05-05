import Foundation

/// Persistent app settings backed by `UserDefaults`. The chosen audio file
/// is copied into Application Support so it stays available even if the user
/// moves or deletes the original.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let soundPath = "soundPath"
        static let trimStart = "trimStart"
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
