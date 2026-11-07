import Foundation

public struct LatestRelease: Sendable, Equatable {
    public let tag: String
    public let pageURL: URL
    /// The release's `Meqat-<version>.dmg`; nil when it is missing or unusable.
    public let asset: ReleaseAsset?

    public init(tag: String, pageURL: URL, asset: ReleaseAsset? = nil) {
        self.tag = tag
        self.pageURL = pageURL
        self.asset = asset
    }
}

public struct ReleaseAsset: Sendable, Equatable {
    public let downloadURL: URL
    /// Lowercase hex SHA-256 taken from `digest` (`sha256:<64 hex>`); nil when GitHub sent none or it is malformed.
    public let sha256: String?
}

public protocol ReleaseFetching: Sendable {
    func fetchLatest() async throws -> LatestRelease
}
