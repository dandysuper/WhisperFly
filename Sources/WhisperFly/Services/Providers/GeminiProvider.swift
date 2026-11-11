import Foundation

/// Google's Gemini API, called directly with an AI Studio key.
///
/// Uses the Interactions API (`POST /v1beta/interactions`), which Google now
/// recommends over the legacy `generateContent`.
///
/// - Speech: `gemini-3.5-transcribe`, the dedicated speech-to-text model (free
///   tier). `transcription_config` carries the language hint, up to 1,000
///   custom-vocabulary terms and the `smart` mode, which removes disfluencies,
///   applies spoken self-corrections and formats lists, numbers and dates.
///   Any other Gemini model is used as a general multimodal model with a
///   transcription instruction instead.
/// - Text: `gemini-3.5-flash-lite` by default, with the lowest thinking level
///   the model supports.
///
/// Audio is sent inline as base64. The request limit is 20 MB, so the pipeline
/// compresses anything larger than `maxUploadBytes` to AAC first — about an
/// hour of speech, which is also the model's per-request audio limit.
enum GeminiAPI {
    static let interactionsURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!
    static let modelsURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1")!
    /// 20 MB request cap; base64 inflates by 4/3.
    static let maxUploadBytes = 14 * 1024 * 1024

    static func request(apiKey: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: interactionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The text of an interaction, across the current and legacy response shapes:
    /// `steps[].content[]` (current), `outputs[]` (pre-June 2026) and
    /// `output_text` (SDK convenience field).
    static func outputText(from json: [String: Any]) -> String {
        if let steps = json["steps"] as? [[String: Any]] {
            let text = steps
                .filter { ($0["type"] as? String) == "model_output" }
                .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                .filter { ($0["type"] as? String ?? "text") == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            if !text.isEmpty { return text }
        }
        if let outputs = json["outputs"] as? [[String: Any]] {
            let text = outputs
                .filter { ($0["type"] as? String ?? "text") == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            if !text.isEmpty { return text }
        }
        return json["output_text"] as? String ?? ""
    }

    /// The fastest thinking level each model accepts. `minimal` is not
    /// supported by 3.8 Flash, the Pro models or Gemini 4.
    static func lowestThinkingLevel(for model: String) -> String {
        let lowered = model.lowercased()
        if lowered.contains("3.8") || lowered.contains("pro") || lowered.contains("gemini-4") {
            return "low"
        }
        return "minimal"
    }
}

struct GeminiTranscriber: SpeechRecognizer {
    let apiKey: String
    let model: String
    let language: DictationLanguage
    let vocabulary: [String]
    let smartFormatting: Bool

    var provider: AIProvider { .gemini }
    var displayName: String { "Gemini · \(model)" }
    var maxUploadBytes: Int { GeminiAPI.maxUploadBytes }

    private var isDedicatedSpeechModel: Bool { model.lowercased().contains("transcribe") }

    func transcribe(audio: PreparedAudio) async throws -> TranscriptionResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.gemini) }
        let start = Date()

        let audioPart: [String: Any] = [
            "type": "audio",
            "data": try audio.data().base64EncodedString(),
            "mime_type": audio.mimeType,
        ]

        var body: [String: Any] = ["model": model, "store": false]
        if isDedicatedSpeechModel {
            var config: [String: Any] = [:]
            if let code = language.geminiCode { config["language_codes"] = [code] }
            if !vocabulary.isEmpty { config["custom_vocabulary"] = Array(vocabulary.prefix(1000)) }
            if smartFormatting { config["mode"] = "smart" }
            body["input"] = [audioPart]
            body["generation_config"] = ["transcription_config": config]
        } else {
            body["system_instruction"] = multimodalInstruction
            body["input"] = [audioPart, ["type": "text", "text": "Transcribe this audio."]]
            body["generation_config"] = ["thinking_level": GeminiAPI.lowestThinkingLevel(for: model)]
        }

        let data = try await HTTPTransport.send(try GeminiAPI.request(apiKey: apiKey, body: body), provider: .gemini)
        let json = try HTTPTransport.json(data, provider: .gemini)
        return TranscriptionResultPayload(
            text: GeminiAPI.outputText(from: json).trimmed,
            latency: Date().timeIntervalSince(start),
            audioURL: audio.url,
            providerName: displayName,
            isAlreadyPolished: isDedicatedSpeechModel && smartFormatting
        )
    }

    private var multimodalInstruction: String {
        var text = "You are a speech-to-text engine. Transcribe the audio exactly as spoken, with correct punctuation and capitalization. Output only the transcript: no labels, no quotes, no commentary. If there is no speech, output nothing."
        if !language.isAuto {
            text += " The speech is most likely in \(language.englishName)."
        }
        if !vocabulary.isEmpty {
            text += " Spell these terms exactly: \(vocabulary.prefix(100).joined(separator: ", "))."
        }
        return text
    }
}

struct GeminiRewriter: TextRewriter {
    let apiKey: String
    let model: String

    var provider: AIProvider { .gemini }
    var displayName: String { "Gemini · \(model)" }

    func rewrite(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload {
        guard !apiKey.isEmpty else { throw ProviderError.missingKey(.gemini) }
        let start = Date()
        let body: [String: Any] = [
            "model": model,
            "system_instruction": systemPrompt,
            "input": RewritePrompts.userMessage(for: inputText),
            "generation_config": [
                "thinking_level": GeminiAPI.lowestThinkingLevel(for: model),
                "max_output_tokens": 8192,
            ],
            "store": false,
        ]
        let data = try await HTTPTransport.send(try GeminiAPI.request(apiKey: apiKey, body: body), provider: .gemini)
        let json = try HTTPTransport.json(data, provider: .gemini)
        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: RewriteOutput.clean(GeminiAPI.outputText(from: json)),
            latency: Date().timeIntervalSince(start)
        )
    }
}
