import Foundation

/// The OpenAI-shaped endpoints shared by Groq, OpenRouter and custom servers:
/// `POST /audio/transcriptions` and `POST /chat/completions`.
enum OpenAICompatibleAPI {

    // MARK: - Speech to text

    struct TranscriptionRequest {
        var baseURL: URL
        var apiKey: String
        var model: String
        var language: DictationLanguage
        /// Whisper's `prompt` field: style and spelling hints, ≤ 224 tokens.
        var prompt: String?
        /// `verbose_json` returns per-segment `no_speech_prob`, which is how
        /// silence that Whisper "heard" as words gets filtered out.
        var verbose: Bool
        var provider: AIProvider
    }

    static func transcribe(_ request: TranscriptionRequest, audio: PreparedAudio) async throws -> String {
        var form = MultipartForm()
        form.field("model", request.model)
        if let code = request.language.whisperCode {
            form.field("language", code)
        }
        if let prompt = request.prompt?.trimmed, !prompt.isEmpty {
            form.field("prompt", prompt)
        }
        form.field("response_format", request.verbose ? "verbose_json" : "json")
        form.field("temperature", "0")
        form.file("file", fileName: audio.fileName, mimeType: audio.mimeType, data: try audio.data())

        var urlRequest = URLRequest(url: request.baseURL.appendingPathComponent("audio/transcriptions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 180
        if !request.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = form.finish()

        let data = try await HTTPTransport.send(urlRequest, provider: request.provider)
        let json = try HTTPTransport.json(data, provider: request.provider)
        return spokenText(from: json)
    }

    /// The transcript, minus segments Whisper itself flags as probably silent.
    ///
    /// Uses Whisper's own skip rule: a segment is dropped when
    /// `no_speech_prob > 0.6` *and* `avg_logprob < -1`.
    static func spokenText(from json: [String: Any]) -> String {
        guard let segments = json["segments"] as? [[String: Any]], !segments.isEmpty else {
            return (json["text"] as? String ?? "").trimmed
        }
        let kept = segments.filter { segment in
            let noSpeech = (segment["no_speech_prob"] as? NSNumber)?.doubleValue ?? 0
            let logProb = (segment["avg_logprob"] as? NSNumber)?.doubleValue ?? 0
            return !(noSpeech > 0.6 && logProb < -1)
        }
        if kept.count == segments.count {
            return (json["text"] as? String ?? "").trimmed
        }
        return kept.compactMap { $0["text"] as? String }.joined().trimmed
    }

    /// Builds Whisper's `prompt` from the vocabulary list.
    ///
    /// Whisper reads the prompt as preceding text, so a short, natural sentence
    /// listing the terms works better than bare keywords. Capped well under the
    /// 224-token limit.
    static func whisperPrompt(vocabulary: [String]) -> String? {
        guard !vocabulary.isEmpty else { return nil }
        var prompt = "Vocabulary: "
        for term in vocabulary {
            let next = prompt + term + ", "
            if next.count > 600 { break }
            prompt = next
        }
        return String(prompt.dropLast(2)) + "."
    }

    // MARK: - Chat completions

    struct ChatRequest {
        var baseURL: URL
        var apiKey: String
        var model: String
        var systemPrompt: String
        var userMessage: String
        var provider: AIProvider
        /// Provider-specific body fields (reasoning controls, etc.).
        var extraBody: [String: Any] = [:]
        var extraHeaders: [String: String] = [:]
    }

    static func complete(_ request: ChatRequest) async throws -> String {
        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userMessage],
            ],
            "stream": false,
        ]
        for (key, value) in request.extraBody { body[key] = value }

        var urlRequest = URLRequest(url: request.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        if !request.apiKey.isEmpty {
            urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in request.extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await HTTPTransport.send(urlRequest, provider: request.provider)
        let json = try HTTPTransport.json(data, provider: request.provider)
        return messageContent(from: json)
    }

    /// `choices[0].message.content`, accepting both the string and the
    /// content-parts array forms.
    static func messageContent(from json: [String: Any]) -> String {
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return "" }
        if let text = message["content"] as? String { return text }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }
}
