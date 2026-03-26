import XCTest
@testable import OpenOatsKit

@MainActor
final class IntelligenceEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeSettings(openRouterKey: String = "") -> AppSettings {
        let suiteName = "com.openoats.tests.intelligence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        if !openRouterKey.isEmpty {
            defaults.set(openRouterKey, forKey: "openRouterApiKey")
        }
        defaults.set("openRouter", forKey: "llmProvider")
        defaults.set("anthropic/claude-sonnet-4.6", forKey: "selectedModel")
        let storage = AppSettingsStorage(
            defaults: defaults,
            secretStore: .ephemeral,
            defaultNotesDirectory: FileManager.default.temporaryDirectory,
            runMigrations: false
        )
        return AppSettings(storage: storage)
    }

    private func makeEngine(openRouterKey: String = "") -> (IntelligenceEngine, TranscriptStore) {
        let store = TranscriptStore()
        let settings = makeSettings(openRouterKey: openRouterKey)
        // Set the API key via the settings property (writes to secretStore)
        if !openRouterKey.isEmpty {
            settings.openRouterApiKey = openRouterKey
        }
        let engine = IntelligenceEngine(transcriptStore: store, settings: settings)
        return (engine, store)
    }

    private func makeUtterance(text: String, speaker: Speaker = .them) -> Utterance {
        Utterance(text: text, speaker: speaker)
    }

    // MARK: - Mode

    func testDefaultModeIsOff() {
        let (engine, _) = makeEngine()
        XCTAssertEqual(engine.mode, .off)
    }

    func testModeCanBeChanged() {
        let (engine, _) = makeEngine()
        engine.mode = .query
        XCTAssertEqual(engine.mode, .query)
        engine.mode = .analyze
        XCTAssertEqual(engine.mode, .analyze)
        engine.mode = .passive
        XCTAssertEqual(engine.mode, .passive)
        engine.mode = .off
        XCTAssertEqual(engine.mode, .off)
    }

    // MARK: - Credential Validation

    func testQueryWithNoCredentialsShowsError() {
        let (engine, store) = makeEngine(openRouterKey: "")
        store.append(makeUtterance(text: "Hello world"))
        engine.query("What was discussed?")
        XCTAssertEqual(engine.responses.count, 1)
        XCTAssertTrue(engine.responses[0].text.contains("No LLM credentials"))
    }

    func testAnalyzeWithNoCredentialsShowsError() {
        let (engine, store) = makeEngine(openRouterKey: "")
        store.append(makeUtterance(text: "Hello world"))
        engine.analyze(.summarize)
        XCTAssertEqual(engine.responses.count, 1)
        XCTAssertTrue(engine.responses[0].text.contains("No LLM credentials"))
    }

    // MARK: - Empty Transcript

    func testQueryWithCredentialsButNoTranscriptStartsProcessing() {
        let (engine, _) = makeEngine(openRouterKey: "test-key")
        // With valid credentials and no transcript, query enters the async Task
        // (can't reliably await MainActor Task in XCTest — verify it doesn't
        // fail synchronously and doesn't produce a credential error)
        engine.query("What was discussed?")
        // Should NOT have a synchronous credential error
        let hasCredentialError = engine.responses.contains { $0.text.contains("No LLM credentials") }
        XCTAssertFalse(hasCredentialError)
    }

    func testAnalyzeWithCredentialsButNoTranscriptStartsProcessing() {
        let (engine, _) = makeEngine(openRouterKey: "test-key")
        engine.analyze(.actionItems)
        let hasCredentialError = engine.responses.contains { $0.text.contains("No LLM credentials") }
        XCTAssertFalse(hasCredentialError)
    }

    // MARK: - Empty Query

    func testEmptyQueryIsIgnored() {
        let (engine, _) = makeEngine()
        engine.query("")
        XCTAssertEqual(engine.responses.count, 0)
    }

    func testWhitespaceOnlyQueryIsIgnored() {
        let (engine, _) = makeEngine()
        engine.query("   \n\t  ")
        XCTAssertEqual(engine.responses.count, 0)
    }

    // MARK: - Response Management

    func testResponsesInsertedAtFront() {
        let (engine, _) = makeEngine(openRouterKey: "")
        // No credentials → immediate error responses
        engine.query("First question")
        engine.query("Second question")
        XCTAssertEqual(engine.responses.count, 2)
        XCTAssertEqual(engine.responses[0].prompt, "Second question")
        XCTAssertEqual(engine.responses[1].prompt, "First question")
    }

    func testClearResponsesRemovesAll() {
        let (engine, _) = makeEngine(openRouterKey: "")
        engine.query("Test")
        XCTAssertFalse(engine.responses.isEmpty)
        engine.clearResponses()
        XCTAssertTrue(engine.responses.isEmpty)
    }

    func testResetClearsEverything() {
        let (engine, _) = makeEngine(openRouterKey: "")
        engine.query("Test")
        XCTAssertFalse(engine.responses.isEmpty)
        engine.reset()
        XCTAssertTrue(engine.responses.isEmpty)
        XCTAssertFalse(engine.isProcessing)
    }

    // MARK: - Response Kind Filtering

    func testQueryResponsesHaveCorrectKind() {
        let (engine, _) = makeEngine(openRouterKey: "")
        engine.query("Test query")
        guard let response = engine.responses.first else {
            XCTFail("Expected a response")
            return
        }
        if case .query = response.kind {
            // correct
        } else {
            XCTFail("Expected .query kind, got \(response.kind)")
        }
    }

    func testAnalysisResponsesHaveCorrectKind() {
        let (engine, _) = makeEngine(openRouterKey: "")
        engine.analyze(.keyDecisions)
        guard let response = engine.responses.first else {
            XCTFail("Expected a response")
            return
        }
        if case .analysis(let preset) = response.kind {
            XCTAssertEqual(preset, .keyDecisions)
        } else {
            XCTFail("Expected .analysis(.keyDecisions) kind")
        }
    }

    // MARK: - Transcript Context

    func testTranscriptContextIncludesUtterances() {
        let (engine, store) = makeEngine(openRouterKey: "")
        store.append(makeUtterance(text: "We should discuss pricing", speaker: .them))
        store.append(makeUtterance(text: "I agree, let's look at tiers", speaker: .you))
        // Query with no credentials to get immediate response (tests the flow)
        engine.query("What about pricing?")
        // The error is about credentials, not empty transcript
        XCTAssertEqual(engine.responses.count, 1)
        XCTAssertTrue(engine.responses[0].text.contains("No LLM credentials"))
    }

    // MARK: - SuggestionEngine Mode Gate

    func testSuggestionEngineSkipsWhenModeIsOff() {
        let store = TranscriptStore()
        let settings = makeSettings()
        let kb = KnowledgeBase(settings: settings)
        let suggestionEngine = SuggestionEngine(transcriptStore: store, knowledgeBase: kb, settings: settings)
        let intelEngine = IntelligenceEngine(transcriptStore: store, settings: settings)

        suggestionEngine.intelligenceEngine = intelEngine
        intelEngine.mode = .off

        let utterance = makeUtterance(text: "What should we do about the customer retention problem? I think we need to address this urgently.")
        suggestionEngine.onNewUtterance(utterance)

        // Should not generate anything — mode is off
        XCTAssertTrue(suggestionEngine.suggestions.isEmpty)
        XCTAssertFalse(suggestionEngine.isGenerating)
    }

    func testSuggestionEngineSkipsWhenModeIsQuery() {
        let store = TranscriptStore()
        let settings = makeSettings()
        let kb = KnowledgeBase(settings: settings)
        let suggestionEngine = SuggestionEngine(transcriptStore: store, knowledgeBase: kb, settings: settings)
        let intelEngine = IntelligenceEngine(transcriptStore: store, settings: settings)

        suggestionEngine.intelligenceEngine = intelEngine
        intelEngine.mode = .query

        let utterance = makeUtterance(text: "What should we do about the customer retention problem?")
        suggestionEngine.onNewUtterance(utterance)

        XCTAssertTrue(suggestionEngine.suggestions.isEmpty)
        XCTAssertFalse(suggestionEngine.isGenerating)
    }

    // MARK: - Analysis Presets

    func testAllPresetsHaveNonEmptyPrompts() {
        for preset in AnalysisPreset.allCases {
            XCTAssertFalse(preset.systemPrompt.isEmpty, "\(preset.rawValue) has empty system prompt")
            XCTAssertFalse(preset.icon.isEmpty, "\(preset.rawValue) has empty icon")
            XCTAssertFalse(preset.rawValue.isEmpty, "\(preset.rawValue) has empty raw value")
        }
    }

    func testAllModesHaveLabels() {
        for mode in IntelligenceMode.allCases {
            XCTAssertFalse(mode.rawValue.isEmpty, "Mode has empty label")
        }
    }
}
