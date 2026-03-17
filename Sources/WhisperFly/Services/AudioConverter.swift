import Foundation
import AVFoundation

/// Shared utility for converting audio files to 16 kHz mono PCM WAV,
/// which is the format expected by all speech-recognition backends.
enum AudioConverter {
    static func convertToWAV(_ inputURL: URL) throws -> URL {
        let wavURL = inputURL.deletingPathExtension().appendingPathExtension("wav")
        let inputFile = try AVAudioFile(forReading: inputURL)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        let frameCount = AVAudioFrameCount(inputFile.length)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw NSError(domain: "WhisperFly", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }
        try inputFile.read(into: inputBuffer)

        let outputBuffer: AVAudioPCMBuffer
        if inputFile.processingFormat == targetFormat {
            outputBuffer = inputBuffer
        } else {
            guard let converter = AVAudioConverter(
                from: inputFile.processingFormat,
                to: targetFormat
            ) else {
                throw NSError(domain: "WhisperFly", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Audio format conversion not possible"])
            }
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else {
                throw NSError(domain: "WhisperFly", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
            }
            try converter.convert(to: converted, from: inputBuffer)
            outputBuffer = converted
        }

        let outputFile = try AVAudioFile(
            forWriting: wavURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try outputFile.write(from: outputBuffer)
        return wavURL
    }
}
