import Foundation
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "GitHub")

/// Thin, typed wrapper over the handful of GitHub REST endpoints the updater needs.
///
/// Kept separate from the update state machine so the request/parse layer can be
/// tested with a stubbed `URLSession` and so the rate-limit and error mapping
/// live in exactly one place.
struct GitHubClient: Sendable {

    enum ClientError: LocalizedError {
        case rateLimited(resetAt: Date?)
        case notFound
        case httpStatus(Int)
        case malformedResponse(String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .rateLimited(let resetAt):
                if let resetAt {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    return L("update.error.rate_limit",
                             "GitHub rate limit reached. Try again after %@.", formatter.string(from: resetAt))
                }
                return L("update.error.rate_limit_generic", "GitHub rate limit reached. Try again later.")
            case .notFound:
                return L("update.error.not_found", "The repository or branch could not be found on GitHub.")
            case .httpStatus(let code):
                return L("update.error.http", "GitHub returned HTTP %d.", code)
            case .malformedResponse(let detail):
                return L("update.error.malformed", "Unexpected response from GitHub: %@.", detail)
            case .transport(let detail):
                return L("update.error.transport", "Could not reach GitHub: %@.", detail)
            }
        }
    }

    let repository: String
    let branch: String
    let token: String?
    let session: URLSession

    init(repository: String,
         branch: String,
         token: String? = nil,
         session: URLSession = .shared) {
        self.repository = repository
        self.branch = branch
        self.token = token
        self.session = session
    }

    // MARK: - Endpoints

    /// The tip of the tracked branch.
    func headCommit() async throws -> RemoteCommit {
        let data = try await get(path: "/repos/\(repository)/commits/\(branch)")
        return try Self.decodeCommit(data)
    }

    /// The newest published release, if there is one.
    func latestRelease() async throws -> RemoteRelease? {
        do {
            let data = try await get(path: "/repos/\(repository)/releases/latest")
            return try Self.decodeRelease(data)
        } catch ClientError.notFound {
            // Repositories without releases are normal, not an error.
            return nil
        }
    }

    /// Whether `sha` is reachable from the branch head — i.e. the running build
    /// is a normal ancestor rather than an unpublished local change.
    func isAncestor(_ sha: String, of branchHead: String) async throws -> Bool {
        guard sha != branchHead else { return true }
        do {
            let data = try await get(path: "/repos/\(repository)/compare/\(sha)...\(branchHead)")
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw ClientError.malformedResponse("compare: missing status")
            }
            return status == "ahead" || status == "identical"
        } catch ClientError.notFound {
            // The stamped commit is not in the repository at all (e.g. a rebase
            // dropped it), so it cannot be an ancestor of the branch head.
            return false
        }
    }

    // MARK: - Plumbing

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw ClientError.transport("invalid URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects requests without a User-Agent.
        request.setValue("\(BuildInfo.displayName)/\(BuildInfo.version) (\(BuildInfo.repository))",
                         forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func get(path: String) async throws -> Data {
        let request = try makeRequest(path: path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.malformedResponse("no HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 404:
            throw ClientError.notFound
        case 403, 429:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw ClientError.rateLimited(resetAt: Self.rateLimitReset(from: http))
            }
            throw ClientError.httpStatus(http.statusCode)
        default:
            log.error("GitHub \(path, privacy: .public) -> \(http.statusCode)")
            throw ClientError.httpStatus(http.statusCode)
        }
    }

    private static func rateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Decoding

    static func decodeCommit(_ data: Data) throws -> RemoteCommit {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw ClientError.malformedResponse("commit: missing sha")
        }
        let commit = json["commit"] as? [String: Any] ?? [:]
        let message = commit["message"] as? String ?? ""
        let author = commit["author"] as? [String: Any] ?? [:]
        let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))

        return RemoteCommit(
            sha: sha,
            message: message,
            authorName: author["name"] as? String,
            authoredAt: iso8601(author["date"] as? String),
            htmlURL: htmlURL
        )
    }

    static func decodeRelease(_ data: Data) throws -> RemoteRelease {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw ClientError.malformedResponse("release: missing tag_name")
        }
        let rawAssets = json["assets"] as? [[String: Any]] ?? []
        let assets: [ReleaseAsset] = rawAssets.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let urlString = entry["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return ReleaseAsset(
                name: name,
                downloadURL: url,
                sizeBytes: entry["size"] as? Int ?? 0
            )
        }
        return RemoteRelease(
            tagName: tag,
            name: json["name"] as? String,
            publishedAt: iso8601(json["published_at"] as? String),
            htmlURL: (json["html_url"] as? String).flatMap(URL.init(string:)),
            assets: assets
        )
    }

    private static func iso8601(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
