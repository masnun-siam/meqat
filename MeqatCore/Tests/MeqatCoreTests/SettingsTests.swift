import XCTest
@testable import MeqatCore

@MainActor
final class SettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func store() -> SettingsStore { SettingsStore(defaults: defaults) }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testEventOrder() {
        XCTAssertEqual(EventID.allCases.map(\.rawValue),
                       ["tahajjud", "fajr", "shuruq", "duha", "istiwa", "dhuhr", "jumah", "asr", "ghurub", "maghrib", "isha"])
        XCTAssertEqual(EventID.shuruq.kind, .prohibited)
        XCTAssertEqual(EventID.duha.kind, .voluntary)
        XCTAssertEqual(EventID.fajr.kind, .obligatory)
        XCTAssertEqual(EventID.istiwa.displayName, "Istiwa")
    }

    func testEmptyDefaults() {
        let s = store().settings
        for id in EventID.allCases {
            let e = s[event: id]
            XCTAssertEqual(e.style, [.duha, .tahajjud].contains(id) ? .disabled : .banner, "\(id)")
            XCTAssertEqual(e.timeSource, .calculated)
            XCTAssertNil(e.staticTime)
            XCTAssertEqual(e.startAlert, StartAlert(enabled: true, offsetMinutes: 0))
            XCTAssertEqual(e.endAlert, LeadAlert(enabled: false, leadMinutes: 15))
            XCTAssertEqual(e.preWarning, LeadAlert(enabled: false, leadMinutes: 20))
            XCTAssertEqual(e.overlayHoldSeconds, 60)
        }
        XCTAssertEqual(s.events.count, 11)
        XCTAssertEqual(s.general, GeneralSettings(launchAtLogin: true, method: nil, school: .shafii, shuruqMinutes: 15, istiwaMinutes: 10, ghurubMinutes: 15))
        XCTAssertEqual(s.location, LocationSettings(mode: .automatic))
    }

    func testMissingKeyKeepsOtherValues() throws {
        let json = #"{"version":1,"value":{"fajr":{"style":"fullScreen","startAlert":{"enabled":false,"offsetMinutes":5}}}}"#
        defaults.set(Data(json.utf8), forKey: "settings.events")
        let fajr = store().settings[event: .fajr]
        XCTAssertEqual(fajr.style, .fullScreen)
        XCTAssertEqual(fajr.startAlert, StartAlert(enabled: false, offsetMinutes: 5))
        XCTAssertEqual(fajr.preWarning, LeadAlert(enabled: false, leadMinutes: 20))
        XCTAssertEqual(store().settings[event: .dhuhr], .defaults(for: .dhuhr))
    }

    func testPartialLeadAlertKeepsDefaultForMissingField() throws {
        let json = #"{"version":1,"value":{"asr":{"preWarning":{"enabled":true}}}}"#
        defaults.set(Data(json.utf8), forKey: "settings.events")
        XCTAssertEqual(store().settings[event: .asr].preWarning, LeadAlert(enabled: true, leadMinutes: 20))
    }

    func testUnknownVersionGivesDefaults() {
        defaults.set(Data(#"{"version":2,"value":{"launchAtLogin":false}}"#.utf8), forKey: "settings.general")
        XCTAssertEqual(store().settings.general, GeneralSettings())
    }

    func testClampingThroughInitAndSetter() {
        var a = StartAlert(offsetMinutes: 999); XCTAssertEqual(a.offsetMinutes, 60)
        a.offsetMinutes = -999; XCTAssertEqual(a.offsetMinutes, -60)
        var l = LeadAlert(enabled: true, leadMinutes: 0); XCTAssertEqual(l.leadMinutes, 1)
        l.leadMinutes = 500; XCTAssertEqual(l.leadMinutes, 120)
        var e = EventSettings(style: .banner, overlayHoldSeconds: -1); XCTAssertEqual(e.overlayHoldSeconds, 0)
        e.overlayHoldSeconds = 301; XCTAssertEqual(e.overlayHoldSeconds, 300)
        var g = GeneralSettings(shuruqMinutes: 3); XCTAssertEqual(g.shuruqMinutes, 5)
        g.istiwaMinutes = 45; XCTAssertEqual(g.istiwaMinutes, 30)
    }

    func testClampingThroughDecoding() throws {
        XCTAssertEqual(try decode(StartAlert.self, #"{"enabled":true,"offsetMinutes":999}"#).offsetMinutes, 60)
        XCTAssertEqual(try decode(StartAlert.self, #"{"enabled":true,"offsetMinutes":-999}"#).offsetMinutes, -60)
        XCTAssertEqual(try decode(LeadAlert.self, #"{"enabled":true,"leadMinutes":0}"#).leadMinutes, 1)
        XCTAssertEqual(try decode(LeadAlert.self, #"{"enabled":true,"leadMinutes":500}"#).leadMinutes, 120)
        XCTAssertEqual(try decode(EventSettings.self, #"{"overlayHoldSeconds":-1}"#).overlayHoldSeconds, 0)
        XCTAssertEqual(try decode(EventSettings.self, #"{"overlayHoldSeconds":301}"#).overlayHoldSeconds, 300)
        let g = try decode(GeneralSettings.self, #"{"shuruqMinutes":3,"ghurubMinutes":45}"#)
        XCTAssertEqual(g.shuruqMinutes, 5)
        XCTAssertEqual(g.ghurubMinutes, 30)
    }

    func testRoundTrip() {
        let a = store()
        a.settings.general.launchAtLogin = false
        a.settings.general.method = 3
        a.settings.general.school = .hanafi
        a.setManualLocation(city: "Dhaka", country: "Bangladesh", state: nil)
        a.settings.events[.fajr]?.style = .fullScreen
        a.settings.events[.fajr]?.timeSource = .fixed
        a.settings.events[.fajr]?.staticTime = ClockTime(hour: 4, minute: 5)
        a.settings.events[.isha]?.endAlert = LeadAlert(enabled: true, leadMinutes: 30)
        XCTAssertEqual(store().settings, a.settings)
        XCTAssertEqual(store().settings[event: .fajr].staticTime, ClockTime(hour: 4, minute: 5))
    }

    func testResetEvent() {
        let s = store()
        s.settings.events[.dhuhr]?.style = .fullScreen
        s.settings.events[.asr]?.style = .fullScreen
        s.resetEvent(.dhuhr)
        XCTAssertEqual(s.settings[event: .dhuhr], .defaults(for: .dhuhr))
        XCTAssertEqual(s.settings[event: .asr].style, .fullScreen)
    }

    func testResetAllKeepsLocation() {
        let s = store()
        s.settings.general.school = .hanafi
        s.settings.events[.asr]?.style = .disabled
        s.setManualLocation(city: "Dhaka", country: "Bangladesh", state: nil)
        s.resetAll()
        XCTAssertEqual(s.settings.general, GeneralSettings())
        XCTAssertEqual(s.settings.events, AppSettings.defaultEvents)
        XCTAssertEqual(s.settings.location, LocationSettings(mode: .manual, manualCity: "Dhaka", manualCountry: "Bangladesh"))
    }

    func testSwitchToAutomaticClearsManual() {
        let s = store()
        s.setManualLocation(city: "Dhaka", country: "Bangladesh", state: "Dhaka Division")
        s.setLocationMode(.automatic)
        XCTAssertEqual(s.settings.location, LocationSettings())
    }

    func testOnChange() {
        let s = store()
        var calls: [(Bool, Bool)] = []
        s.onChange = { old, new in calls.append((old.general.launchAtLogin, new.general.launchAtLogin)) }
        s.settings.general.launchAtLogin = false
        s.settings.general.launchAtLogin = false
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(calls[0].0)
        XCTAssertFalse(calls[0].1)
    }

    func testPlaceName() {
        XCTAssertEqual(LocationSettings(mode: .manual, manualCity: "Dhaka").placeName(timeZone: TimeZone(identifier: "Europe/Paris")!), "Dhaka")
        XCTAssertEqual(LocationSettings().placeName(timeZone: TimeZone(identifier: "Asia/Dhaka")!), "Dhaka")
        XCTAssertEqual(LocationSettings().placeName(timeZone: TimeZone(identifier: "America/New_York")!), "New York")
    }

    func testClockTimeCoding() throws {
        let t = ClockTime(hour: 4, minute: 5)
        let data = try JSONEncoder().encode([t])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["04:05"]"#)
        XCTAssertEqual(try JSONDecoder().decode([ClockTime].self, from: data), [t])
        for bad in ["4:5", "24:00", "04:60", "0405", "ab:cd"] {
            XCTAssertThrowsError(try JSONDecoder().decode([ClockTime].self, from: Data("[\"\(bad)\"]".utf8)), bad)
        }
    }
}
