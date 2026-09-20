//
//  SearchQueryParserTests.swift
//  LOGITTests
//
//  What the Search tab understands a query to mean. The parser is pure, so every
//  locale can be checked here instead of in the simulator — which matters,
//  because "Dezember" working is the whole point and English tests would never
//  catch it breaking.
//

import XCTest

@testable import LOGIT

final class SearchQueryParserTests: XCTestCase {

    /// A fixed "now" so relative phrases resolve to the same dates every run:
    /// Wednesday, 17 September 2025, 12:00 UTC.
    private let referenceDate = Date(timeIntervalSince1970: 1_758_110_400)

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func parser(_ identifier: String = "en_US") -> SearchQueryParser {
        SearchQueryParser(
            calendar: calendar,
            locale: Locale(identifier: identifier),
            now: { self.referenceDate }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Plain text

    func testPlainTextCarriesNoDateTokens() {
        let query = parser().parse("bench press")
        XCTAssertEqual(query.text, "bench press")
        XCTAssertTrue(query.dateTokens.isEmpty)
        XCTAssertFalse(query.hasDateConstraint)
    }

    func testEmptyTextParsesToAnEmptyQuery() {
        XCTAssertTrue(parser().parse("   ").isEmpty)
    }

    func testAnExerciseNameIsNotMistakenForADate() {
        for name in ["dips", "squat", "row", "lat pulldown", "leg press"] {
            XCTAssertTrue(
                parser().parse(name).dateTokens.isEmpty,
                "\(name) should not read as a date"
            )
        }
    }

    // MARK: - Month names

    func testMonthNameInEveryAppLanguage() {
        // The December each locale's own calendar prints, typed in full.
        let december: [String: String] = [
            "en_US": "December",
            "de_DE": "Dezember",
            "fr_FR": "décembre",
            "es_ES": "diciembre",
            "pt_BR": "dezembro",
            "it_IT": "dicembre",
            "ja_JP": "12月",
            "ko_KR": "12월",
        ]
        for (identifier, word) in december {
            let query = parser(identifier).parse(word)
            XCTAssertEqual(
                query.dateTokens, [.month(12, year: nil)],
                "\(word) in \(identifier) should be December"
            )
            XCTAssertEqual(query.text, "", "\(identifier) should have no text left over")
        }
    }

    func testMonthNameIsCaseAndAccentInsensitive() {
        XCTAssertEqual(parser("fr_FR").parse("DECEMBRE").dateTokens, [.month(12, year: nil)])
    }

    func testAbbreviatedMonthName() {
        XCTAssertEqual(parser().parse("dec").dateTokens, [.month(12, year: nil)])
        XCTAssertEqual(parser("de_DE").parse("dez").dateTokens, [.month(12, year: nil)])
    }

    func testEnglishMonthWorksOnANonEnglishDevice() {
        XCTAssertEqual(parser("de_DE").parse("december").dateTokens, [.month(12, year: nil)])
    }

    func testTooShortToBeAMonth() {
        // "ju" could be June or July, "j" could be three months — neither should
        // silently pick one.
        XCTAssertTrue(parser().parse("ju").dateTokens.isEmpty)
        XCTAssertTrue(parser().parse("j").dateTokens.isEmpty)
    }

    func testMonthWithYear() {
        XCTAssertEqual(parser("de_DE").parse("dezember 2024").dateTokens, [.month(12, year: 2024)])
        XCTAssertEqual(parser().parse("2024 december").dateTokens, [.month(12, year: 2024)])
    }

    func testMonthWithoutAYearMatchesThatMonthInEveryYear() {
        let token = SearchDateToken.month(12, year: nil)
        XCTAssertTrue(token.matches(date(2024, 12, 3), calendar: calendar))
        XCTAssertTrue(token.matches(date(2021, 12, 30), calendar: calendar))
        XCTAssertFalse(token.matches(date(2024, 11, 30), calendar: calendar))
    }

    // MARK: - Years

    func testBareYear() {
        XCTAssertEqual(parser().parse("2024").dateTokens, [.year(2024)])
    }

    func testANumberThatIsNotAPlausibleYearStaysText() {
        let query = parser().parse("1200")
        XCTAssertTrue(query.dateTokens.isEmpty)
        XCTAssertEqual(query.text, "1200")
    }

    // MARK: - Weekdays

    func testWeekdayName() {
        XCTAssertEqual(parser("de_DE").parse("montag").dateTokens, [.weekday(2)])
        XCTAssertEqual(parser().parse("monday").dateTokens, [.weekday(2)])
    }

    func testWeekdayMatchesEveryWeekWithThatDay() {
        let monday = SearchDateToken.weekday(2)
        XCTAssertTrue(monday.matches(date(2025, 9, 15), calendar: calendar))
        XCTAssertFalse(monday.matches(date(2025, 9, 16), calendar: calendar))
    }

    // MARK: - Relative phrases

    func testTodayAndYesterday() {
        XCTAssertEqual(parser().parse("today").dateTokens, [.day(referenceDate)])
        XCTAssertEqual(parser("de_DE").parse("gestern").dateTokens.count, 1)

        guard case let .day(day)? = parser().parse("yesterday").dateTokens.first else {
            return XCTFail("yesterday should resolve to a day")
        }
        XCTAssertTrue(calendar.isDate(day, inSameDayAs: date(2025, 9, 16)))
    }

    func testLastWeekIsAWholeWeekSpan() {
        guard let token = parser().parse("last week").dateTokens.first,
              case .span = token
        else { return XCTFail("last week should resolve to a span") }
        XCTAssertTrue(token.matches(date(2025, 9, 10), calendar: calendar))
        XCTAssertFalse(token.matches(date(2025, 9, 17), calendar: calendar))
    }

    func testAWorkoutAtMidnightBelongsToTheWeekItStarts() {
        // `DateInterval.contains` includes its end instant, so a workout logged
        // at exactly 00:00 on the following Monday used to count as last week's.
        guard let token = parser().parse("last week").dateTokens.first,
              case let .span(interval, _) = token
        else { return XCTFail("last week should resolve to a span") }
        XCTAssertTrue(token.matches(interval.start, calendar: calendar))
        XCTAssertFalse(token.matches(interval.end, calendar: calendar))
    }

    func testThisMonthAndLastYear() {
        XCTAssertEqual(parser().parse("this month").dateTokens, [.month(9, year: 2025)])
        XCTAssertEqual(parser().parse("last year").dateTokens, [.year(2024)])
    }

    func testAnAmbiguousHalfTypedPhraseIsNotGuessed() {
        // "last" alone could still become week, month or year.
        XCTAssertTrue(parser().parse("last").dateTokens.isEmpty)
    }

    // MARK: - Numeric dates

    func testWrittenOutDate() {
        guard case let .day(day)? = parser("de_DE").parse("15.09.2025").dateTokens.first else {
            return XCTFail("15.09.2025 should resolve to a day")
        }
        XCTAssertTrue(calendar.isDate(day, inSameDayAs: date(2025, 9, 15)))
    }

    func testDayAndMonthOrderFollowsTheLocale() {
        guard case let .day(german)? = parser("de_DE").parse("3/4/2025").dateTokens.first,
              case let .day(american)? = parser("en_US").parse("3/4/2025").dateTokens.first
        else { return XCTFail("both locales should resolve a day") }
        XCTAssertTrue(calendar.isDate(german, inSameDayAs: date(2025, 4, 3)))
        XCTAssertTrue(calendar.isDate(american, inSameDayAs: date(2025, 3, 4)))
    }

    func testANumberTooLargeForAMonthDecidesTheOrderItself() {
        guard case let .day(day)? = parser("en_US").parse("25/12/2025").dateTokens.first else {
            return XCTFail("25/12/2025 should resolve to a day")
        }
        XCTAssertTrue(calendar.isDate(day, inSameDayAs: date(2025, 12, 25)))
    }

    func testIsoDate() {
        guard case let .day(day)? = parser().parse("2025-09-15").dateTokens.first else {
            return XCTFail("2025-09-15 should resolve to a day")
        }
        XCTAssertTrue(calendar.isDate(day, inSameDayAs: date(2025, 9, 15)))
    }

    func testNumericMonthAndYear() {
        XCTAssertEqual(parser().parse("09/2025").dateTokens, [.month(9, year: 2025)])
        XCTAssertEqual(parser().parse("2025-09").dateTokens, [.month(9, year: 2025)])
    }

    func testAnImpossibleDateStaysText() {
        let query = parser().parse("31.02.2025")
        XCTAssertTrue(query.dateTokens.isEmpty)
        XCTAssertEqual(query.text, "31.02.2025")
    }

    // MARK: - Text and dates together

    func testTextAndDateAreSeparated() {
        let query = parser("de_DE").parse("push dezember 2024")
        XCTAssertEqual(query.text, "push")
        XCTAssertEqual(query.dateTokens, [.month(12, year: 2024)])
    }

    func testSeveralTokensAreCombinedWithAnd() {
        let query = parser().parse("december monday")
        XCTAssertEqual(query.dateTokens, [.month(12, year: nil), .weekday(2)])
        // 1 December 2025 is a Monday, 2 December is not.
        XCTAssertTrue(query.matchesDate(date(2025, 12, 1), calendar: calendar))
        XCTAssertFalse(query.matchesDate(date(2025, 12, 2), calendar: calendar))
        XCTAssertFalse(query.matchesDate(date(2025, 11, 3), calendar: calendar))
    }

    func testAQueryWithoutTokensMatchesAnyDate() {
        XCTAssertTrue(parser().parse("bench").matchesDate(date(2019, 1, 1), calendar: calendar))
    }

    func testAWorkoutWithoutADateNeverMatchesADateQuery() {
        XCTAssertFalse(parser().parse("december").matchesDate(nil, calendar: calendar))
    }

    // MARK: - Labels

    func testTokenLabelsReadBackInTheUsersLanguage() {
        let month = SearchDateToken.month(12, year: 2024)
        XCTAssertEqual(month.label(calendar: calendar, locale: Locale(identifier: "en_US")), "December 2024")
        XCTAssertEqual(month.label(calendar: calendar, locale: Locale(identifier: "de_DE")), "Dezember 2024")
        XCTAssertEqual(
            SearchDateToken.month(12, year: nil).label(calendar: calendar, locale: Locale(identifier: "de_DE")),
            "Dezember"
        )
        XCTAssertEqual(
            SearchDateToken.year(2024).label(calendar: calendar, locale: Locale(identifier: "en_US")),
            "2024"
        )
    }
}
