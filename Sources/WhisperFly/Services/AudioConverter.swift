import Foundation
@preconcurrency import AVFoundation

/// An audio file ready to upload, plus what the pipeline learned while making it.
struct PreparedAudio: Sendable {
    let url: URL
    /// MIME type for the upload, e.g. `audio/wav`.
    let mimeType: String
    /// Short container name some APIs want instead of a MIME type (`wav`, `m4a`).
    let format: String
    let byteCount: Int
    let duration: TimeInterval
    /// Loudest sample in dBFS. Below roughly -55 dBFS nothing audible was captured.
    let peakDBFS: Float

    var fileName: String { "audio.\(format)" }

    func data() throws -> Data { try Data(contentsOf: url) }
}

/// Converts any recording or media file into what the speech APIs accept.
///
/// The previous converter read the whole file into one PCM buffer and handed the
/// same buffer to `AVAudioConverter` on every input callback, so a long file
/// could need gigabytes of memory and the resampler could see the audio twice.
/// This version streams in fixed-size chunks and signals end-of-stream
/// properly. It also measures the peak level on the way through, which lets the
/// pipeline skip the network round trip for a silent recording.
enum AudioConverter {

    static let speechSampleRate: Double = 16_000

    /// Supported file extensions for the "Transcribe File" picker.
    static let supportedAudioExtensions = ["mp3", "wav", "m4a", "aac", "ogg", "flac", "caf", "aiff", "aif", "wma", "opus", "webm"]
    static let supportedVideoExtensions = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "ts"]

    private static var workDirectory: URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperFly", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Public entry points

    /// Produces a 16 kHz mono 16-bit WAV from any audio or video file.
    ///
    /// The result always lives in a fresh temporary file the caller owns; the
    /// input is never modified or deleted.
    static func prepareWAV(from inputURL: URL) async throws -> PreparedAudio {
        var readable = inputURL
        var extracted: URL?
        if (try? AVAudioFile(forReading: inputURL)) == nil {
            // Video containers and formats Core Audio cannot open directly go
            // through AVFoundation's exporter first.
            let url = try await extractAudioTrack(from: inputURL)
            readable = url
            extracted = url
        }
        defer { if let extracted { try? FileManager.default.removeItem(at: extracted) } }

        let output = workDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: speechSampleRate, channels: 1, interleaved: true)!
        let stats = try transcode(readable, to: output, settings: format.settings)
        return PreparedAudio(
            url: output,
            mimeType: "audio/wav",
            format: "wav",
            byteCount: fileSize(output),
            duration: stats.duration,
            peakDBFS: stats.peakDBFS
        )
    }

    /// Re-encodes `audio` as 16 kHz mono AAC, roughly 8× smaller than WAV, for
    /// providers with an upload limit a long recording would exceed.
    static func compressToAAC(_ audio: PreparedAudio) async throws -> PreparedAudio {
        let output = workDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: speechSampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let stats = try transcode(audio.url, to: output, settings: settings)
        return PreparedAudio(
            url: output,
            mimeType: "audio/m4a",
            format: "m4a",
            byteCount: fileSize(output),
            duration: stats.duration,
            peakDBFS: audio.peakDBFS
        )
    }

    // MARK: - Streaming conversion

    private struct Stats {
        var duration: TimeInterval
        var peakDBFS: Float
    }

    private static func transcode(
        _ inputURL: URL,
        to outputURL: URL,
        settings: [String: Any]
    ) throws -> Stats {
        let input = try AVAudioFile(forReading: inputURL)
        let inputFormat = input.processingFormat
        // Mono float at the speech rate is what the analysis and both encoders want.
        guard let monoFloat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: speechSampleRate, channels: 1, interleaved: false) else {
            throw conversionError(3, "Audio format conversion not possible")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: monoFloat) else {
            throw conversionError(3, "Audio format conversion not possible")
        }

        let output = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let chunkFrames: AVAudioFrameCount = 16_384
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkFrames) else {
            throw conversionError(2, "Failed to create input buffer")
        }
        let ratio = speechSampleRate / inputFormat.sampleRate
        let outCapacity = AVAudioFrameCount((Double(chunkFrames) * ratio).rounded(.up)) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: monoFloat, frameCapacity: outCapacity) else {
            throw conversionError(4, "Failed to create output buffer")
        }

        var peak: Float = 0
        var framesWritten: AVAudioFramePosition = 0
        var reachedEnd = false
        var readError: Error?

        while true {
            outBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
                if reachedEnd {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    readBuffer.frameLength = 0
                    try input.read(into: readBuffer, frameCount: chunkFrames)
                } catch {
                    readError = error
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if readBuffer.frameLength == 0 {
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return readBuffer
            }
            if let conversionError { throw conversionError }
            if let readError { throw readError }

            if outBuffer.frameLength > 0, let samples = outBuffer.floatChannelData?[0] {
                for index in 0..<Int(outBuffer.frameLength) {
                    let magnitude = abs(samples[index])
                    if magnitude > peak { peak = magnitude }
                }
                try output.write(from: outBuffer)
                framesWritten += AVAudioFramePosition(outBuffer.frameLength)
            }

            if status == .endOfStream || status == .error { break }
            if status == .inputRanDry && reachedEnd { break }
        }

        let peakDB: Float = peak > 0 ? 20 * log10(peak) : -160
        return Stats(duration: Double(framesWritten) / speechSampleRate, peakDBFS: peakDB)
    }

    // MARK: - Video / exotic containers

    private static func extractAudioTrack(from inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard try await asset.load(.isReadable) else {
            throw conversionError(40, L("audio.error.unreadable", "This file cannot be read."))
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw conversionError(41, L("audio.error.no_track", "This file has no audio track."))
        }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw conversionError(42, "Cannot create audio export session")
        }

        let outputURL = workDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        await exportSession.export()

        guard exportSession.status == .completed else {
            let message = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw conversionError(43, L("audio.error.extract", "Audio extraction failed: %@", message))
        }
        return outputURL
    }

    // MARK: - Helpers

    private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func conversionError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "WhisperFly", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
