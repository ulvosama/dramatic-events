import AVFoundation

/// Plays the configured snippet when a meeting is about to start.
///
/// Timing model — `lead + tail`:
///   • lead = 10 s (fires when the urgent visual kicks in at T-10s).
///   • tail = 2 s for the bundled default sound, 0 for user-uploaded sounds.
///
/// The 2-second tail on the default lets the BBC News theme's climax land
/// during the "is live!" state instead of being cut off at T=0. User-uploaded
/// sounds are explicitly trimmed to a 10-second slice via the Settings UI, so
/// playing past their slice would feel wrong — those stay strictly 10 s.
///
/// Every sound also gets:
///   • A 2-second fade-IN at the start.
///   • A 1-second fade-OUT at the end, so playback finishes naturally.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var stopTimer: Timer?
    private var fadeOutWork: DispatchWorkItem?

    func playMeetingSound() {
        guard let url = Settings.shared.effectiveSoundURL else {
            NSLog("⚠️ No sound configured and no bundled fallback found.")
            return
        }
        do {
            stop()
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()

            let start = min(Settings.shared.trimStart,
                            max(0, p.duration - 0.1))
            let leadSeconds = 10.0
            let tailSeconds: Double = Settings.shared.usesCustomSound ? 0 : 2
            let total = min(leadSeconds + tailSeconds, p.duration - start)

            p.currentTime = start
            p.volume = 0
            p.play()
            p.setVolume(1.0, fadeDuration: 2.0)
            player = p

            // Schedule the fade-out 1 s before the hard stop so the tail
            // tapers off naturally instead of cutting abruptly.
            if total > 1.0 {
                let fade = DispatchWorkItem { [weak p] in
                    p?.setVolume(0, fadeDuration: 1.0)
                }
                fadeOutWork = fade
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + (total - 1.0),
                    execute: fade)
            }

            stopTimer = Timer.scheduledTimer(withTimeInterval: total,
                                             repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            NSLog("⚠️ AVAudioPlayer init error: \(error)")
        }
    }

    /// Stops playback and cancels any pending fade/stop work. Idempotent.
    func stop() {
        fadeOutWork?.cancel()
        fadeOutWork = nil
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
    }
}
