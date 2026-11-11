import Foundation

/// Groq's free developer tier.
///
/// - Speech: `whisper-large-v3-turbo` (default) or `whisper-large-v3`, through the
///   OpenAI-compatible `/audio/transcriptions` endpoint. The free tier accepts
///   files up to 25 MB and 20 requests / 7,200 audio-seconds per hour.
/// - Text: `openai/gpt-oss-20b` (default), `openai/gpt-oss-120b` or
///   `qwen/qwen3.8-27b`. Reasoning is kept to the minimum each model allows,
///   because a cleanup pass needs speed, not deliberation.
enum GroqAPI {
    static let baseURL = URL(string: "https://api.groq.com/openai/v1")!
    /// 25 MB free-tier cap, minus headroom for the multipart envelope.
    static let maxUploadBytes = 24 * 1024 * 1024

    /// Reasoning controls per model family, as documented by Groq.
    static func reasoningFields(for model: String) -> [String: Any] {
        let lowered = model.lowercased()
        if lowered.hasPrefix("openai/gpt-oss") {
            return ["reasoning_effort": "low", "include_reasoning": false]
        }
        if lowered.hasPrefix("qwen/") {
            return ["reasoning_effort": "none"]
        }
        return [:]
    }
}

struct GroqTranscriber: SpeechRecognizer {
    let apiKey: String
    let model: String
    let language: DictationLanguage
    let vocabulary: [String]

    var provider: AIProvider { .groq }
    var displayName: String { "Groq · \(model)" }
    var maxUploadBytes: Int { GroqAPI.maxUploadBytes }

    func transcribe(audio: PreparedAudio) async throws -> TranscriptionResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.groq) }
        let start = Date()
        let text = try await OpenAICompatibleAPI.transcribe(
            .init(
                baseURL: GroqAPI.baseURL,
                apiKey: apiKey,
                model: model,
                language: language,
                prompt: OpenAICompatibleAPI.whisperPrompt(vocabulary: vocabulary),
                verbose: true,
                provider: .groq
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

struct GroqRewriter: TextRewriter {
    let apiKey: String
    let model: String

    var provider: AIProvider { .groq }
    var displayName: String { "Groq · \(model)" }

    func rewrite(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.groq) }
        let start = Date()
        var extra = GroqAPI.reasoningFields(for: model)
        extra["temperature"] = 0.2
        extra["max_completion_tokens"] = 4096
        let output = try await OpenAICompatibleAPI.complete(
            .init(
                baseURL: GroqAPI.baseURL,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userMessage: RewritePrompts.userMessage(for: inputText),
                provider: .groq,
                extraBody: extra
            )
        )
        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: RewriteOutput.clean(output),
            latency: Date().timeIntervalSince(start)
        )
    }
}
