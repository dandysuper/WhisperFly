import Foundation

actor GroqWhisperRecognizer: SpeechRecognizer {
    private let apiKey: String
    private let language: String
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3"
    
    init(apiKey: String, language: String = "ru") {
        self.apiKey = apiKey
        self.language = language
    }
    
    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload {
        let start = CFAbsoluteTimeGetCurrent()
        
        let wavURL = try AudioConverter.convertToWAV(audioURL)
        defer { try? FileManager.default.removeItem(at: wavURL) }
        
        let audioData = try Data(contentsOf: wavURL)
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("model", model)
        appendField("language", language)
        appendField("response_format", "json")
        appendField("temperature", "0")
        
        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WhisperFly", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Groq"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "WhisperFly", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Groq API error (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = json?["text"] as? String ?? ""
        
        let latency = CFAbsoluteTimeGetCurrent() - start
        return TranscriptionResultPayload(text: text.trimmingCharacters(in: .whitespacesAndNewlines), latency: latency, audioURL: audioURL)
    }
    
}
