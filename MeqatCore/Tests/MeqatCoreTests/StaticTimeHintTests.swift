import Foundation
import Testing

@testable import MeqatCore

@Suite struct StaticTimeHintTests {
    let tz = TimeZone(identifier: "Asia/Dhaka")!

    func window(_ from: (Int, Int), _ to: (Int, Int), endDayOffset: Int = 0) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 28))!
        let start = cal.date(bySettingHour: from.0, minute: from.1, second: 0, of: day)!
        var end = cal.date(bySettingHour: to.0, minute: to.1, second: 0, of: day)!
        end = cal.date(byAdding: .day, value: endDayOffset, to: end)!
        return DateInterval(start: start, end: end)
    }

    func outside(_ h: Int, _ m: Int, _ w: DateInterval) -> Bool {
        StaticTimeHint.isOutside(ClockTime(hour: h, minute: m), window: w, timeZone: tz)
    }

    @Test func dhuhr() {
        let w = window((11, 46), (15, 4))
        #expect(!outside(12, 30, w))
        #expect(outside(15, 30, w))
        #expect(!outside(11, 46, w))
        #expect(!outside(15, 4, w))
    }

    @Test func istiwa() {
        #expect(outside(11, 30, window((11, 36), (11, 46))))
    }

    @Test func tahajjudAcrossMidnight() {
        #expect(outside(23, 30, window((2, 10), (4, 30))))
    }
}
