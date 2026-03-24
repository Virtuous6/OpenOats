import Foundation
import Observation

/// In-memory store for user notes captured during a live session.
/// Notes are flushed to SessionRepository on each append for crash safety.
@Observable
@MainActor
final class LiveNoteStore {
    @ObservationIgnored nonisolated(unsafe) private var _notes: [UserNote] = []
    private(set) var notes: [UserNote] {
        get { access(keyPath: \.notes); return _notes }
        set { withMutation(keyPath: \.notes) { _notes = newValue } }
    }

    @ObservationIgnored nonisolated(unsafe) private var _isActive = false
    /// Whether the notepad is accepting input (session is recording).
    private(set) var isActive: Bool {
        get { access(keyPath: \.isActive); return _isActive }
        set { withMutation(keyPath: \.isActive) { _isActive = newValue } }
    }

    private var sessionStartTime: Date?

    /// Start a new note-taking session. Clears previous notes.
    func start(sessionStartTime: Date = .now) {
        self.sessionStartTime = sessionStartTime
        notes = []
        isActive = true
    }

    /// Add a note with automatic elapsed time calculation.
    /// Returns the created note for persistence by the caller.
    @discardableResult
    func append(text: String) -> UserNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let startTime = sessionStartTime else { return nil }

        let elapsed = Date.now.timeIntervalSince(startTime)
        let note = UserNote(text: trimmed, sessionElapsed: elapsed)
        notes.append(note)
        return note
    }

    /// Stop accepting notes. Does not clear — notes remain for post-session review.
    func stop() {
        isActive = false
    }

    /// Clear all notes and reset state.
    func clear() {
        notes = []
        isActive = false
        sessionStartTime = nil
    }

    /// Whether any notes have been captured in this session.
    var hasNotes: Bool { !notes.isEmpty }

    /// Total note count.
    var count: Int { notes.count }
}
