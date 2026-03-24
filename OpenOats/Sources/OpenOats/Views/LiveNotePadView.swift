import SwiftUI

/// Floating quick-note panel shown during live recording.
/// Cmd+N toggles visibility. Enter saves a note. Esc dismisses.
struct LiveNotePadView: View {
    @Bindable var noteStore: LiveNoteStore
    /// Called when a note is saved — caller should persist to SessionRepository.
    var onNoteSaved: ((String) -> Void)?
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quick Note")
                        .font(.system(size: 12, weight: .semibold))
                    Text("⌘N")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .cornerRadius(3)
                }
                .foregroundStyle(.blue)

                Spacer()

                if noteStore.isActive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .opacity(1.0)
                        Text(elapsedLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // Saved notes list
            if !noteStore.notes.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(noteStore.notes) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(note.elapsedLabel)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.blue)
                                    Text(note.text)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary)
                                .cornerRadius(6)
                                .id(note.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 160)
                    .onChange(of: noteStore.notes.count) { _, _ in
                        if let last = noteStore.notes.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            VStack(spacing: 4) {
                TextField("Type a note... (Enter to save)", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(.quaternary)
                    .cornerRadius(8)
                    .focused($isInputFocused)
                    .onSubmit {
                        saveNote()
                    }

                HStack {
                    Text("Enter to save · Esc to dismiss")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(noteStore.count) note\(noteStore.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isInputFocused = true
            timerTick = .now
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            timerTick = now
        }
    }

    private func saveNote() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        noteStore.append(text: text)
        onNoteSaved?(text)
        inputText = ""
    }

    // MARK: - Live Elapsed Timer

    private var elapsedLabel: String {
        guard let start = noteStore.sessionStartTime else { return "00:00" }
        let elapsed = timerTick.timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Ticks every second to drive elapsed time display.
    @State private var timerTick = Date()

    init(noteStore: LiveNoteStore, onNoteSaved: ((String) -> Void)? = nil) {
        self.noteStore = noteStore
        self.onNoteSaved = onNoteSaved
    }
}
