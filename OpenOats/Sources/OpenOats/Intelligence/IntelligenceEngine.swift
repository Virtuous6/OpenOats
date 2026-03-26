import Foundation
import Observation
import os

private let intelLog = Logger(subsystem: "com.openoats", category: "IntelligenceEngine")

/// Intelligence modes for the meeting panel.
enum IntelligenceMode: String, CaseIterable, Sendable {
    case off = "Off"
    case passive = "Passive"
    case query = "Query"
    case analyze = "Analyze"
}

/// Preset analytical prompts for one-click analysis.
enum AnalysisPreset: String, CaseIterable, Identifiable, Sendable {
    case summarize = "Summarize so far"
    case suggestQuestions = "Suggest questions"
    case keyDecisions = "Key decisions"
    case actionItems = "Action items"

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .summarize:
            return """
            You are a meeting analyst. Given the transcript of a meeting in progress, \
            provide a concise summary of what has been discussed so far. \
            Focus on key topics, positions taken, and any conclusions reached. \
            Use bullet points. Be brief — 3-5 bullets max.
            """
        case .suggestQuestions:
            return """
            You are a meeting strategist. Given the transcript of a meeting in progress, \
            suggest 3-5 questions the user should consider asking. Focus on: \
            gaps in the discussion, unstated assumptions, clarifications needed, \
            and strategic angles not yet explored. Be specific to the conversation content.
            """
        case .keyDecisions:
            return """
            You are a meeting analyst. Given the transcript of a meeting in progress, \
            identify any decisions that have been made (explicit or implicit). \
            For each decision, note who made it and what it means. \
            If no clear decisions yet, say so and note what's still open.
            """
        case .actionItems:
            return """
            You are a meeting analyst. Given the transcript of a meeting in progress, \
            extract any action items — tasks, follow-ups, commitments, or next steps \
            mentioned by any participant. For each, note who owns it if clear. \
            If none yet, say "No action items identified so far."
            """
        }
    }

    var icon: String {
        switch self {
        case .summarize: "text.alignleft"
        case .suggestQuestions: "questionmark.bubble"
        case .keyDecisions: "checkmark.seal"
        case .actionItems: "checklist"
        }
    }
}

/// A response from the intelligence engine (query or analysis).
struct IntelligenceResponse: Identifiable, Sendable {
    let id = UUID()
    let prompt: String
    let text: String
    let timestamp: Date
    let kind: Kind

    enum Kind: Sendable {
        case query
        case analysis(AnalysisPreset)
    }
}

/// Handles direct LLM queries and one-click analysis against the live transcript.
/// Separate from SuggestionEngine — no pipeline, no gate, no KB dependency.
/// Only fires when the user explicitly requests it.
@Observable
@MainActor
final class IntelligenceEngine {
    @ObservationIgnored nonisolated(unsafe) private var _mode: IntelligenceMode = .off
    var mode: IntelligenceMode {
        get { access(keyPath: \.mode); return _mode }
        set { withMutation(keyPath: \.mode) { _mode = newValue } }
    }

    @ObservationIgnored nonisolated(unsafe) private var _responses: [IntelligenceResponse] = []
    private(set) var responses: [IntelligenceResponse] {
        get { access(keyPath: \.responses); return _responses }
        set { withMutation(keyPath: \.responses) { _responses = newValue } }
    }

    @ObservationIgnored nonisolated(unsafe) private var _isProcessing = false
    private(set) var isProcessing: Bool {
        get { access(keyPath: \.isProcessing); return _isProcessing }
        set { withMutation(keyPath: \.isProcessing) { _isProcessing = newValue } }
    }

    private let client = OpenRouterClient()
    private let transcriptStore: TranscriptStore
    private let settings: AppSettings
    private var currentTask: Task<Void, Never>?

    init(transcriptStore: TranscriptStore, settings: AppSettings) {
        self.transcriptStore = transcriptStore
        self.settings = settings
    }

    // MARK: - Query Mode

    /// Submit a free-form question against the current transcript.
    func query(_ question: String) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard hasValidCredentials else {
            appendResponse(prompt: question, text: "No LLM credentials configured. Check Settings.", kind: .query)
            return
        }
        currentTask?.cancel()

        currentTask = Task {
            isProcessing = true
            defer { isProcessing = false }

            let transcript = buildTranscriptContext()
            guard !transcript.isEmpty else {
                appendResponse(prompt: question, text: "No transcript available yet.", kind: .query)
                return
            }

            let messages: [OpenRouterClient.Message] = [
                .init(role: "system", content: """
                You are a real-time meeting assistant. The user is in a meeting and asking \
                a question about the conversation. Answer based on the transcript provided. \
                If the answer isn't in the transcript, say so. Be concise — 2-4 sentences max.
                """),
                .init(role: "user", content: """
                Transcript so far:
                \(transcript)

                My question: \(question)
                """)
            ]

            do {
                let response = try await client.complete(
                    apiKey: llmApiKey,
                    model: llmModel,
                    messages: messages,
                    maxTokens: 512,
                    baseURL: llmBaseURL
                )
                guard !Task.isCancelled else { return }
                appendResponse(prompt: question, text: response, kind: .query)
                intelLog.info("Query completed: \(question.prefix(40))")
            } catch {
                guard !Task.isCancelled else { return }
                appendResponse(prompt: question, text: "Error: \(error.localizedDescription)", kind: .query)
                intelLog.error("Query failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Analyze Mode

    /// Run a preset analysis against the current transcript.
    func analyze(_ preset: AnalysisPreset) {
        guard hasValidCredentials else {
            appendResponse(
                prompt: preset.rawValue,
                text: "No LLM credentials configured. Check Settings.",
                kind: .analysis(preset)
            )
            return
        }
        currentTask?.cancel()

        currentTask = Task {
            isProcessing = true
            defer { isProcessing = false }

            let transcript = buildTranscriptContext()
            guard !transcript.isEmpty else {
                appendResponse(
                    prompt: preset.rawValue,
                    text: "No transcript available yet.",
                    kind: .analysis(preset)
                )
                return
            }

            let messages: [OpenRouterClient.Message] = [
                .init(role: "system", content: preset.systemPrompt),
                .init(role: "user", content: """
                Meeting transcript:
                \(transcript)
                """)
            ]

            do {
                let response = try await client.complete(
                    apiKey: llmApiKey,
                    model: llmModel,
                    messages: messages,
                    maxTokens: 1024,
                    baseURL: llmBaseURL
                )
                guard !Task.isCancelled else { return }
                appendResponse(prompt: preset.rawValue, text: response, kind: .analysis(preset))
                intelLog.info("Analysis completed: \(preset.rawValue)")
            } catch {
                guard !Task.isCancelled else { return }
                appendResponse(
                    prompt: preset.rawValue,
                    text: "Error: \(error.localizedDescription)",
                    kind: .analysis(preset)
                )
                intelLog.error("Analysis failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - State

    func clearResponses() {
        responses = []
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        responses = []
        isProcessing = false
    }

    // MARK: - Validation

    /// Check that the current provider has usable credentials before firing an LLM call.
    private var hasValidCredentials: Bool {
        switch settings.llmProvider {
        case .openRouter:
            return !settings.openRouterApiKey.isEmpty
        case .ollama:
            return llmBaseURL != nil
        case .mlx:
            return llmBaseURL != nil
        case .openAICompatible:
            return llmBaseURL != nil
        }
    }

    // MARK: - Private

    private func appendResponse(prompt: String, text: String, kind: IntelligenceResponse.Kind) {
        let response = IntelligenceResponse(
            prompt: prompt,
            text: text,
            timestamp: .now,
            kind: kind
        )
        responses.insert(response, at: 0)
    }

    private func buildTranscriptContext() -> String {
        let utterances = transcriptStore.utterances.suffix(200)
        guard !utterances.isEmpty else { return "" }

        return utterances.map { u in
            let label = u.speaker == .you ? "You" : u.speaker.storageKey
            return "\(label): \(u.text)"
        }.joined(separator: "\n")
    }

    private var llmApiKey: String? {
        switch settings.llmProvider {
        case .openRouter:
            let key = settings.openRouterApiKey
            return key.isEmpty ? nil : key
        default: return nil
        }
    }

    private var llmModel: String {
        switch settings.llmProvider {
        case .openRouter: settings.selectedModel
        case .ollama: settings.ollamaLLMModel
        case .mlx: settings.mlxModel
        case .openAICompatible: settings.openAILLMModel
        }
    }

    private var llmBaseURL: URL? {
        switch settings.llmProvider {
        case .openRouter: nil
        case .ollama: OpenRouterClient.chatCompletionsURL(from: settings.ollamaBaseURL)
        case .mlx: OpenRouterClient.chatCompletionsURL(from: settings.mlxBaseURL)
        case .openAICompatible: OpenRouterClient.chatCompletionsURL(from: settings.openAILLMBaseURL)
        }
    }
}
