import SwiftUI

/// Multi-mode intelligence panel — replaces the fixed suggestions view.
/// Modes: Off (no LLM calls), Passive (auto-suggestions), Query (ask questions), Analyze (one-click prompts).
struct IntelligencePanelView: View {
    let intelligenceEngine: IntelligenceEngine
    let suggestions: [Suggestion]
    let isGeneratingSuggestions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mode picker
            modePicker
            Divider()

            // Mode content
            switch intelligenceEngine.mode {
            case .off:
                offContent
            case .passive:
                SuggestionsView(
                    suggestions: suggestions,
                    isGenerating: isGeneratingSuggestions
                )
            case .query:
                queryContent
            case .analyze:
                analyzeContent
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(IntelligenceMode.allCases, id: \.self) { mode in
                modeTab(mode)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func modeTab(_ mode: IntelligenceMode) -> some View {
        let isSelected = intelligenceEngine.mode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                intelligenceEngine.mode = mode
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modeIcon(mode))
                    .font(.system(size: 10))
                Text(mode.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentTeal.opacity(0.12) : Color.clear)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func modeIcon(_ mode: IntelligenceMode) -> String {
        switch mode {
        case .off: "moon.zzz"
        case .passive: "sparkles"
        case .query: "magnifyingglass"
        case .analyze: "chart.bar.doc.horizontal"
        }
    }

    // MARK: - Off Content

    private var offContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Intelligence paused")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No LLM calls are being made.\nSwitch to a mode to get started.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Query Content

    private var queryContent: some View {
        VStack(spacing: 0) {
            // Response area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if intelligenceEngine.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Thinking...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentTeal.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    let queryResponses = intelligenceEngine.responses.filter {
                        if case .query = $0.kind { return true }
                        return false
                    }

                    ForEach(queryResponses) { response in
                        ResponseCard(response: response)
                    }

                    if queryResponses.isEmpty && !intelligenceEngine.isProcessing {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("Ask a question")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Query the LLM about this meeting.\nIt sees the transcript so far.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    }
                }
                .padding(16)
            }

            Divider()

            // Query input
            QueryInputBar(onSubmit: { question in
                intelligenceEngine.query(question)
            })
        }
    }

    // MARK: - Analyze Content

    private var analyzeContent: some View {
        VStack(spacing: 0) {
            // Preset buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnalysisPreset.allCases) { preset in
                        Button {
                            intelligenceEngine.analyze(preset)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 11))
                                Text(preset.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentTeal.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(intelligenceEngine.isProcessing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            // Results
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if intelligenceEngine.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Analyzing...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentTeal.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    let analysisResponses = intelligenceEngine.responses.filter {
                        if case .analysis = $0.kind { return true }
                        return false
                    }

                    ForEach(analysisResponses) { response in
                        ResponseCard(response: response)
                    }

                    if analysisResponses.isEmpty && !intelligenceEngine.isProcessing {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("One-click analysis")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Tap a button above to analyze\nthe meeting transcript.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - Query Input Bar

private struct QueryInputBar: View {
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask about this meeting...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit {
                    submit()
                }

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color.accentTeal)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { isFocused = true }
    }

    private func submit() {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        onSubmit(question)
        text = ""
    }
}

// MARK: - Response Card

private struct ResponseCard: View {
    let response: IntelligenceResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Prompt/question label
            HStack(spacing: 4) {
                Image(systemName: promptIcon)
                    .font(.system(size: 9))
                Text(response.prompt)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(response.timestamp, style: .time)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)

            // Response text
            Text(response.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var promptIcon: String {
        switch response.kind {
        case .query: "magnifyingglass"
        case .analysis(let preset): preset.icon
        }
    }
}
