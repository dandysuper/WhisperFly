import Foundation

/// A failure talking to a speech or text provider, phrased for the user.
///
/// Every client maps HTTP and transport failures onto this type so the pill and
/// the menu can say "Groq rejected the API key" instead of dumping a raw JSON
/// body, and so the pipeline can decide whether another provider is worth trying.
enum ProviderError: LocalizedError, Sendable {
    case missingKey(AIProvider)
    case invalidKey(AIProvider)
    case rateLimited(AIProvider, retryAfter: TimeInterval?)
    case quotaExceeded(AIProvider)
    case modelUnavailable(AIProvider, model: String)
    case badRequest(AIProvider, message: String)
    case server(AIProvider, status: Int)
    case network(AIProvider, message: String)
    case emptyResponse(AIProvider)
    case audioTooLarge(AIProvider, limitMB: Int)

    var provider: AIProvider {
        switch self {
        case .missingKey(let p), .invalidKey(let p), .quotaExceeded(let p),
             .emptyResponse(let p):
            return p
        case .rateLimited(let p, _), .modelUnavailable(let p, _), .badRequest(let p, _),
             .server(let p, _), .network(let p, _), .audioTooLarge(let p, _):
            return p
        }
    }

    var errorDescription: String? {
        let name = provider.shortName
        switch self {
        case .missingKey:
            return L("provider.error.missing_key", "Add a %@ API key in Settings → Speech Engines.", name)
        case .invalidKey:
            return L("provider.error.invalid_key", "%@ rejected the API key. Check it in Settings → Speech Engines.", name)
        case .rateLimited(_, let retryAfter):
            if let retryAfter, retryAfter > 0 {
                return L("provider.error.rate_limited_after", "%@ rate limit reached. Try again in %ds.", name, Int(retryAfter.rounded(.up)))
            }
            return L("provider.error.rate_limited", "%@ rate limit reached. Try again shortly.", name)
        case .quotaExceeded:
            return L("provider.error.quota", "%@ free quota is used up for now.", name)
        case .modelUnavailable(_, let model):
            return L("provider.error.model", "%@ does not offer the model “%@”.", name, model)
        case .badRequest(_, let message):
            return L("provider.error.bad_request", "%@: %@", name, message)
        case .server(_, let status):
            return L("provider.error.server", "%@ is having trouble (HTTP %d).", name, status)
        case .network(_, let message):
            return L("provider.error.network", "Could not reach %@: %@", name, message)
        case .emptyResponse:
            return L("provider.error.empty", "%@ returned no text.", name)
        case .audioTooLarge(_, let limit):
            return L("provider.error.too_large", "This recording is larger than the %d MB %@ accepts.", limit, name)
        }
    }

    /// Whether another provider might succeed where this one failed.
    ///
    /// A bad key, a rate limit or an outage is specific to one service, so a
    /// different one is worth a try. A malformed request usually is not.
    var warrantsFallback: Bool {
        switch self {
        case .badRequest: return false
        default:          return true
        }
    }
}

/// Failures that belong to the pipeline rather than to a provider.
enum PipelineError: LocalizedError, Sendable {
    case noSpeech
    case notConfigured(AIProvider)

    var errorDescription: String? {
        switch self {
        case .noSpeech:
            return L("error.no_speech", "No speech detected")
        case .notConfigured(let provider):
            return L("error.not_configured", "Add a free %@ API key to start dictating.", provider.shortName)
        }
    }
}
