import Foundation
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "HTTP")

/// The one place provider requests leave the app.
///
/// Centralising transport gives every provider the same behaviour:
///
/// - a dedicated session with sane timeouts (the shared session waits up to
///   seven days for a resource, which turned a dead network into a frozen pill);
/// - one automatic retry for a short rate-limit window, a 5xx or a dropped
///   connection, which covers the common transient failure without surprising
///   the user with long waits;
/// - status codes mapped to `ProviderError`, with the provider's own message
///   extracted from its JSON error body.
enum HTTPTransport {

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "WhisperFly/\(BuildInfo.version) (macOS)"]
        return URLSession(configuration: configuration)
    }()

    /// The longest `retry-after` worth waiting for before giving up to fallback.
    private static let maxAutomaticWait: TimeInterval = 6

    /// Sends `request` and returns the body of a 2xx response.
    static func send(_ request: URLRequest, provider: AIProvider) async throws -> Data {
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ProviderError.network(provider, message: "no HTTP response")
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }

                let error = mapStatus(http, data: data, provider: provider, model: modelName(in: request))
                log.error("\(provider.rawValue, privacy: .public) HTTP \(http.statusCode): \(String(decoding: data.prefix(400), as: UTF8.self), privacy: .public)")

                if attempt == 1, let delay = retryDelay(for: error) {
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw error
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                let transient: Set<URLError.Code> = [.networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed]
                if attempt == 1, transient.contains(error.code) {
                    try await Task.sleep(for: .milliseconds(600))
                    continue
                }
                throw ProviderError.network(provider, message: error.localizedDescription)
            }
        }
    }

    /// Decodes a JSON object body, or throws `emptyResponse`.
    static func json(_ data: Data, provider: AIProvider) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.emptyResponse(provider)
        }
        return object
    }

    // MARK: - Mapping

    private static func retryDelay(for error: ProviderError) -> TimeInterval? {
        switch error {
        case .rateLimited(_, let after):
            let wait = after ?? 2
            return wait <= maxAutomaticWait ? max(wait, 0.5) : nil
        case .server:
            return 1
        default:
            return nil
        }
    }

    static func mapStatus(_ response: HTTPURLResponse, data: Data, provider: AIProvider, model: String?) -> ProviderError {
        let message = errorMessage(from: data)
        let lowered = message.lowercased()
        switch response.statusCode {
        case 401, 403:
            // Gemini answers a bad key with 400 + API_KEY_INVALID, handled below;
            // a 403 that is about something else still reads best as a key problem.
            return .invalidKey(provider)
        case 404:
            return .modelUnavailable(provider, model: model ?? "?")
        case 413:
            return .audioTooLarge(provider, limitMB: 25)
        case 429:
            if lowered.contains("quota") && !lowered.contains("per minute") {
                return .quotaExceeded(provider)
            }
            return .rateLimited(provider, retryAfter: retryAfter(from: response))
        case 400:
            if lowered.contains("api key not valid") || lowered.contains("api_key_invalid") || lowered.contains("invalid api key") {
                return .invalidKey(provider)
            }
            if lowered.contains("model") && (lowered.contains("not found") || lowered.contains("does not exist") || lowered.contains("decommissioned")) {
                return .modelUnavailable(provider, model: model ?? "?")
            }
            return .badRequest(provider, message: message.isEmpty ? "HTTP 400" : message)
        case 500...599:
            return .server(provider, status: response.statusCode)
        default:
            return .badRequest(provider, message: message.isEmpty ? "HTTP \(response.statusCode)" : message)
        }
    }

    /// Pulls a human-readable message out of the common error shapes:
    /// `{"error": {"message": …}}` (OpenAI, Groq, Gemini, OpenRouter),
    /// `[{"error": …}]` (Google batch-style), or a bare string.
    static func errorMessage(from data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data)
        let root: Any? = (object as? [Any])?.first ?? object
        if let dict = root as? [String: Any] {
            if let error = dict["error"] as? [String: Any], let message = error["message"] as? String {
                return message.trimmed
            }
            if let message = dict["error"] as? String { return message.trimmed }
            if let message = dict["message"] as? String { return message.trimmed }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmed
        return text.hasPrefix("<") ? "" : text
    }

    /// Seconds from `retry-after`, or from Groq's `x-ratelimit-reset-*` (`"7.66s"`, `"2m59.56s"`).
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let value = response.value(forHTTPHeaderField: "retry-after"), let seconds = TimeInterval(value.trimmed) {
            return seconds
        }
        for header in ["x-ratelimit-reset-requests", "x-ratelimit-reset-tokens", "x-ratelimit-reset-audio-seconds"] {
            if let value = response.value(forHTTPHeaderField: header), let seconds = parseDuration(value) {
                return seconds
            }
        }
        return nil
    }

    static func parseDuration(_ raw: String) -> TimeInterval? {
        var total: TimeInterval = 0
        var number = ""
        var matched = false
        for character in raw.trimmed {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = TimeInterval(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default:  return nil
            }
            matched = true
            number = ""
        }
        if !number.isEmpty, let value = TimeInterval(number) {
            total += value
            matched = true
        }
        return matched ? total : nil
    }

    private static func modelName(in request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return json["model"] as? String
    }
}

/// `multipart/form-data` body builder for the OpenAI-style audio endpoints.
struct MultipartForm {
    let boundary = "WhisperFly-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func field(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func file(_ name: String, fileName: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    mutating func finish() -> Data {
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
