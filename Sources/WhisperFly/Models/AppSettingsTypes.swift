import Foundation
import Carbon.HIToolbox

extension AppSettings {

    /// Which input the app records from.
    ///
    /// The raw values are stable identifiers, not labels. They used to *be* the
    /// labels (`"Microphone"`, `"System Audio"`), which meant that renaming a
    /// label either changed what was persisted or broke decoding for every
    /// existing install.
    enum AudioSource: String, Codable, Sendable, CaseIterable, Identifiable {
        case microphone
        case systemAudio

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .microphone:  return L("audio_source.microphone", "Microphone")
            case .systemAudio: return L("audio_source.system_audio", "System Audio")
            }
        }

        var systemImage: String {
            switch self {
            case .microphone:  return "mic.fill"
            case .systemAudio: return "speaker.wave.2.fill"
            }
        }

        /// Maps the label-as-raw-value strings written by earlier releases.
        static func fromPersisted(_ raw: String) -> AudioSource? {
            if let value = AudioSource(rawValue: raw) { return value }
            switch raw {
            case "Microphone":   return .microphone
            case "System Audio": return .systemAudio
            default:             return nil
            }
        }
    }

    /// Which speech-to-text service performs the transcription.
    enum TranscriptionBackend: String, Codable, Sendable, CaseIterable, Identifiable {
        case groqWhisper
        case gemini

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .groqWhisper: return L("backend.groq", "Groq Whisper (Free)")
            case .gemini:      return L("backend.gemini", "Gemini 2.5 Flash (OpenRouter)")
            }
        }

        /// Maps the display-string raw values used up to release 2.x, including
        /// the `NIM Canary` backend that no longer exists — an install that had
        /// it selected falls back to Groq rather than losing every other setting.
        static func fromPersisted(_ raw: String) -> TranscriptionBackend? {
            if let value = TranscriptionBackend(rawValue: raw) { return value }
            switch raw {
            case "Groq Whisper (Free)":                 return .groqWhisper
            case "Gemini 2.5 Flash (OpenRouter)":       return .gemini
            case "NIM Canary", "NVIDIA NIM Canary":     return .groqWhisper
            default:                                    return nil
            }
        }
    }

    /// The global shortcut that starts and stops recording.
    ///
    /// Each case carries the Carbon key code and modifier mask so registering the
    /// hotkey is driven entirely by the stored preference. Previously the
    /// preference existed in the UI but `HotkeyMonitor` hard-coded ⌘⇧Space, so
    /// changing the picker did nothing.
    enum HotkeyPreset: String, Codable, Sendable, CaseIterable, Identifiable {
        case commandShiftSpace
        case controlOptionSpace
        case commandOptionSpace
        case controlShiftSpace

        var id: String { rawValue }

        /// Virtual key code for the space bar (`kVK_Space`).
        var keyCode: UInt32 { UInt32(kVK_Space) }

        var carbonModifiers: UInt32 {
            switch self {
            case .commandShiftSpace:  return UInt32(cmdKey | shiftKey)
            case .controlOptionSpace: return UInt32(controlKey | optionKey)
            case .commandOptionSpace: return UInt32(cmdKey | optionKey)
            case .controlShiftSpace:  return UInt32(controlKey | shiftKey)
            }
        }

        var displayName: String {
            switch self {
            case .commandShiftSpace:  return "⌘⇧Space"
            case .controlOptionSpace: return "⌃⌥Space"
            case .commandOptionSpace: return "⌘⌥Space"
            case .controlShiftSpace:  return "⌃⇧Space"
            }
        }

        /// Maps the symbol-string raw values written by earlier releases.
        static func fromPersisted(_ raw: String) -> HotkeyPreset? {
            if let value = HotkeyPreset(rawValue: raw) { return value }
            switch raw {
            case "⌘⇧Space", "cmdShiftSpace":  return .commandShiftSpace
            case "⌃⌥Space", "ctrlOptSpace":   return .controlOptionSpace
            case "⌘⌥Space":                    return .commandOptionSpace
            case "⌃⇧Space":                    return .controlShiftSpace
            default:                           return nil
            }
        }
    }
}
