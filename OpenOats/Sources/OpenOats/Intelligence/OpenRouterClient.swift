import Foundation

/// Streaming OpenAI-compatible client for OpenRouter API (and Ollama via OpenAI-compatible endpoint).
actor OpenRouterClient {
    private static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // MARK: - Timeout

    /// Timeout for streaming requests (URLRequest.timeoutInterval).
    private static let streamTimeoutSeconds: TimeInterval = 30

    // MARK: - Circuit Breaker

    private static let circuitBreakerThreshold = 3
    private static let circuitBreakerBaseDelay: TimeInterval = 30
    private static let circuitBreakerMaxDelay: TimeInterval = 300

    private var consecutiveFailures = 0
    private var circuitOpenUntil: Date?

    private func recordSuccess() {
        consecutiveFailures = 0
        circuitOpenUntil = nil
    }

    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= Self.circuitBreakerThreshold {
            let delay = min(
                Self.circuitBreakerBaseDelay * pow(2.0, Double(consecutiveFailures - Self.circuitBreakerThreshold)),
                Self.circuitBreakerMaxDelay
            )
            circuitOpenUntil = Date.now.addingTimeInterval(delay)
        }
    }

    private func checkCircuitBreaker() throws {
        if let openUntil = circuitOpenUntil, Date.now < openUntil {
            let remaining = openUntil.timeIntervalSince(.now)
            throw CircuitBreakerError.open(retryAfter: remaining)
        }
        // If past the deadline, allow a probe attempt
        if circuitOpenUntil != nil, Date.now >= circuitOpenUntil! {
            circuitOpenUntil = nil
        }
    }

    enum CircuitBreakerError: Error, LocalizedError {
        case open(retryAfter: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .open(let seconds):
                "LLM circuit breaker open — retry in \(Int(seconds))s"
            }
        }
    }

    /// Builds a chat completions URL from a user-provided base URL, stripping
    /// any trailing `/v1` or `/v1/chat/completions` to avoid double-pathing.
    static func chatCompletionsURL(from rawBase: String) -> URL? {
        var base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Strip paths that users commonly include so we don't get /v1/v1/...
        for suffix in ["/v1/chat/completions", "/v1"] {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
            }
        }
        return URL(string: base + "/v1/chat/completions")
    }

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let max_tokens: Int?
        let max_completion_tokens: Int?
    }

    /// Streams the completion response, yielding text chunks.
    /// Enforces a 30s timeout on the initial connection via URLRequest.timeoutInterval.
    /// Circuit breaker prevents repeated calls to a broken endpoint.
    func streamCompletion(
        apiKey: String? = nil,
        model: String,
        messages: [Message],
        maxTokens: Int = 1024,
        baseURL: URL? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    try await self?.checkCircuitBreaker()

                    let request = ChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        max_tokens: nil,
                        max_completion_tokens: maxTokens
                    )

                    let targetURL = baseURL ?? Self.defaultBaseURL
                    var urlRequest = URLRequest(url: targetURL)
                    urlRequest.httpMethod = "POST"
                    urlRequest.timeoutInterval = TimeInterval(Self.streamTimeoutSeconds)
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let apiKey, !apiKey.isEmpty {
                        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    if targetURL.host?.contains("openrouter.ai") == true {
                        urlRequest.setValue("OpenOats/2.0", forHTTPHeaderField: "HTTP-Referer")
                    }
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        await self?.recordFailure()
                        continuation.finish(throwing: OpenRouterError.httpError(statusCode, host: targetURL.host))
                        return
                    }

                    var receivedAny = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(SSEChunk.self, from: data),
                           let content = chunk.choices.first?.delta.content {
                            receivedAny = true
                            continuation.yield(content)
                        }
                    }

                    if receivedAny {
                        await self?.recordSuccess()
                    }
                    continuation.finish()
                } catch {
                    await self?.recordFailure()
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Non-streaming completion for structured JSON tasks (gate decisions, state updates).
    /// Circuit breaker prevents hammering a broken endpoint after consecutive failures.
    func complete(
        apiKey: String? = nil,
        model: String,
        messages: [Message],
        maxTokens: Int = 512,
        baseURL: URL? = nil
    ) async throws -> String {
        try checkCircuitBreaker()

        let request = ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            max_tokens: nil,
            max_completion_tokens: maxTokens
        )

        let targetURL = baseURL ?? Self.defaultBaseURL
        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if targetURL.host?.contains("openrouter.ai") == true {
            urlRequest.setValue("OpenOats/2.0", forHTTPHeaderField: "HTTP-Referer")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                recordFailure()
                throw OpenRouterError.httpError(statusCode, host: targetURL.host)
            }

            let completionResponse = try JSONDecoder().decode(CompletionResponse.self, from: data)
            recordSuccess()
            return completionResponse.choices.first?.message.content ?? ""
        } catch let error as OpenRouterError {
            throw error
        } catch {
            recordFailure()
            throw error
        }
    }

    enum OpenRouterError: Error, LocalizedError {
        case httpError(Int, host: String?)

        var errorDescription: String? {
            switch self {
            case .httpError(let code, let host):
                let provider = switch host {
                case let h? where h.contains("openrouter.ai"): "OpenRouter"
                case let h? where h.contains("localhost"), let h? where h.contains("127.0.0.1"): "Local LLM"
                case let h?: h
                case nil: "LLM"
                }
                return "\(provider) API error (HTTP \(code))"
            }
        }
    }

    // MARK: - SSE Types

    private struct SSEChunk: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let delta: Delta
        }

        struct Delta: Codable {
            let content: String?
        }
    }

    private struct CompletionResponse: Codable {
        let choices: [CompletionChoice]

        struct CompletionChoice: Codable {
            let message: CompletionMessage
        }

        struct CompletionMessage: Codable {
            let content: String
        }
    }
}

