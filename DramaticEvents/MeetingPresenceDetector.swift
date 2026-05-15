import AppKit
import Foundation

/// Heuristics for "is the user already in a meeting?" — used to suppress the
/// dramatic sound (the visual urgent state still fires; only audio is gated).
///
/// We err on the side of *playing* sound: each signal is high-precision,
/// lower-recall. A missed-suppression (sound plays during a call) is just
/// noise; a false-positive (sound suppressed when the user actually needed
/// the reminder) is a missed meeting. The union of three signals is checked.
final class MeetingPresenceDetector {

    private let calendarManager: CalendarManager

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func isLikelyInMeeting() -> Bool {
        if calendarManager.isAnyEventInProgress() { return true }
        if Self.isInCallAppRunning()              { return true }
        if Self.isFocusActive()                    { return true }
        return false
    }

    // MARK: – Signal: in-call app subprocess

    /// Bundle IDs whose mere presence is a reliable in-call indicator:
    /// processes that only run *during* a call, or apps that aren't typically
    /// always-on. Always-running apps (Slack, full Teams) are intentionally
    /// excluded — they'd false-positive.
    private static let inCallBundleIDs: Set<String> = [
        "us.zoom.CptHost",                  // Zoom: spawned only while in a meeting
        "com.webex.meetingmanager",         // Webex Meetings (not normally running)
        "Cisco-Systems.Spark.Helper.Meeting"// Webex/Spark meeting helper
    ]

    private static func isInCallAppRunning() -> Bool {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, inCallBundleIDs.contains(id) {
                return true
            }
        }
        return false
    }

    // MARK: – Signal: Focus / Do Not Disturb

    /// macOS doesn't expose a public API for arbitrary Focus modes, but the
    /// system writes active Focus assertions to a JSON file. Reading it
    /// requires no entitlements. Format is undocumented and may change between
    /// OS versions — parse defensively and return false on any failure.
    private static func isFocusActive() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        // Shape (Ventura+): { "data": [ { "storeAssertionRecords": [ ... ] } ] }
        // A non-empty assertion-records array means at least one Focus mode is on.
        if let arr = json["data"] as? [[String: Any]] {
            for entry in arr {
                if let recs = entry["storeAssertionRecords"] as? [Any], !recs.isEmpty {
                    return true
                }
            }
        }
        return false
    }
}
