import XCTest

@testable import MeqatCore

private final class StubDownloadTransport: DownloadTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    let status: Int
    let contentLength: Int?
    let chunks: [Data]
    let failure: Error?
    /// Keeps the body open after the chunks, as a slow download does.
    let hold: Bool

    init(status: Int = 200, contentLength: Int? = nil, chunks: [Data] = [], failure: Error? = nil, hold: Bool = false) {
        self.status = status
        self.contentLength = contentLength
        self.chunks = chunks
        self.failure = failure
        self.hold = hold
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, HTTPURLResponse) {
        requests.append(request)
        let headers = contentLength.map { ["Content-Length": String($0)] } ?? [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        let stream = AsyncThrowingStream<Data, Error> { [chunks, failure, hold] continuation in
            chunks.forEach { continuation.yield($0) }
            guard !hold else { return }
            continuation.finish(throwing: failure)
        }
        return (stream, response)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []
    var onReport: ((Int) -> Void)?

    var values: [Int] { lock.withLock { stored } }

    func report(_ value: Int) {
        lock.withLock { stored.append(value) }
        onReport?(value)
    }
}

final class UpdateDownloaderTests: XCTestCase {
    let url = URL(string: "https://github.com/masnun-siam/meqat/releases/download/v1.8.0/Meqat-1.8.0.dmg")!
    var dir: URL!
    var file: URL { dir.appendingPathComponent("Meqat.dmg") }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func quarters() -> [Data] { (0..<4).map { Data(repeating: UInt8($0), count: 250) } }

    private func download(_ transport: StubDownloadTransport, from url: URL? = nil, to target: URL? = nil) async throws
        -> [Int]
    {
        let box = ProgressBox()
        try await UpdateDownloader(transport: transport).download(url ?? self.url, to: target ?? file) {
            box.report($0)
        }
        return box.values
    }

    private func assertThrows<E: Error & Equatable>(
        _ expected: E, _ transport: StubDownloadTransport, from url: URL? = nil, to target: URL? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await download(transport, from: url, to: target)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expected, "\(error)", file: file, line: line)
        }
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: file.path) }

    // MARK: Request

    func testRequestIsPlainGetWithOnlyUserAgent() async throws {
        let transport = StubDownloadTransport(chunks: [Data([1])])
        _ = try await download(transport)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.allHTTPHeaderFields, ["User-Agent": "Meqat"])
        XCTAssertEqual(request.timeoutInterval, 60)
        XCTAssertEqual(request.url, url)
    }

    func testHTTPURLThrowsBeforeAnyRequest() async {
        let transport = StubDownloadTransport()
        await assertThrows(DownloadError.insecureURL, transport, from: URL(string: "http://github.com/a.dmg")!)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: Body and progress

    func testWritesBodyAndReportsEachPercentOnce() async throws {
        let progress = try await download(StubDownloadTransport(contentLength: 1000, chunks: quarters()))
        XCTAssertEqual(progress, [0, 25, 50, 75, 100])
        XCTAssertEqual(try Data(contentsOf: file), quarters().reduce(Data(), +))
    }

    func testWithoutContentLengthProgressIsZeroUntilTheEnd() async throws {
        let progress = try await download(StubDownloadTransport(chunks: quarters()))
        XCTAssertEqual(progress, [0, 100])
        XCTAssertEqual(try Data(contentsOf: file).count, 1000)
    }

    func testSmallChunksReportEachPercentOnce() async throws {
        let chunks = (0..<1000).map { _ in Data([7]) }
        let progress = try await download(StubDownloadTransport(contentLength: 1000, chunks: chunks))
        XCTAssertEqual(progress, Array(0...100))
    }

    // MARK: Failures

    func testNon200ThrowsAndLeavesNoFile() async {
        for status in [404, 500] {
            await assertThrows(DownloadError.http(status), StubDownloadTransport(status: status, chunks: quarters()))
            XCTAssertFalse(fileExists)
        }
    }

    func testContentLengthOverCapThrowsBeforeWriting() async {
        let transport = StubDownloadTransport(contentLength: UpdateDownloader.maxBytes + 1, chunks: quarters())
        await assertThrows(DownloadError.tooLarge, transport)
        XCTAssertFalse(fileExists)
    }

    func testBodyCrossingCapWithoutContentLengthThrowsAndDeletes() async {
        let half = Data(count: UpdateDownloader.maxBytes / 2)
        await assertThrows(DownloadError.tooLarge, StubDownloadTransport(chunks: [half, half, Data([1])]))
        XCTAssertFalse(fileExists)
    }

    func testBodyAtCapSucceeds() async throws {
        let half = Data(count: UpdateDownloader.maxBytes / 2)
        _ = try await download(StubDownloadTransport(chunks: [half, half]))
        XCTAssertTrue(fileExists)
    }

    func testTransportErrorMidBodyIsRethrownAndDeletes() async {
        for code in [URLError.Code.timedOut, .notConnectedToInternet] {
            let transport = StubDownloadTransport(contentLength: 1000, chunks: [quarters()[0]], failure: URLError(code))
            await assertThrows(URLError(code), transport)
            XCTAssertFalse(fileExists)
        }
    }

    func testMissingFolderThrowsWriteFailed() async {
        let target = dir.appendingPathComponent("missing/Meqat.dmg")
        await assertThrows(DownloadError.writeFailed, StubDownloadTransport(chunks: quarters()), to: target)
    }

    func testCancelMidBodyThrowsCancellationAndDeletes() async throws {
        let transport = StubDownloadTransport(contentLength: 1000, chunks: [quarters()[0]], hold: true)
        let box = ProgressBox()
        let firstChunk = expectation(description: "first chunk written")
        box.onReport = { if $0 == 25 { firstChunk.fulfill() } }
        let task = Task { [url, file] in
            try await UpdateDownloader(transport: transport).download(url, to: file) { box.report($0) }
        }
        await fulfillment(of: [firstChunk], timeout: 5)
        XCTAssertTrue(fileExists)
        task.cancel()
        do {
            try await task.value
            XCTFail("expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(fileExists)
        XCTAssertEqual(box.values, [0, 25])
    }
}
