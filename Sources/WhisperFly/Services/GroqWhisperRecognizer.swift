import Foundation
import AVFoundation

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
        
        let wavURL = try convertToWAV(audioURL)
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
    
    private func convertToWAV(_ cafURL: URL) throws -> URL {
        let wavURL = cafURL.deletingPathExtension().appendingPathExtension("wav")
        let inputFile = try AVAudioFile(forReading: cafURL)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        
        let frameCount = AVAudioFrameCount(inputFile.length)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "WhisperFly", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }
        try inputFile.read(into: inputBuffer)
        
        let outputBuffer: AVAudioPCMBuffer
        if inputFile.processingFormat == targetFormat {
            outputBuffer = inputBuffer
        } else {
            guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: targetFormat) else {
                throw NSError(domain: "WhisperFly", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio format conversion not possible"])
            }
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                throw NSError(domain: "WhisperFly", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
            }
            try converter.convert(to: converted, from: inputBuffer)
            outputBuffer = converted
        }
        
        let outputFile = try AVAudioFile(forWriting: wavURL, settings: targetFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try outputFile.write(from: outputBuffer)
        return wavURL
    }
}
