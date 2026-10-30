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
    }

    private static func parse(_ body: Data) throws -> LatestRelease {
        guard body.count <= maxBodyBytes else { throw ReleaseError.bodyTooLarge }
        guard let response = try? JSONDecoder().decode(Response.self, from: body),
            let url = URL(string: response.html_url), url.scheme == "https"
        else { throw ReleaseError.invalidResponse }
        return LatestRelease(tag: response.tag_name, pageURL: url)
    }
}
