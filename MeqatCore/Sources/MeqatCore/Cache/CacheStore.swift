import Foundation

public final class CacheStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("timings.json")
    }

    public static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Meqat", isDirectory: true)
    }

    /// nil when missing. A corrupt file or a different format version is deleted.
    public func load() -> TimingsCache? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let cache = try? decoder.decode(TimingsCache.self, from: data),
            cache.formatVersion == TimingsCache.currentFormatVersion
        {
            return cache
        }
        delete()
        return nil
    }

    public func save(_ cache: TimingsCache) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cache)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
