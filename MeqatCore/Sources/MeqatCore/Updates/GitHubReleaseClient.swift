import Foundation

public struct GitHubReleaseClient: ReleaseFetching {
    static let maxBodyBytes = 1_048_576

    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchLatest() async throws -> LatestRelease {
        let (body, response) = try await transport.data(for: Self.request())
        guard response.statusCode == 200 else { throw ReleaseError.http(response.statusCode) }
        return try Self.parse(body)
    }

    static func request() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/masnun-siam/meqat/releases/latest")!)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Meqat", forHTTPHeaderField: "User-Agent")
        return request
    }

    private struct Response: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]?

        private enum CodingKeys: String, CodingKey { case tag_name, html_url, assets }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tag_name = try c.decode(String.self, forKey: .tag_name)
            html_url = try c.decode(String.self, forKey: .html_url)
            assets = try? c.decodeIfPresent([Asset].self, forKey: .assets)
        }
    }

    /// Never fails to decode: a field of the wrong type, or an entry that is not an object, reads as nil.
    private struct Asset: Decodable {
        let name: String?
        let browser_download_url: String?
        let digest: String?

        private enum CodingKeys: String, CodingKey { case name, browser_download_url, digest }

        init(from decoder: Decoder) {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            name = try? c?.decodeIfPresent(String.self, forKey: .name)
            browser_download_url = try? c?.decodeIfPresent(String.self, forKey: .browser_download_url)
            digest = try? c?.decodeIfPresent(String.self, forKey: .digest)
        }
    }

    private static func parse(_ body: Data) throws -> LatestRelease {
        guard body.count <= maxBodyBytes else { throw ReleaseError.bodyTooLarge }
        guard let response = try? JSONDecoder().decode(Response.self, from: body),
            let url = URL(string: response.html_url), url.scheme == "https"
        else { throw ReleaseError.invalidResponse }
        return LatestRelease(tag: response.tag_name, pageURL: url, asset: dmgAsset(response))
    }

    /// The `Meqat-<version>.dmg` entry, only with an `https` URL on `github.com`.
    private static func dmgAsset(_ response: Response) -> ReleaseAsset? {
        guard let version = ReleaseVersion(response.tag_name),
            let asset = response.assets?.first(where: { $0.name == "Meqat-\(version).dmg" }),
            let url = asset.browser_download_url.flatMap(URL.init(string:)),
            url.scheme == "https", url.host == "github.com"
        else { return nil }
        return ReleaseAsset(downloadURL: url, sha256: sha256(asset.digest))
    }

    /// The 64 hex characters of `sha256:<hex>`, lowercased; nil for anything else.
    private static func sha256(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count)
        guard hex.count == 64, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return hex.lowercased()
    }
}
