import SwiftUI

/// A cloud service WhisperFly can send audio or text to.
///
/// One enum covers both jobs (speech-to-text and the optional rewrite pass) so
/// the settings UI, key validation and fallback ordering all agree on what a
/// provider is. Raw values are persisted.
enum AIProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Groq's free developer tier: Whisper Large v3 (Turbo) and GPT-OSS / Qwen.
    case groq
    /// Google's Gemini API, called directly with an AI Studio key.
    case gemini
    /// Gemini (or any other model) through OpenRouter — the original backend.
    case openRouter
    /// Any OpenAI-compatible server: OpenAI itself, a local whisper.cpp server, …
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groq:       return "Groq"
        case .gemini:     return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .custom:     return L("provider.custom", "OpenAI-compatible")
        }
    }

    var shortName: String {
        switch self {
        case .groq:       return "Groq"
        case .gemini:     return "Gemini"
        case .openRouter: return "OpenRouter"
        case .custom:     return L("provider.custom_short", "Custom")
        }
    }

    var tagline: String {
        switch self {
        case .groq:
            return L("provider.groq.tagline", "Free · Whisper Large v3 Turbo · fastest")
        case .gemini:
            return L("provider.gemini.tagline", "Free tier · Gemini 3.5 Transcribe · smart formatting")
        case .openRouter:
            return L("provider.openrouter.tagline", "Gemini and other models through one key")
        case .custom:
            return L("provider.custom.tagline", "OpenAI, a local Whisper server, or any compatible API")
        }
    }

    var systemImage: String {
        switch self {
        case .groq:       return "bolt.fill"
        case .gemini:     return "sparkle"
        case .openRouter: return "arrow.triangle.branch"
        case .custom:     return "server.rack"
        }
    }

    var tint: Color {
        switch self {
        case .groq:       return .orange
        case .gemini:     return .blue
        case .openRouter: return .purple
        case .custom:     return .teal
        }
    }

    /// Where the user creates a key.
    var keyURL: URL? {
        switch self {
        case .groq:       return URL(string: "https://console.groq.com/keys")
        case .gemini:     return URL(string: "https://aistudio.google.com/apikey")
        case .openRouter: return URL(string: "https://openrouter.ai/keys")
        case .custom:     return nil
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .groq:       return "gsk_…"
        case .gemini:     return "AIza…"
        case .openRouter: return "sk-or-v1-…"
        case .custom:     return "sk-…"
        }
    }

    /// `true` when the free tier is enough for everyday dictation.
    var isFree: Bool {
        switch self {
        case .groq, .gemini: return true
        case .openRouter, .custom: return false
        }
    }

    // MARK: - Models

    var transcriptionModels: [ModelOption] {
        switch self {
        case .groq:
            return [
                ModelOption(id: "whisper-large-v3-turbo",
                            note: L("model.note.fastest_free", "Fastest · free")),
                ModelOption(id: "whisper-large-v3",
                            note: L("model.note.most_accurate", "Most accurate · free")),
            ]
        case .gemini:
            return [
                ModelOption(id: "gemini-3.5-transcribe",
                            note: L("model.note.gemini_transcribe", "Dedicated speech model · free tier")),
                ModelOption(id: "gemini-3.5-flash-lite",
                            note: L("model.note.multimodal", "General multimodal model · free tier")),
            ]
        case .openRouter:
            return Self.openRouterModels
        case .custom:
            return [
                ModelOption(id: "whisper-1", note: "OpenAI"),
                ModelOption(id: "gpt-4o-transcribe", note: "OpenAI"),
                ModelOption(id: "gpt-4o-mini-transcribe", note: "OpenAI"),
            ]
        }
    }

    var rewriteModels: [ModelOption] {
        switch self {
        case .groq:
            return [
                ModelOption(id: "openai/gpt-oss-20b",
                            note: L("model.note.fast_free", "Fast · free")),
                ModelOption(id: "openai/gpt-oss-120b",
                            note: L("model.note.smarter_free", "Smarter · free")),
                ModelOption(id: "qwen/qwen3.8-27b",
                            note: L("model.note.multilingual_free", "Strong multilingual · free")),
            ]
        case .gemini:
            return [
                ModelOption(id: "gemini-3.5-flash-lite",
                            note: L("model.note.fastest_free_tier", "Fastest · free tier")),
                ModelOption(id: "gemini-3.6-flash",
                            note: L("model.note.balanced_free_tier", "Balanced · free tier")),
                ModelOption(id: "gemini-3.8-flash",
                            note: L("model.note.smartest_flash", "Smartest Flash · free tier")),
            ]
        case .openRouter:
            return Self.openRouterModels
        case .custom:
            return [
                ModelOption(id: "gpt-4o-mini", note: "OpenAI"),
                ModelOption(id: "gpt-4.1-mini", note: "OpenAI"),
            ]
        }
    }

    private static let openRouterModels: [ModelOption] = [
        ModelOption(id: "google/gemini-3.5-flash-lite", note: L("model.note.fastest", "Fastest")),
        ModelOption(id: "google/gemini-3.6-flash", note: L("model.note.balanced", "Balanced")),
        ModelOption(id: "google/gemini-3.8-flash", note: L("model.note.smartest", "Smartest")),
        ModelOption(id: "google/gemini-2.5-flash", note: L("model.note.legacy", "Previous default")),
    ]

    /// Maps the `transcriptionBackend` values written by releases up to 2.x.
    ///
    /// The old `gemini` backend went through OpenRouter, so it maps to
    /// `.openRouter` — the user's existing key keeps working unchanged.
    static func fromLegacyBackend(_ raw: String) -> AIProvider? {
        if let value = AIProvider(rawValue: raw) { return value }
        switch raw {
        case "groqWhisper", "Groq Whisper (Free)":                 return .groq
        case "gemini", "Gemini 2.5 Flash (OpenRouter)":            return .openRouter
        case "NIM Canary", "NVIDIA NIM Canary":                    return .groq
        default:                                                   return nil
        }
    }
}

/// A model suggestion shown next to a model-ID text field.
struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let note: String
}
