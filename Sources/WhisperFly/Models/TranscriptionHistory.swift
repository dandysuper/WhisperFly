import Foundation
import SwiftUI
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "History")

/// One finished transcription.
///
/// Decoded by hand for the same reason as `AppSettings`: Swift's synthesised
/// decoder throws on a missing key even when the property has a default, so
/// adding a field here would otherwise make the stored history undecodable.
/// The difference that matters here is scope — a single unreadable entry would
/// throw for the whole array and discard every transcription the user ever made,
/// which is why `TranscriptionHistory` also decodes entry by entry.
struct TranscriptionEntry: Codable, Identifiable, Sendable {

    enum Source: String, Codable, Sendable, CaseIterable {
        case microphone
        case systemAudio
        case file

        /// Maps raw values written by earlier releases.
        static func fromPersisted(_ raw: String) -> Source? {
            if let value = Source(rawValue: raw) { return value }
            switch raw.lowercased() {
            case "microphone":            return .microphone
            case "systemaudio", "system": return .systemAudio
            case "file":                  return .file
            default:                      return nil
            }
        }
    }

    let id: UUID
    let date: Date
    let text: String
    let source: Source
    /// Original filename for file transcriptions.
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

    private enum CodingKeys: String, CodingKey {
        case id, date, text, source, fileName, latency
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decode(container, .id, fallback: UUID())
        date = Self.decode(container, .date, fallback: Date())
        text = Self.decode(container, .text, fallback: "")
        fileName = (try? container.decodeIfPresent(String.self, forKey: .fileName)) ?? nil
        latency = Self.decode(container, .latency, fallback: 0)

        let rawSource = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? nil
        source = rawSource.flatMap(Source.fromPersisted) ?? .microphone
    }

    private static func decode<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        fallback: T
    ) -> T {
        guard let value = try? container.decodeIfPresent(T.self, forKey: key) else { return fallback }
        return value
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
    private let corruptBackupKey = "whisperfly_history_corrupt_backup"
    private let maxEntries = 100
    private let defaults: UserDefaults

    /// `defaults` exists so tests can run against an isolated suite; production
    /// callers always use the standard defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        log.info("History: added entry (\(entry.source.rawValue, privacy: .public)), total=\(self.entries.count)")
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    /// Decodes every readable entry and drops only the ones that cannot be read.
    ///
    /// The previous implementation decoded the array as a whole, so one entry
    /// written by an older or newer build took the entire history down with it —
    /// silently, because the failure was swallowed by `try?`.
    private func load() {
        guard let data = defaults.data(forKey: key) else { return }

        do {
            let wrapped = try JSONDecoder().decode([LossyEntry].self, from: data)
            entries = wrapped.compactMap(\.entry)
            let dropped = wrapped.count - entries.count
            if dropped > 0 {
                log.warning("History: skipped \(dropped) unreadable entr(ies)")
                save()
            }
        } catch {
            // Not even an array: keep the bytes so the failure is diagnosable.
            log.error("History could not be decoded: \(error.localizedDescription, privacy: .public)")
            defaults.set(data, forKey: corruptBackupKey)
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: key)
        } catch {
            log.error("History could not be encoded: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Wrapper that turns a failing element into `nil` instead of failing the array.
    private struct LossyEntry: Decodable {
        let entry: TranscriptionEntry?

        init(from decoder: any Decoder) throws {
            entry = try? TranscriptionEntry(from: decoder)
        }
    }
}
