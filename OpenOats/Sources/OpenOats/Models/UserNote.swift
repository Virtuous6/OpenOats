import Foundation

/// A timestamped note captured by the user during a live meeting.
/// Immutable — create new instances instead of mutating.
struct UserNote: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let timestamp: Date
    /// Seconds elapsed since session start when note was captured.
    let sessionElapsed: TimeInterval

    init(text: String, timestamp: Date = .now, sessionElapsed: TimeInterval) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.sessionElapsed = sessionElapsed
    }

    /// Formatted elapsed time as [MM:SS].
    var elapsedLabel: String {
        let minutes = Int(sessionElapsed) / 60
        let seconds = Int(sessionElapsed) % 60
        return String(format: "[%02d:%02d]", minutes, seconds)
    }
}
