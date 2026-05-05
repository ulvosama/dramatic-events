import Foundation
import EventKit

enum EventLinkParser {

    private static let patterns: [NSRegularExpression] = {
        let raws = [
            #"https?://[\w.-]*zoom\.us/(?:j|my|w|s)/\S+"#,
            #"https?://meet\.google\.com/[A-Za-z0-9?=_-]+"#,
            #"https?://teams\.(?:microsoft|live)\.com/l/meetup-join/\S+"#,
            #"https?://[\w.-]*webex\.com/\S+"#
        ]
        return raws.map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    /// Returns the first video-conferencing URL referenced by the event, if any.
    /// Checks `event.url`, then scans `notes` and `location` for known providers.
    static func extractURL(from event: EKEvent) -> URL? {
        if let u = event.url, isVideoLink(u.absoluteString) { return u }
        for text in [event.notes, event.location].compactMap({ $0 }) {
            if let url = firstMatch(in: text) { return url }
        }
        return nil
    }

    private static func firstMatch(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            if let m = pattern.firstMatch(in: text, range: range),
               let r = Range(m.range, in: text) {
                let raw = String(text[r])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>\""))
                if let url = URL(string: raw) { return url }
            }
        }
        return nil
    }

    private static func isVideoLink(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return patterns.contains { $0.firstMatch(in: s, range: range) != nil }
    }
}
