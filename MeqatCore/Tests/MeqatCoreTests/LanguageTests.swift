import XCTest

@testable import MeqatCore

final class LanguageTests: XCTestCase {
    func testLocalesAreEnglishPOSIXAndBanglaWithBengaliDigits() {
        XCTAssertEqual(Language.english.locale.identifier, "en_US_POSIX")
        XCTAssertEqual(Language.bangla.locale.identifier, "bn@numbers=beng")
    }

    func testSystemFollowsWhicheverOfBanglaOrEnglishComesFirst() {
        XCTAssertEqual(Language.resolve(override: nil, preferred: ["bn-BD", "en-US"]), .bangla)
        XCTAssertEqual(Language.resolve(override: nil, preferred: ["en-US", "bn-BD"]), .english)
        XCTAssertEqual(Language.resolve(override: nil, preferred: ["fr-FR", "bn", "en"]), .bangla)
    }

    func testSystemFallsBackToEnglishForOtherOrNoLanguages() {
        XCTAssertEqual(Language.resolve(override: nil, preferred: ["fr-FR", "en-US"]), .english)
        XCTAssertEqual(Language.resolve(override: nil, preferred: ["ar"]), .english)
        XCTAssertEqual(Language.resolve(override: nil, preferred: []), .english)
    }

    func testOverrideWinsOverPreferredAndEmptyOverrideCountsAsAbsent() {
        XCTAssertEqual(Language.resolve(override: ["bn"], preferred: ["en-US"]), .bangla)
        XCTAssertEqual(Language.resolve(override: ["en"], preferred: ["bn"]), .english)
        XCTAssertEqual(Language.resolve(override: [], preferred: ["bn-BD"]), .bangla)
    }

    func testChoiceMapsFromStoredOverride() {
        XCTAssertEqual(LanguageChoice(override: nil), .system)
        XCTAssertEqual(LanguageChoice(override: []), .system)
        XCTAssertEqual(LanguageChoice(override: ["en"]), .english)
        XCTAssertEqual(LanguageChoice(override: ["bn"]), .bangla)
        XCTAssertEqual(LanguageChoice(override: ["bn-BD"]), .bangla)
        XCTAssertEqual(LanguageChoice(override: ["fr"]), .english)
    }

    func testChoiceOverrideRoundTrips() {
        XCTAssertNil(LanguageChoice.system.override)
        XCTAssertEqual(LanguageChoice.english.override, ["en"])
        XCTAssertEqual(LanguageChoice.bangla.override, ["bn"])
        for choice in LanguageChoice.allCases {
            XCTAssertEqual(LanguageChoice(override: choice.override), choice)
        }
    }

    func testBanglaEventNamesFollowTheGlossary() {
        let expected: [EventID: String] = [
            .tahajjud: "তাহাজ্জুদ", .fajr: "ফজর", .shuruq: "নিষিদ্ধ সময় (সূর্যোদয়)", .duha: "চাশত",
            .istiwa: "নিষিদ্ধ সময় (দুপুর)", .dhuhr: "যোহর", .jumah: "জুমা", .asr: "আসর",
            .ghurub: "নিষিদ্ধ সময় (সূর্যাস্ত)", .maghrib: "মাগরিব", .isha: "এশা",
        ]
        for id in EventID.allCases {
            XCTAssertEqual(id.displayName(in: .bangla), expected[id], "\(id)")
        }
    }

    func testEnglishEventNamesAreUnchanged() {
        for id in EventID.allCases {
            XCTAssertEqual(id.displayName(in: .english), id.displayName)
        }
    }

    func testMissingBanglaEntryFallsBackToEnglishText() {
        XCTAssertEqual(Language.bangla.localized("Not in the table", table: "Events"), "Not in the table")
    }
}
