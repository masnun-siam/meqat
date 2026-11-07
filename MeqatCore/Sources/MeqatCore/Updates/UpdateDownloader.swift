import Foundation

public enum DownloadError: Error, Equatable {
    case insecureURL
    case http(Int)
    case tooLarge
    case writeFailed
}

/// Downloads the release DMG to a file. No retries; on any failure or cancel the partial file is deleted.
public struct UpdateDownloader: Sendable {
    static let maxBytes = 50 * 1_048_576
    /// URLSession's request timeout is an inactivity timeout: it restarts with every packet.
    static let inactivityTimeout: TimeInterval = 60

    private let transport: DownloadTransport

    public init(transport: DownloadTransport = URLSessionDownloadTransport()) {
        self.transport = transport
    }

    /// Writes the body of `url` to `file`, reporting whole percentages from 0 to 100, each once.
    /// Without a `Content-Length` it reports 0 until the body ends, then 100.
    /// Throws `DownloadError`, or a transport `URLError` or `CancellationError` as it is.
    public func download(_ url: URL, to file: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        guard url.scheme == "https" else { throw DownloadError.insecureURL }
        let (chunks, response) = try await transport.bytes(for: Self.request(url))
        guard response.statusCode == 200 else { throw DownloadError.http(response.statusCode) }
        let expected = response.expectedContentLength
        guard expected <= Self.maxBytes else { throw DownloadError.tooLarge }
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
            let handle = try? FileHandle(forWritingTo: file)
        else { throw DownloadError.writeFailed }
        do {
            defer { try? handle.close() }
            try await Self.write(chunks, to: handle, expected: expected, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: file)
            // URLSession reports a cancelled task as URLError(.cancelled); callers see one cancel error.
            throw Task.isCancelled ? CancellationError() : error
        }
    }

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = inactivityTimeout
        request.setValue("Meqat", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func write(
        _ chunks: AsyncThrowingStream<Data, Error>, to handle: FileHandle, expected: Int64,
        progress: (Int) -> Void
    ) async throws {
        var written: Int64 = 0
        var reported = 0
        progress(0)
        for try await chunk in chunks {
            try Task.checkCancellation()
            written += Int64(chunk.count)
            guard written <= maxBytes else { throw DownloadError.tooLarge }
            do { try handle.write(contentsOf: chunk) } catch { throw DownloadError.writeFailed }
            guard expected > 0 else { continue }
            let percent = Int(min(written * 100 / expected, 100))
            if percent != reported {
                reported = percent
                progress(percent)
            }
        }
        // A cancelled stream ends without an error.
        try Task.checkCancellation()
        if reported != 100 { progress(100) }
    }
}
