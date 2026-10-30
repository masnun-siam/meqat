import Foundation

public struct LatestRelease: Sendable, Equatable {
    public let tag: String
    public let pageURL: URL

    public init(tag: String, pageURL: URL) {
        self.tag = tag
        self.pageURL = pageURL
    }
}

public protocol ReleaseFetching: Sendable {
    func fetchLatest() async throws -> LatestRelease
}
