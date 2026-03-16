import Foundation
import AVFoundation

final class AudioCaptureService: NSObject, AudioCapturing, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onMaxDurationReached: (@Sendable () -> Void)?
    
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var durationTask: Task<Void, Never>?
    private var recordingURL: URL?
    private var maxDuration: TimeInterval = 120
    
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
        let url = recordingsDir.appendingPathComponent("\(UUID().uuidString).caf")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        
        guard rec.record() else {
            throw NSError(domain: "WhisperFly", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }
        
        self.recorder = rec
        self.recordingURL = url
        
        await MainActor.run {
            self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                let level = rec.averagePower(forChannel: 0)
                self.onAudioLevel?(level)
            }
        }
        
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
        
        await MainActor.run {
            meterTimer?.invalidate()
            meterTimer = nil
        }
        
        guard let rec = recorder, let url = recordingURL else {
            throw NSError(domain: "WhisperFly", code: 11, userInfo: [NSLocalizedDescriptionKey: "No active recording"])
        }
        
        rec.stop()
        recorder = nil
        recordingURL = nil
        
        return url
    }
    
    func cancelRecording() async {
        durationTask?.cancel()
        durationTask = nil
        
        await MainActor.run {
            meterTimer?.invalidate()
            meterTimer = nil
        }
        
        recorder?.stop()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        recordingURL = nil
    }
}
