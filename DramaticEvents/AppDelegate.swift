import Cocoa
import EventKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemManager: StatusItemManager!
    private let calendarManager = CalendarManager()
    private let soundPlayer = SoundPlayer()

    private var timer: Timer?
    private var currentEvent: EKEvent?
    private var soundStartedForEventID: String?
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the runloop / timer ticking and audio firing on time even when
        // another app is foreground. Without this, App Nap can throttle our
        // 1-second timer and the meeting sound misses its launch window.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Live countdown to next calendar event")

        statusItemManager = StatusItemManager()
        statusItemManager.onRefresh      = { [weak self] in self?.refreshEvent() }
        statusItemManager.onOpenCalendar = {
            if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
        }
        statusItemManager.onOpenSettings = {
            SettingsWindowController.shared.show()
        }
        statusItemManager.showText("Loading…")

        calendarManager.requestAccess { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.statusItemManager.showText("Calendar access denied")
                    return
                }
                self.startTimer()
                self.refreshEvent()
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshEvent),
            name: .EKEventStoreChanged, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshEvent),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func refreshEvent() {
        calendarManager.fetchNextEvent { [weak self] event in
            DispatchQueue.main.async {
                self?.currentEvent = event
                self?.updateJoinMenuItem(for: event)
                self?.tick()
            }
        }
    }

    private func updateJoinMenuItem(for event: EKEvent?) {
        guard let event = event,
              let url = EventLinkParser.extractURL(from: event) else {
            statusItemManager.setJoin(label: nil, url: nil)
            return
        }
        statusItemManager.setJoin(label: event.title ?? "meeting", url: url)
    }

    @objc private func tick() {
        guard let event = currentEvent else {
            statusItemManager.setMode(.normal)
            statusItemManager.showText("No meetings today")
            return
        }
        let title = event.title ?? "Meeting"
        let interval = event.startDate.timeIntervalSinceNow
        let id = event.eventIdentifier

        if interval > 0 {
            // Countdown
            let secondsLeft = Int(interval.rounded(.up))
            statusItemManager.setMode(secondsLeft <= 10 ? .urgent : .normal)
            statusItemManager.showStructured(
                title: title,
                suffix: " in \(formatCountdown(seconds: secondsLeft))")

            // Sound + urgent visual fire together at T-10s.
            if secondsLeft <= 10, soundStartedForEventID != id {
                soundStartedForEventID = id
                soundPlayer.playMeetingSound()
            }
        } else if interval >= -60 {
            // Live state — first 60 s of the event. Solid red, no flash.
            statusItemManager.setMode(.live)
            statusItemManager.showStructured(title: title, suffix: " is live!")
            soundPlayer.stop()
        } else {
            // After 1 minute, advance to the next event.
            statusItemManager.setMode(.normal)
            refreshEvent()
        }
    }

    /// `H:MM` when ≥ 60 s remain; `SSs` (zero-padded) when under a minute.
    private func formatCountdown(seconds: Int) -> String {
        if seconds < 60 { return String(format: "%02ds", seconds) }
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours):\(String(format: "%02d", minutes))"
    }
}
