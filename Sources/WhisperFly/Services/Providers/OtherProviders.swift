import Foundation

// MARK: - OpenRouter

/// Gemini (or another audio-capable model) through OpenRouter's chat endpoint.
/// This is the 2.x backend, kept so existing OpenRouter keys keep working.
enum OpenRouterAPI {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    static let headers = [
        "HTTP-Referer": "https://github.com/dandysuper/WhisperFly",
        "X-Title": "WhisperFly",
    ]
}

struct OpenRouterTranscriber: SpeechRecognizer {
    let apiKey: String
    let model: String
    let language: DictationLanguage
    let vocabulary: [String]

    var provider: AIProvider { .openRouter }
    var displayName: String { "OpenRouter · \(model)" }
    var maxUploadBytes: Int { GeminiAPI.maxUploadBytes }

    func transcribe(audio: PreparedAudio) async throws -> TranscriptionResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.openRouter) }
        let start = Date()

        var instruction = "You are a speech-to-text engine. Transcribe the audio exactly as spoken, with correct punctuation. Output only the transcript, nothing else. If there is no speech, output nothing."
        if !language.isAuto { instruction += " The speech is most likely in \(language.englishName)." }
        if !vocabulary.isEmpty { instruction += " Spell these terms exactly: \(vocabulary.prefix(100).joined(separator: ", "))." }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instruction],
                ["role": "user", "content": [
                    ["type": "input_audio", "input_audio": ["data": try audio.data().base64EncodedString(), "format": audio.format]],
                    ["type": "text", "text": "Transcribe this audio."],
                ]],
            ],
            "temperature": 0,
        ]

        var request = URLRequest(url: OpenRouterAPI.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in OpenRouterAPI.headers { request.setValue(value, forHTTPHeaderField: header) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await HTTPTransport.send(request, provider: .openRouter)
        let json = try HTTPTransport.json(data, provider: .openRouter)
        return TranscriptionResultPayload(
            text: OpenAICompatibleAPI.messageContent(from: json).trimmed,
            latency: Date().timeIntervalSince(start),
            audioURL: audio.url,
            providerName: displayName
        )
    }
}

struct OpenRouterRewriter: TextRewriter {
    let apiKey: String
    let model: String

    var provider: AIProvider { .openRouter }
    var displayName: String { "OpenRouter · \(model)" }

    func rewrite(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.openRouter) }
        let start = Date()
        let output = try await OpenAICompatibleAPI.complete(
            .init(
                baseURL: OpenRouterAPI.baseURL,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userMessage: RewritePrompts.userMessage(for: inputText),
                provider: .openRouter,
                extraBody: ["temperature": 0.2, "max_tokens": 4096],
                extraHeaders: OpenRouterAPI.headers
            )
        )
        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: RewriteOutput.clean(output),
            latency: Date().timeIntervalSince(start)
        )
    }
}

// MARK: - OpenAI-compatible server

/// OpenAI itself, or any server that speaks its audio and chat endpoints
/// (whisper.cpp's server, LocalAI, a self-hosted faster-whisper, …).
struct CustomTranscriber: SpeechRecognizer {
    let baseURL: URL
    let apiKey: String
    let model: String
    let language: DictationLanguage
    let vocabulary: [String]

    var provider: AIProvider { .custom }
    var displayName: String { "\(baseURL.host ?? "Custom") · \(model)" }
    var maxUploadBytes: Int { 24 * 1024 * 1024 }

    func transcribe(audio: PreparedAudio) async throws -> TranscriptionResultPayload {
        let start = Date()
        let text = try await OpenAICompatibleAPI.transcribe(
            .init(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                language: language,
                prompt: OpenAICompatibleAPI.whisperPrompt(vocabulary: vocabulary),
                // `verbose_json` is Whisper-only on OpenAI; plain JSON works everywhere.
                verbose: false,
                provider: .custom
            ),
            audio: audio
        )
        return TranscriptionResultPayload(
            text: text,
            latency: Date().timeIntervalSince(start),
            audioURL: audio.url,
            providerName: displayName
        )
    }
}

struct CustomRewriter: TextRewriter {
    let baseURL: URL
    let apiKey: String
    let model: String

    var provider: AIProvider { .custom }
    var displayName: String { "\(baseURL.host ?? "Custom") · \(model)" }

    func rewrite(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload {
        let start = Date()
        let output = try await OpenAICompatibleAPI.complete(
            .init(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userMessage: RewritePrompts.userMessage(for: inputText),
                provider: .custom,
                extraBody: ["temperature": 0.2]
            )
        )
        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: RewriteOutput.clean(output),
            latency: Date().timeIntervalSince(start)
        )
    }
}

// MARK: - Factory

/// Turns settings into concrete clients.
enum ProviderFactory {

    static func recognizer(for provider: AIProvider, settings: AppSettings) -> SpeechRecognizer {
        let model = settings.transcriptionModel(for: provider)
        let language = settings.language
        let vocabulary = settings.vocabularyTerms
        switch provider {
        case .groq:
            return GroqTranscriber(apiKey: settings.groqApiKey.trimmed, model: model, language: language, vocabulary: vocabulary)
        case .gemini:
            return GeminiTranscriber(
                apiKey: settings.geminiApiKey.trimmed, model: model, language: language,
                vocabulary: vocabulary, smartFormatting: settings.geminiSmartTranscription
            )
        case .openRouter:
            return OpenRouterTranscriber(apiKey: settings.openRouterApiKey.trimmed, model: model, language: language, vocabulary: vocabulary)
        case .custom:
            return CustomTranscriber(
                baseURL: customBaseURL(settings), apiKey: settings.customApiKey.trimmed,
                model: model, language: language, vocabulary: vocabulary
            )
        }
    }

    static func rewriter(for provider: AIProvider, settings: AppSettings) -> TextRewriter {
        let model = settings.rewriteModel(for: provider)
        switch provider {
        case .groq:       return GroqRewriter(apiKey: settings.groqApiKey.trimmed, model: model)
        case .gemini:     return GeminiRewriter(apiKey: settings.geminiApiKey.trimmed, model: model)
        case .openRouter: return OpenRouterRewriter(apiKey: settings.openRouterApiKey.trimmed, model: model)
        case .custom:     return CustomRewriter(baseURL: customBaseURL(settings), apiKey: settings.customApiKey.trimmed, model: model)
        }
    }

    /// The selected engine first, then — when fallback is on — every other
    /// configured engine that does not need explicit setup (custom servers are
    /// never tried unless chosen).
    static func transcriptionChain(for settings: AppSettings) -> [AIProvider] {
        var chain = [settings.transcriptionProvider]
        guard settings.fallbackEnabled else { return chain }
        for provider in [AIProvider.groq, .gemini, .openRouter] where provider != settings.transcriptionProvider {
            if settings.isConfigured(provider) { chain.append(provider) }
        }
        return chain
    }

    static func customBaseURL(_ settings: AppSettings) -> URL {
        var raw = settings.customBaseURL.trimmed
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw) ?? URL(string: "https://api.openai.com/v1")!
    }
}

// MARK: - Key validation

/// Checks a key with the cheapest authenticated call each provider offers.
enum ProviderKeyValidator {

    static func validate(_ provider: AIProvider, settings: AppSettings) async throws {
        let key = settings.apiKey(for: provider)
        var request: URLRequest
        switch provider {
        case .groq:
            guard !key.isEmpty else { throw ProviderError.missingKey(.groq) }
            request = URLRequest(url: GroqAPI.baseURL.appendingPathComponent("models"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .gemini:
            guard !key.isEmpty else { throw ProviderError.missingKey(.gemini) }
            request = URLRequest(url: GeminiAPI.modelsURL)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .openRouter:
            guard !key.isEmpty else { throw ProviderError.missingKey(.openRouter) }
            request = URLRequest(url: OpenRouterAPI.baseURL.appendingPathComponent("key"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .custom:
            request = URLRequest(url: ProviderFactory.customBaseURL(settings).appendingPathComponent("models"))
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }
        request.timeoutInterval = 20
        _ = try await HTTPTransport.send(request, provider: provider)
    }
}
