import Foundation
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "UpdateDownloader")

/// Streams a release asset to a temporary file, reporting progress as it goes.
///
/// Uses `URLSession.bytes(for:)` rather than `downloadTask` so progress can be
/// surfaced to the UI without pulling the whole disk image into memory first.
struct UpdateDownloader: Sendable {

    enum DownloadError: LocalizedError {
        case transport(String)
        case unexpectedStatus(Int)

        var errorDescription: String? {
            switch self {
            case .transport(let detail):
                return L("update.download.transport", "Download failed: %@.", detail)
            case .unexpectedStatus(let code):
                return L("update.download.status", "The download server returned HTTP %d.", code)
            }
        }
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Downloads `asset` into the temporary directory.
    ///
    /// - Parameter progress: Called on an arbitrary queue with a 0…1 fraction.
    /// - Returns: The file URL of the completed download.
    func download(
        _ asset: ReleaseAsset,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: asset.downloadURL)
        request.timeoutInterval = 300
        // GitHub redirects asset downloads to a signed object-storage URL.
        request.setValue("\(BuildInfo.displayName)/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")

        let (stream, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.transport("no HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw DownloadError.unexpectedStatus(http.statusCode)
        }

        let expectedBytes = asset.sizeBytes > 0
            ? asset.sizeBytes
            : Int(http.expectedContentLength)

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisperfly-\(UUID().uuidString)-\(asset.name)")

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: destination.path) else {
            throw DownloadError.transport("could not open \(destination.lastPathComponent) for writing")
        }

        do {
            var buffer = Data()
            buffer.reserveCapacity(Self.chunkSize)
            var received = 0
            var lastReported = 0.0

            for try await byte in stream {
                buffer.append(byte)
                guard buffer.count >= Self.chunkSize else { continue }

                try handle.write(contentsOf: buffer)
                received += buffer.count
                buffer.removeAll(keepingCapacity: true)

                if expectedBytes > 0 {
                    let fraction = min(1.0, Double(received) / Double(expectedBytes))
                    // Only cross the actor boundary a handful of times per second.
                    if fraction - lastReported >= 0.01 || fraction >= 1.0 {
                        lastReported = fraction
                        progress(fraction)
                    }
                }
            }

            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                received += buffer.count
            }

            try handle.close()
            progress(1.0)
            log.info("Downloaded \(asset.name, privacy: .public) (\(received) bytes)")
            return destination
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw DownloadError.transport(error.localizedDescription)
        }
    }

    private static let chunkSize = 128 * 1024
}
