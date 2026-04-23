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

    // State shared between audioQueue (callback) and caller context.
    // Access ONLY while holding `stateLock`.
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
        self.maxDuration = TimeInterval(maxRecordingSeconds)
    }

    func startRecording() async throws -> URL {
        // Clean up any leftover state from a previous failed attempt.
        await resetState()

        let url = recordingsDir.appendingPathComponent("\(UUID().uuidString).m4a")

        // Get available content — throws if Screen Recording permission is not granted
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw NSError(
                domain: "WhisperFly", code: 30,
                userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission required for system audio capture. Grant it in System Settings → Privacy & Security → Screen Recording."]
            )
        }

        guard let display = content.displays.first else {
            throw NSError(
                domain: "WhisperFly", code: 31,
                userInfo: [NSLocalizedDescriptionKey: "No display found for audio capture"]
            )
        }

        // Configure stream: audio-only, minimal video
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1
        // Minimize video overhead (ScreenCaptureKit requires video stream)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // Capture audio from all applications on this display
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Setup AVAssetWriter → M4A (AAC)
        let writer = try AVAssetWriter(url: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        guard writer.startWriting() else {
            let desc = writer.error?.localizedDescription ?? "Unknown writer error"
            throw NSError(
                domain: "WhisperFly", code: 33,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start audio writer: \(desc)"]
            )
        }

        stateLock.lock()
        self.assetWriter = writer
        self.audioInput = input
        self.sessionStarted = false
        stateLock.unlock()

        self.recordingURL = url

        // Create and start ScreenCaptureKit stream
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try await scStream.startCapture()
        } catch {
            // Clean up writer state so the next attempt starts fresh.
            stateLock.lock()
            let lockedInput = audioInput
            let lockedWriter = assetWriter
            self.audioInput = nil
            self.assetWriter = nil
            self.sessionStarted = false
            stateLock.unlock()

            lockedInput?.markAsFinished()
            lockedWriter?.cancelWriting()
            self.recordingURL = nil

            throw NSError(
                domain: "WhisperFly", code: 30,
                userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission required for system audio capture. Grant it in System Settings → Privacy & Security → Screen Recording."]
            )
        }
        self.stream = scStream

        log.info("System audio capture started → \(url.lastPathComponent)")

        // Max duration timer
        durationTask = Task { [weak self, maxDuration] in
            try? await Task.sleep(for: .seconds(maxDuration))
            guard !Task.isCancelled else { return }
            self?.onMaxDurationReached?()
        }

        return url
    }

    func stopRecording() async throws -> URL {
        durationTask?.cancel()
        durationTask = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        // Drain audioQueue so all pending callbacks complete before cleanup.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async { continuation.resume() }
        }

        // Now safe to tear down the writer — no more callbacks can fire.
        stateLock.lock()
        let input = audioInput
        let writer = assetWriter
        self.audioInput = nil
        self.assetWriter = nil
        self.sessionStarted = false
        stateLock.unlock()

        input?.markAsFinished()
        if let writer, writer.status == .writing {
            await writer.finishWriting()
        }

        guard let url = recordingURL else {
            throw NSError(
                domain: "WhisperFly", code: 32,
                userInfo: [NSLocalizedDescriptionKey: "No active system audio recording"]
            )
        }
        recordingURL = nil

        log.info("System audio capture stopped → \(url.lastPathComponent)")
        return url
    }

    func cancelRecording() async {
        durationTask?.cancel()
        durationTask = nil

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil

        // Drain audioQueue so all pending callbacks complete before cleanup.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async { continuation.resume() }
        }

        stateLock.lock()
        let input = audioInput
        let writer = assetWriter
        self.audioInput = nil
        self.assetWriter = nil
        self.sessionStarted = false
        stateLock.unlock()

        input?.markAsFinished()
        if let writer, writer.status == .writing {
            await writer.finishWriting()
        }

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    /// Tears down any leftover stream/writer state from a previous attempt.
    private func resetState() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                audioQueue.async { continuation.resume() }
            }
        }

        stateLock.lock()
        let input = audioInput
        let writer = assetWriter
        self.audioInput = nil
        self.assetWriter = nil
        self.sessionStarted = false
        stateLock.unlock()

        input?.markAsFinished()
        if let writer, writer.status == .writing {
            writer.cancelWriting()
        }

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        durationTask?.cancel()
        durationTask = nil
    }

    // MARK: - Audio Level Metering

    private func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return -160 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &length, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, length > 0 else { return -160 }

        // ScreenCaptureKit delivers Float32 LPCM
        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return -160 }

        return dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            var sum: Float = 0
            for i in 0..<floatCount {
                let sample = floats[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(floatCount))
            return 20 * log10(max(rms, 1e-7))
        }
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        log.error("SCStream stopped with error: \(error.localizedDescription)")
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Audio level metering (read-only on the buffer, no shared state)
        let level = calculateAudioLevel(from: sampleBuffer)
        onAudioLevel?(level)

        // Safely snapshot shared state under the lock.
        stateLock.lock()
        let writer = assetWriter
        let input = audioInput
        let started = sessionStarted
        stateLock.unlock()

        guard let writer, let input else { return }

        // Start asset writer session with first sample's timestamp
        if !started {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            stateLock.lock()
            sessionStarted = true
            stateLock.unlock()
        }

        // Write audio to file
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
}
