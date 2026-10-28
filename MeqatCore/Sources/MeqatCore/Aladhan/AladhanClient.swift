import Foundation

public protocol AladhanFetching: Sendable {
    func fetchMonth(_ month: YearMonth, parameters: FetchParameters) async throws -> [DayTimings]
}

public struct AladhanClient: AladhanFetching {
    static let maxBodyBytes = 1_048_576

    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchMonth(_ month: YearMonth, parameters: FetchParameters) async throws -> [DayTimings] {
        guard let location = parameters.location else { throw AladhanError.noLocation }
        let (body, response) = try await transport.data(for: Self.request(for: month, parameters: parameters))
        if response.statusCode != 200 {
            if response.statusCode == 400, case .city = location { throw AladhanError.cityNotFound }
            throw AladhanError.http(response.statusCode)
        }
        return try Self.parse(body, month: month)
    }

    // MARK: Request

    static func request(for month: YearMonth, parameters: FetchParameters) -> URLRequest {
        var items: [(String, String)] = []
        let endpoint: String
        switch parameters.location {
        case .coordinates(let c):
            endpoint = "calendar"
            items = [("latitude", rounded(c.latitude)), ("longitude", rounded(c.longitude))]
        case .city(let city, let country, let state):
            endpoint = "calendarByCity"
            items = [("city", city), ("country", country)]
            if let state { items.append(("state", state)) }
        case nil:
            endpoint = "calendar"
        }
        items.append(("school", String(parameters.school)))
        items.append(("iso8601", "true"))
        if let method = parameters.method { items.append(("method", String(method))) }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.aladhan.com"
        components.path = "/v1/\(endpoint)/\(month.year)/\(month.month)"
        components.percentEncodedQueryItems = items.map { URLQueryItem(name: $0.0, value: encode($0.1)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 5
        return request
    }

    private static func rounded(_ x: Double) -> String {
        String(format: "%.2f", (x * 100).rounded() / 100)
    }

    // Not URLComponents' own encoding: whether it escapes & = + varies by Foundation version.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    // MARK: Response

    private struct Response: Decodable {
        struct Day: Decodable {
            struct DateInfo: Decodable {
                struct Gregorian: Decodable { let date: String }
                let gregorian: Gregorian
            }
            struct Meta: Decodable { let timezone: String }
            let date: DateInfo
            let timings: [String: String]
            let meta: Meta
        }
        let code: Int
        let data: [Day]
    }

    private static func parse(_ body: Data, month: YearMonth) throws -> [DayTimings] {
        guard body.count <= maxBodyBytes else { throw AladhanError.bodyTooLarge }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: body)
        } catch {
            throw AladhanError.invalidResponse("undecodable body")
        }
        guard response.code == 200 else { throw AladhanError.apiCode(response.code) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var seen = Set<LocalDate>()
        return try response.data.map { day in
            let date = try localDate(day.date.gregorian.date)
            guard date.yearMonth == month else { throw AladhanError.invalidResponse("date outside month") }
            guard seen.insert(date).inserted else { throw AladhanError.invalidResponse("duplicate date") }
            func time(_ key: String) throws -> Date {
                guard let text = day.timings[key], let value = formatter.date(from: text) else {
                    throw AladhanError.invalidResponse("bad timing \(key)")
                }
                return value
            }
            return DayTimings(
                date: date, fajr: try time("Fajr"), sunrise: try time("Sunrise"), dhuhr: try time("Dhuhr"),
                asr: try time("Asr"), sunset: try time("Sunset"), maghrib: try time("Maghrib"),
                isha: try time("Isha"), midnight: try time("Midnight"), lastthird: try time("Lastthird"))
        }
    }

    /// "DD-MM-YYYY"
    private static func localDate(_ text: String) throws -> LocalDate {
        let p = text.split(separator: "-")
        guard p.count == 3, let d = Int(p[0]), let m = Int(p[1]), let y = Int(p[2]),
            (1...12).contains(m), (1...31).contains(d)
        else {
            throw AladhanError.invalidResponse("bad date")
        }
        return LocalDate(year: y, month: m, day: d)
    }
}
