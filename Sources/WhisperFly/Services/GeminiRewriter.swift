import Foundation

actor GeminiRewriter: TextRewriter {
    private let apiKey: String
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "google/gemini-2.5-flash-preview-05-20:free"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func rewrite(inputText: String, locale: Locale, mode: RewriteMode) async throws -> RewriteResultPayload {
        let start = CFAbsoluteTimeGetCurrent()
        
        let systemPrompt = Self.systemPrompt(for: mode, locale: locale)
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": inputText]
            ],
            "temperature": 0.2,
            "top_p": 0.95,
            "max_tokens": 1024
        ]
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WhisperFly/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("WhisperFly", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WhisperFly", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from OpenRouter"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "WhisperFly", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenRouter rewrite error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let rewritten = message?["content"] as? String ?? inputText
        
        let latency = CFAbsoluteTimeGetCurrent() - start
        return RewriteResultPayload(
            sourceText: inputText,
            rewrittenText: rewritten.trimmingCharacters(in: .whitespacesAndNewlines),
            latency: latency
        )
    }
    
    private static func systemPrompt(for mode: RewriteMode, locale: Locale) -> String {
        switch mode {
        case .cleanup:
            return """
            You are a text cleanup assistant. Fix grammar, punctuation, and formatting of the following dictated text. \
            Keep the original language. Do NOT translate. Do NOT add explanations. \
            Output ONLY the cleaned-up text.
            """
        case .punctuate:
            return """
            You are a punctuation assistant. Add proper punctuation and capitalization to the following dictated text. \
            Do NOT change any words. Do NOT translate. Do NOT add explanations. \
            Output ONLY the punctuated text.
            """
        case .translate:
            return """
            You are a translation assistant. Translate the following text to English. \
            Output ONLY the translated text. No explanations, no original text.
            """
        }
    }
}
