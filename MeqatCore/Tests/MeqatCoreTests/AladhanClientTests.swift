import XCTest
@testable import MeqatCore

final class StubTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var result: Result<(Data, Int), Error>

    init(_ result: Result<(Data, Int), Error>) { self.result = result }
    convenience init(status: Int = 200, body: Data) { self.init(.success((body, status))) }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = try result.get()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class AladhanClientTests: XCTestCase {
    let october = YearMonth(year: 2026, month: 10)

    func params(_ location: FetchLocation? = .coordinates(Coordinates(latitude: 23.81034, longitude: 90.41252)),
                method: Int? = nil, school: Int = 0) -> FetchParameters {
        FetchParameters(location: location, method: method, school: school, timeZoneId: "Asia/Dhaka")
    }

    func url(_ p: FetchParameters) -> String {
        AladhanClient.request(for: october, parameters: p).url!.absoluteString
    }

    func fixture() throws -> String { String(decoding: try Fixture.data("aladhan/calendar-dhaka-2026-10.json"), as: UTF8.self) }

    func fetch(_ body: String, status: Int = 200, location: FetchLocation? = nil) async throws -> [DayTimings] {
        let client = AladhanClient(transport: StubTransport(status: status, body: Data(body.utf8)))
        return try await client.fetchMonth(october, parameters: params(location ?? .coordinates(Coordinates(latitude: 23.81, longitude: 90.41))))
    }

    func assertInvalid(_ body: String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await fetch(body)
            XCTFail("expected error", file: file, line: line)
        } catch let e as AladhanError {
            if case .invalidResponse = e { return }
            XCTFail("unexpected \(e)", file: file, line: line)
        } catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    // MARK: Request

    func testCoordinatesRoundedAndParams() {
        let r = AladhanClient.request(for: october, parameters: params(school: 1))
        XCTAssertEqual(r.url!.absoluteString,
                       "https://api.aladhan.com/v1/calendar/2026/10?latitude=23.81&longitude=90.41&school=1&iso8601=true")
        XCTAssertEqual(r.timeoutInterval, 5)
    }

    func testMethodOnlyWhenSet() {
        XCTAssertFalse(url(params()).contains("method"))
        XCTAssertTrue(url(params(method: 3)).hasSuffix("&iso8601=true&method=3"))
    }

    func testCityIsOneEncodedValue() {
        let u = url(params(.city(city: "X&method=99", country: "Bangladesh", state: nil)))
        XCTAssertEqual(u, "https://api.aladhan.com/v1/calendarByCity/2026/10?city=X%26method%3D99&country=Bangladesh&school=0&iso8601=true")
        XCTAssertFalse(u.contains("&method"))
    }

    func testStateEncodedOrAbsent() {
        XCTAssertTrue(url(params(.city(city: "São Paulo", country: "Brazil", state: "SP+1 x"))).contains(
            "city=S%C3%A3o%20Paulo&country=Brazil&state=SP%2B1%20x&school"))
        XCTAssertFalse(url(params(.city(city: "Dhaka", country: "Bangladesh", state: nil))).contains("state"))
    }

    func testNoLocationThrowsWithoutRequest() async {
        let t = StubTransport(status: 200, body: Data())
        do {
            _ = try await AladhanClient(transport: t).fetchMonth(october, parameters: params(nil))
            XCTFail()
        } catch { XCTAssertEqual(error as? AladhanError, .noLocation) }
        XCTAssertTrue(t.requests.isEmpty)
    }

    // MARK: Errors

    func testCityNotFoundOnlyForCityEndpoint() async throws {
        let body = String(decoding: try Fixture.data("aladhan/calendarByCity-400.json"), as: UTF8.self)
        do {
            _ = try await fetch(body, status: 400, location: .city(city: "Nowhere", country: "X", state: nil))
            XCTFail()
        } catch { XCTAssertEqual(error as? AladhanError, .cityNotFound) }
        do { _ = try await fetch(body, status: 400); XCTFail() } catch { XCTAssertEqual(error as? AladhanError, .http(400)) }
    }

    func testHTTPFailures() async {
        for status in [503, 429] {
            do { _ = try await fetch("{}", status: status, location: .city(city: "A", country: "B", state: nil)); XCTFail() }
            catch { XCTAssertEqual(error as? AladhanError, .http(status)) }
        }
    }

    func testTimeoutPassesThrough() async {
        let client = AladhanClient(transport: StubTransport(.failure(URLError(.timedOut))))
        do { _ = try await client.fetchMonth(october, parameters: params()); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }

    func testApiCodeNot200() async throws {
        let body = try fixture().replacingOccurrences(of: "\"code\": 200", with: "\"code\": 500")
        do { _ = try await fetch(body); XCTFail() } catch { XCTAssertEqual(error as? AladhanError, .apiCode(500)) }
    }

    func testBodyTooLarge() async {
        do { _ = try await fetch(String(repeating: " ", count: 1_048_577)); XCTFail() }
        catch { XCTAssertEqual(error as? AladhanError, .bodyTooLarge) }
    }

    func testInvalidBodies() async throws {
        let f = try fixture()
        await assertInvalid("not json")
        await assertInvalid(f.replacingOccurrences(of: "\"02-10-2026\"", with: "\"01-10-2026\""))          // duplicate
        await assertInvalid(f.replacingOccurrences(of: "\"02-10-2026\"", with: "\"02-11-2026\""))          // outside month
        await assertInvalid(f.replacingOccurrences(of: "\"Lastthird\"", with: "\"Other\""))                // missing field
        await assertInvalid(f.replacingOccurrences(of: "2026-10-01T04:35:00+06:00", with: "2026-10-01T04:35:00")) // no offset
        await assertInvalid(f.replacingOccurrences(of: "\"timezone\"", with: "\"tz\""))                   // no timezone
    }

    // MARK: Parsing

    func testValidMonth() async throws {
        let days = try await fetch(try fixture())
        XCTAssertEqual(days.count, 31)
        let first = days[0]
        XCTAssertEqual(first.date, LocalDate(year: 2026, month: 10, day: 1))
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(first.fajr, iso.date(from: "2026-10-01T04:35:00+06:00"))
        XCTAssertEqual(first.lastthird, iso.date(from: "2026-10-02T01:49:00+06:00"))
    }
}
