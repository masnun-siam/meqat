import Foundation

public protocol DownloadTransport: Sendable {
    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse)
}

public struct URLSessionDownloadTransport: DownloadTransport {
    static let chunkBytes = 65_536

    public init() {}

    /// Dropping or cancelling the stream cancels the download.
    public func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var chunk = Data(capacity: Self.chunkBytes)
                    for try await byte in bytes {
                        chunk.append(byte)
                        guard chunk.count == Self.chunkBytes else { continue }
                        continuation.yield(chunk)
                        chunk.removeAll(keepingCapacity: true)
                    }
                    if !chunk.isEmpty { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }
}
