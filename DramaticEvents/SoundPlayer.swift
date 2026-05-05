import AVFoundation

/// Plays the configured 10-second snippet when a meeting is about to start.
/// All sounds get a 2-second fade-in for polish.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var stopTimer: Timer?

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
            p.currentTime = start
            let playbackLength = min(10.0, p.duration - start)

            p.volume = 0
            p.play()
            p.setVolume(1.0, fadeDuration: 2.0)
            player = p

            stopTimer = Timer.scheduledTimer(withTimeInterval: playbackLength,
                                             repeats: false) { [weak self] _ in
                self?.stop()
            }
        } catch {
            NSLog("⚠️ AVAudioPlayer init error: \(error)")
        }
    }

    /// Stops playback and cancels any pending stop timer. Idempotent.
    func stop() {
        stopTimer?.invalidate()
        stopTimer = nil
        player?.stop()
        player = nil
    }
}
