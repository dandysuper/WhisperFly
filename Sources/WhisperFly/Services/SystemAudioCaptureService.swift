import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "SystemAudio")

final class SystemAudioCaptureService: NSObject, AudioCapturing, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onMaxDurationReached: (@Sendable () -> Void)?

    private var stream: SCStream?
    private var recordingURL: URL?
    private var durationTask: Task<Void, Never>?
    private var maxDuration: TimeInterval = 300
    private let audioQueue = DispatchQueue(label: "com.whisperfly.systemaudio")

    // State shared between the caller context and ScreenCaptureKit callback queue.
    private let stateLock = NSLock()
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false

    private let recordingsDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperFly/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func configure(maxRecordingSeconds: Int) {
        maxDuration = TimeInterval(maxRecordingSeconds)
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    func startRecording() async throws -> URL {
        await resetState(deleteRecording: true)

        let url = recordingsDir.appendingPathComponent("\(UUID().uuidString).m4a")

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw screenRecordingPermissionError()
        }

        guard let display = content.displays.first else {
            throw NSError(
                domain: "WhisperFly",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "No display found for audio capture"]
            )
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // ScreenCaptureKit requires a display-backed stream even for audio-only use.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let writer = try AVAssetWriter(url: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw NSError(
                domain: "WhisperFly",
                code: 34,
                userInfo: [NSLocalizedDescriptionKey: "Failed to configure audio writer input for system audio capture."]
            )
        }
        writer.add(input)

        guard writer.startWriting() else {
            let desc = writer.error?.localizedDescription ?? "Unknown writer error"
            throw NSError(
                domain: "WhisperFly",
                code: 33,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start audio writer: \(desc)"]
            )
        }

        withStateLock {
            assetWriter = writer
            audioInput = input
            sessionStarted = false
        }
        recordingURL = url

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try await scStream.startCapture()
        } catch {
            await resetState(deleteRecording: true)

            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain,
               let code = SCStreamError.Code(rawValue: nsError.code),
               code == .userDeclined {
                throw screenRecordingPermissionError()
            }
            throw NSError(
                domain: "WhisperFly",
                code: 35,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start system audio capture: \(nsError.localizedDescription)"]
            )
        }

        stream = scStream
        log.info("System audio capture started -> \(url.lastPathComponent)")

        durationTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: .seconds(maxDuration))
            guard !Task.isCancelled else { return }
            self?.onMaxDurationReached?()
        }

        return url
    }

    func stopRecording() async throws -> URL {
        let url = try await finishCapture(deleteRecording: false)
        log.info("System audio capture stopped -> \(url.lastPathComponent)")
        return url
    }

    func cancelRecording() async {
        _ = try? await finishCapture(deleteRecording: true)
    }

    private func finishCapture(deleteRecording: Bool) async throws -> URL {
        durationTask?.cancel()
        durationTask = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        await drainAudioQueue()

        let (writer, input, didStartSession) = takeWriterState()

        if let input {
            input.markAsFinished()
        }

        if let writer {
            switch writer.status {
            case .writing:
                if didStartSession {
                    await writer.finishWriting()
                } else {
                    writer.cancelWriting()
                }
            case .unknown:
                writer.cancelWriting()
            default:
                break
            }
        }

        guard let url = recordingURL else {
            throw NSError(
                domain: "WhisperFly",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "No active system audio recording"]
            )
        }
        recordingURL = nil

        if deleteRecording {
            try? FileManager.default.removeItem(at: url)
        }

        if !deleteRecording && !didStartSession {
            try? FileManager.default.removeItem(at: url)
            throw NSError(
                domain: "WhisperFly",
                code: 36,
                userInfo: [NSLocalizedDescriptionKey: "No system audio samples were captured. Check Screen Recording permission and try again."]
            )
        }

        return url
    }

    private func resetState(deleteRecording: Bool) async {
        durationTask?.cancel()
        durationTask = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        await drainAudioQueue()

        let (writer, input, _) = takeWriterState()

        if let input {
            input.markAsFinished()
        }

        if let writer {
            switch writer.status {
            case .writing, .unknown:
                writer.cancelWriting()
            default:
                break
            }
        }

        if deleteRecording, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func takeWriterState() -> (writer: AVAssetWriter?, input: AVAssetWriterInput?, sessionStarted: Bool) {
        withStateLock {
            let writer = assetWriter
            let input = audioInput
            let didStartSession = sessionStarted
            assetWriter = nil
            audioInput = nil
            sessionStarted = false
            return (writer, input, didStartSession)
        }
    }

    private func drainAudioQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async {
                continuation.resume()
            }
        }
    }

    private func screenRecordingPermissionError() -> NSError {
        NSError(
            domain: "WhisperFly",
            code: 30,
            userInfo: [
                NSLocalizedDescriptionKey: "Screen Recording permission required for system audio capture. Grant it in System Settings -> Privacy & Security -> Screen Recording."
            ]
        )
    }

    private func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return -160
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else {
            return -160
        }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return -160 }

        return dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            var sum: Float = 0
            for index in 0..<floatCount {
                let sample = floats[index]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(floatCount))
            return 20 * log10(max(rms, 1e-7))
        }
    }
}

extension SystemAudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let nsError = error as NSError
        log.error("SCStream stopped with error: \(nsError.localizedDescription)")
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let level = calculateAudioLevel(from: sampleBuffer)
        onAudioLevel?(level)

        let (writer, input, didStartSession) = withStateLock {
            (assetWriter, audioInput, sessionStarted)
        }

        guard let writer, let input else { return }

        if !didStartSession {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)

            withStateLock {
                sessionStarted = true
            }
        }

        if input.isReadyForMoreMediaData && !input.append(sampleBuffer) {
            let description = writer.error?.localizedDescription ?? "Unknown writer error"
            log.error("Failed to append system audio sample: \(description)")
        }
    }
}
