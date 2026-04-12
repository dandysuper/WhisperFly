import Foundation
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "History")

struct TranscriptionEntry: Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case microphone
        case systemAudio
        case file
    }

    let id: UUID
    let date: Date
    let text: String
    let source: Source
    /// Original filename for file transcriptions
    let fileName: String?
    let latency: TimeInterval

    init(text: String, source: Source, fileName: String? = nil, latency: TimeInterval = 0) {
        self.id = UUID()
        self.date = Date()
        self.text = text
        self.source = source
        self.fileName = fileName
        self.latency = latency
    }

    var sourceIcon: String {
        switch source {
        case .microphone:  return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .file:        return "doc.fill"
        }
    }

    var sourceLabel: String {
        switch source {
        case .microphone:  return L("history.source.mic", "Microphone")
        case .systemAudio: return L("history.source.system", "System Audio")
        case .file:        return fileName ?? L("history.source.file", "File")
        }
    }
}

@MainActor
final class TranscriptionHistory: ObservableObject {
    @Published private(set) var entries: [TranscriptionEntry] = []
    private let key = "whisperfly_history"
    private let maxEntries = 100

    init() {
        load()
    }

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        log.info("History: added entry (\(entry.source.rawValue)), total=\(self.entries.count)")
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
