import Foundation
import Observation

/// Merges user notes with meeting transcript to produce enriched notes.
/// User notes become the skeleton; transcript provides the flesh.
@Observable
@MainActor
final class NoteMergeEngine {
    @ObservationIgnored nonisolated(unsafe) private var _isGenerating = false
    private(set) var isGenerating: Bool {
        get { access(keyPath: \.isGenerating); return _isGenerating }
        set { withMutation(keyPath: \.isGenerating) { _isGenerating = newValue } }
    }

    @ObservationIgnored nonisolated(unsafe) private var _generatedMarkdown = ""
    private(set) var generatedMarkdown: String {
        get { access(keyPath: \.generatedMarkdown); return _generatedMarkdown }
        set { withMutation(keyPath: \.generatedMarkdown) { _generatedMarkdown = newValue } }
    }

    @ObservationIgnored nonisolated(unsafe) private var _error: String?
    private(set) var error: String? {
        get { access(keyPath: \.error); return _error }
        set { withMutation(keyPath: \.error) { _error = newValue } }
    }

    private let client = OpenRouterClient()
    private var currentTask: Task<Void, Never>?

    /// Merge user notes with transcript, streaming the result.
    func merge(
        userNotes: [UserNote],
        transcript: [SessionRecord],
        settings: AppSettings
    ) async {
        currentTask?.cancel()
        isGenerating = true
        generatedMarkdown = ""
        error = nil

        let apiKey: String?
        let baseURL: URL?
        let model: String

        switch settings.llmProvider {
        case .openRouter:
            apiKey = settings.openRouterApiKey.isEmpty ? nil : settings.openRouterApiKey
            baseURL = nil
            model = settings.selectedModel
        case .ollama:
            apiKey = nil
            guard let url = OpenRouterClient.chatCompletionsURL(from: settings.ollamaBaseURL) else {
                error = "Invalid Ollama URL"
                isGenerating = false
                return
            }
            baseURL = url
            model = settings.ollamaLLMModel
        case .mlx:
            apiKey = nil
            guard let url = OpenRouterClient.chatCompletionsURL(from: settings.mlxBaseURL) else {
                error = "Invalid MLX URL"
                isGenerating = false
                return
            }
            baseURL = url
            model = settings.mlxModel
        case .openAICompatible:
            apiKey = settings.openAILLMApiKey.isEmpty ? nil : settings.openAILLMApiKey
            guard let url = OpenRouterClient.chatCompletionsURL(from: settings.openAILLMBaseURL) else {
                error = "Invalid OpenAI Compatible URL"
                isGenerating = false
                return
            }
            baseURL = url
            model = settings.openAILLMModel
        }

        let messages = buildMergePrompt(userNotes: userNotes, transcript: transcript)

        currentTask = Task {
            do {
                let stream = await client.streamCompletion(
                    apiKey: apiKey,
                    model: model,
                    messages: messages,
                    maxTokens: 4096,
                    baseURL: baseURL
                )
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    generatedMarkdown += chunk
                }
            } catch {
                if !Task.isCancelled {
                    self.error = "Merge failed: \(error.localizedDescription)"
                }
            }
            isGenerating = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        isGenerating = false
    }

    // MARK: - Prompt Builder

    private func buildMergePrompt(
        userNotes: [UserNote],
        transcript: [SessionRecord]
    ) -> [OpenRouterClient.Message] {

        // Format user notes with timestamps
        var notesText = ""
        for note in userNotes {
            notesText += "\(note.elapsedLabel) \(note.text)\n"
        }

        // Format transcript, using ±30s window markers around each note
        let noteTimestamps = Set(userNotes.map { $0.sessionElapsed })
        var transcriptText = ""
        let sessionStart = transcript.first?.timestamp ?? Date()

        for record in transcript {
            let elapsed = record.timestamp.timeIntervalSince(sessionStart)
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            let speaker = record.speaker.displayLabel
            let text = record.refinedText ?? record.text
            transcriptText += "[\(String(format: "%02d:%02d", minutes, seconds))] \(speaker): \(text)\n"
        }

        // Truncate if too long (keep head + tail)
        if transcriptText.count > 60_000 {
            let headEnd = transcriptText.index(transcriptText.startIndex, offsetBy: 25_000)
            let tailStart = transcriptText.index(transcriptText.endIndex, offsetBy: -25_000)
            let omitted = transcriptText.count - 50_000
            transcriptText = String(transcriptText[..<headEnd])
                + "\n\n[... \(omitted) characters omitted ...]\n\n"
                + String(transcriptText[tailStart...])
        }

        let system = """
        You are a meeting notes enhancer. The user took shorthand notes during a meeting. \
        You also have the full meeting transcript. Your job is to produce enriched meeting notes \
        that use the user's notes as the STRUCTURE and the transcript as the SOURCE OF DETAIL.

        Rules:
        - Each user note becomes a section or bullet point in the output
        - Expand each note with relevant context, quotes, and specifics from the transcript
        - Use a ±30 second window around each note's timestamp to find the most relevant transcript context
        - For short notes (1-3 words), treat them as topic markers — find what was discussed around that time
        - For longer notes, treat them as the user's interpretation — validate and enrich with transcript evidence
        - Include direct quotes from the transcript where they add value (use > blockquote format)
        - Flag any note that references something NOT discussed in the transcript as an "Open Item"
        - Keep the output concise and actionable — no filler
        - Use markdown formatting: ## for sections, - for bullets, > for quotes, **bold** for emphasis
        - End with an "Action Items" section if any commitments were made
        """

        let user = """
        ## User's Notes (taken during the meeting)
        \(notesText)

        ## Full Meeting Transcript
        \(transcriptText)

        Produce enriched meeting notes using the user's notes as structure:
        """

        return [
            .init(role: "system", content: system),
            .init(role: "user", content: user)
        ]
    }
}
