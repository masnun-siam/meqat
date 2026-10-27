import Foundation
@testable import MeqatCore

actor StubAladhan: AladhanFetching {
    struct Call: Equatable {
        let month: YearMonth
        let parameters: FetchParameters
    }

    private(set) var calls: [Call] = []
    private var failure: Error?
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fail(with error: Error?) { failure = error }

    func hold() { holding = true }

    func release() {
        holding = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func fetchMonth(_ month: YearMonth, parameters: FetchParameters) async throws -> [DayTimings] {
        calls.append(Call(month: month, parameters: parameters))
        if holding { await withCheckedContinuation { waiters.append($0) } }
        if let failure { throw failure }
        return Self.days(in: month)
    }

    static func days(in month: YearMonth) -> [DayTimings] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        return (1...count).map { day(LocalDate(year: month.year, month: month.month, day: $0)) }
    }

    static func day(_ date: LocalDate) -> DayTimings {
        let t = date.startOfDay(in: TimeZone(identifier: "UTC")!)
        return DayTimings(date: date, fajr: t, sunrise: t, dhuhr: t, asr: t, sunset: t, maghrib: t,
                          isha: t, midnight: t, lastthird: t)
    }
}
