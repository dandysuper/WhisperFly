import Foundation
import AVFoundation

actor NIMCanaryRecognizer: SpeechRecognizer {
    private let apiKey: String
    private let language: String
    private let endpoint = URL(string: "https://ai.api.nvidia.com/v1/asr/nvidia/canary-1b-asr")!

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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let config: [String: Any] = [
            "languages": [language],
            "model": "canary-1b-asr",
            "punctuation": true
        ]
        let configJSON = try JSONSerialization.data(withJSONObject: config)
        let configString = String(data: configJSON, encoding: .utf8)!

        var body = Data()
        // Config field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"config\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(configString.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        // Audio file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WhisperFly", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "WhisperFly", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "NIM API error (\(httpResponse.statusCode)): \(errorBody)"])
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
