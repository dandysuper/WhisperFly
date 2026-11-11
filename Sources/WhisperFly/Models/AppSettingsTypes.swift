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

    /// How dictated text reaches the focused app.
    enum InsertionMethod: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Write through the Accessibility API, fall back to paste.
        case automatic
        /// Always paste with ⌘V. Works in apps (Electron, some browsers) that
        /// accept Accessibility writes without actually applying them.
        case paste

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .automatic: return L("insertion.automatic", "Automatic")
            case .paste:     return L("insertion.paste", "Always paste (⌘V)")
            }
        }
    }

    /// The global shortcut that starts and stops recording.
    ///
    /// `fn` is the Fn / 🌐 key on its own and always dictates from the
    /// microphone; it is watched by `FnKeyMonitor`. The other cases carry the
    /// Carbon key code and modifier mask `HotkeyMonitor` registers, and record
    /// from the selected audio source — they exist for keyboards without Fn.
    enum HotkeyPreset: String, Codable, Sendable, CaseIterable, Identifiable {
        case fn
        case commandShiftSpace
        case controlOptionSpace
        case commandOptionSpace
        case controlShiftSpace
        case optionSpace

        var id: String { rawValue }

        /// `true` for the Fn key, which Carbon cannot register.
        var isFunctionKey: Bool { self == .fn }

        /// Virtual key code for the space bar (`kVK_Space`).
        var keyCode: UInt32 { UInt32(kVK_Space) }

        var carbonModifiers: UInt32 {
            switch self {
            case .fn:                 return 0
            case .commandShiftSpace:  return UInt32(cmdKey | shiftKey)
            case .controlOptionSpace: return UInt32(controlKey | optionKey)
            case .commandOptionSpace: return UInt32(cmdKey | optionKey)
            case .controlShiftSpace:  return UInt32(controlKey | shiftKey)
            case .optionSpace:        return UInt32(optionKey)
            }
        }

        var displayName: String {
            switch self {
            case .fn:                 return "fn"
            case .commandShiftSpace:  return "⌘⇧Space"
            case .controlOptionSpace: return "⌃⌥Space"
            case .commandOptionSpace: return "⌘⌥Space"
            case .controlShiftSpace:  return "⌃⇧Space"
            case .optionSpace:        return "⌥Space"
            }
        }

        /// Individual key caps for the shortcut badge, e.g. `["⌘", "⇧", "Space"]`.
        var keyCaps: [String] {
            switch self {
            case .fn:                 return ["fn"]
            case .commandShiftSpace:  return ["⌘", "⇧", "Space"]
            case .controlOptionSpace: return ["⌃", "⌥", "Space"]
            case .commandOptionSpace: return ["⌘", "⌥", "Space"]
            case .controlShiftSpace:  return ["⌃", "⇧", "Space"]
            case .optionSpace:        return ["⌥", "Space"]
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
            case "⌥Space":                     return .optionSpace
            case "Fn", "🌐", "globe":           return .fn
            default:                           return nil
            }
        }
    }
}
