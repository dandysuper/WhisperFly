import Foundation

actor GeminiTranscriber: SpeechRecognizer {
    private let apiKey: String
    private let language: String
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "google/gemini-2.5-flash-preview-05-20:free"
    
    init(apiKey: String, language: String = "ru") {
        self.apiKey = apiKey
        self.language = language
    }
    
    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload {
        let start = CFAbsoluteTimeGetCurrent()
        
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        
        let systemPrompt = "You are a speech transcription assistant. Transcribe the audio exactly as spoken. The audio is likely in \(language). Output ONLY the transcribed text, nothing else. No explanations, no formatting, no quotes."
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    [
                        "type": "input_audio",
                        "input_audio": [
                            "data": base64Audio,
                            "format": "wav"
                        ]
                    ],
                    [
                        "type": "text",
                        "text": "Transcribe this audio exactly as spoken."
                    ]
                ]]
            ]
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
            throw NSError(domain: "WhisperFly", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenRouter API error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        
        let latency = CFAbsoluteTimeGetCurrent() - start
        return TranscriptionResultPayload(text: text.trimmingCharacters(in: .whitespacesAndNewlines), latency: latency, audioURL: audioURL)
    }
}
