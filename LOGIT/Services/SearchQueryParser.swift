//
//  SearchQueryParser.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.09.25.
//

import Foundation

/// Turns what the user typed into a `SearchQuery`: the words that name a date
/// become `SearchDateToken`s, everything else stays free text.
///
/// Month and weekday names come straight from `DateFormatter`'s localised
/// symbols, so "Dezember", "décembre", "12月" and "December" all work on the
/// device that speaks that language — there is no word list to keep in sync with
/// `Localizable.strings`. English is always accepted as well, because the app's
/// language and the keyboard a person types on are not always the same.
///
/// Deliberately *not* built on `NSDataDetector`: it reads a bare "2024" as the
/// time 20:24 and guesses wildly outside English, which makes search-as-you-type
/// unpredictable. Everything here is explicit and unit-tested instead.
///
/// A name beats a guessed date. A month or weekday typed only in part ("mit",
/// "Di", "dec") stays text when a word in an exercise or template name starts
/// with it, so "Bankdrücken mit Kurzhanteln" and "Dips" still find the exercise
/// instead of turning into Wednesday and Tuesday. A name typed in full
/// ("Mittwoch", "December") is always a date.
struct SearchQueryParser {

    // MARK: - Configuration

    private let calendar: Calendar
    private let locale: Locale
    private let now: () -> Date
    private let nameWords: NameWords

    /// The oldest and newest year a bare four-digit number is read as a year.
    private static let yearRange = 1900...2100

    /// - Parameter names: the exercise and template names a partly typed date word must not
    ///   swallow (see the type's documentation). Workout names are left out on purpose: they are
    ///   generated from the weekday ("Wednesday Afternoon Workout"), so every weekday abbreviation
    ///   would start one of them and could never be a date.
    init(
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping () -> Date = { Date.now },
        names: [String] = []
    ) {
        self.calendar = calendar
        self.locale = locale
        self.now = now
        self.nameWords = NameWords(names: names, locale: locale)
    }

    // MARK: - Parsing

    func parse(_ raw: String) -> SearchQuery {
        let words = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return SearchQuery(text: "", dateTokens: []) }

        var classified = classify(words)
        mergeMonthsAndYears(&classified)

        var text: [String] = []
        var tokens: [SearchDateToken] = []
        for word in classified {
            switch word {
            case let .free(value): text.append(value)
            case let .token(token): tokens.append(token)
            case let .month(month): tokens.append(.month(month, year: nil))
            case let .year(year): tokens.append(.year(year))
            case .consumed: break
            }
        }

        return SearchQuery(text: text.joined(separator: " "), dateTokens: tokens)
    }

    // MARK: - Classification

    private enum ClassifiedWord {
        case free(String)
        case token(SearchDateToken)
        /// A month name still looking for a year next to it.
        case month(Int)
        /// A year still looking for a month next to it.
        case year(Int)
        /// A later word of a phrase like "last week".
        case consumed
    }

    /// The most words a relative phrase runs to — "La semaine dernière", "Il mese scorso".
    private static let longestPhraseWordCount = 3

    private func classify(_ words: [String]) -> [ClassifiedWord] {
        var result = [ClassifiedWord]()
        var index = 0
        while index < words.count {
            // Multi-word relative phrases before single words, longest first, so "last" is never
            // read on its own and the "dernière" of "La semaine dernière" is not read again as the
            // start of "Dernière année".
            if let phrase = phraseToken(in: words, at: index) {
                result.append(.token(phrase.token))
                result.append(contentsOf: Array(repeating: .consumed, count: phrase.wordCount - 1))
                index += phrase.wordCount
                continue
            }
            result.append(classify(words[index]))
            index += 1
        }
        return result
    }

    /// The relative phrase starting at `index` that spans two or more words, preferring the longest.
    private func phraseToken(in words: [String], at index: Int) -> (token: SearchDateToken, wordCount: Int)? {
        let longest = min(Self.longestPhraseWordCount, words.count - index)
        guard longest >= 2 else { return nil }
        for count in stride(from: longest, through: 2, by: -1) {
            let phrase = words[index ..< index + count].joined(separator: " ")
            if let token = relativeToken(for: phrase) {
                return (token, count)
            }
        }
        return nil
    }

    private func classify(_ word: String) -> ClassifiedWord {
        if let token = numericToken(for: word) { return .token(token) }
        if let year = year(for: word) { return .year(year) }
        if let token = relativeToken(for: word) { return .token(token) }
        if let month = month(for: word) { return .month(month) }
        if let weekday = weekday(for: word) { return .token(.weekday(weekday)) }
        return .free(word)
    }

    /// Folds a month and a year that sit next to each other — in either order,
    /// so both "Dezember 2024" and "2024 Dezember" resolve to one token.
    private func mergeMonthsAndYears(_ words: inout [ClassifiedWord]) {
        for index in words.indices.dropLast() {
            let next = index + 1
            switch (words[index], words[next]) {
            case let (.month(month), .year(year)), let (.year(year), .month(month)):
                words[index] = .token(.month(month, year: year))
                words[next] = .consumed
            default:
                continue
            }
        }
    }

    // MARK: - Word readers

    private func year(for word: String) -> Int? {
        guard word.count == 4, let value = Int(word), Self.yearRange.contains(value) else { return nil }
        return value
    }

    private func month(for word: String) -> Int? {
        guard let month = uniqueIndex(of: word, in: tables.months),
              isDateRatherThanName(word, fullNames: tables.fullMonthNames)
        else { return nil }
        return month
    }

    private func weekday(for word: String) -> Int? {
        guard let weekday = uniqueIndex(of: word, in: tables.weekdays),
              isDateRatherThanName(word, fullNames: tables.fullWeekdayNames)
        else { return nil }
        return weekday
    }

    /// Whether a word that reads as a date should be taken as one. A name typed in full always is;
    /// anything shorter gives way to an exercise or template name that one of its words starts with.
    private func isDateRatherThanName(_ word: String, fullNames: Set<String>) -> Bool {
        let normalized = normalize(word)
        return fullNames.contains(normalized) || !nameWords.hasWord(startingWith: normalized)
    }

    /// The 1-based index a word points at, but only when every symbol it could be
    /// a prefix of agrees. "jun" is June, "ju" is refused for being too short and
    /// "j" never matches at all.
    private func uniqueIndex(of word: String, in table: [(symbol: String, index: Int)]) -> Int? {
        let normalized = normalize(word)
        guard normalized.count >= 2 else { return nil }
        var matches = Set<Int>()
        for entry in table {
            let symbol = entry.symbol
            // A symbol of one or two characters (ja "1月", ko "1월") has to be
            // typed in full; anything longer may be abbreviated to 3 characters.
            guard normalized.count >= max(2, min(3, symbol.count)) else { continue }
            guard symbol.hasPrefix(normalized) else { continue }
            matches.insert(entry.index)
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Reads the shapes a date is actually typed in: `15.09.2025`, `15/9/2025`,
    /// `2025-09-15`, `09/2025`, `2025-09`. Which of the first two numbers is the
    /// day follows the locale, unless one of them is too large to be a month.
    private func numericToken(for word: String) -> SearchDateToken? {
        let parts = word.split(whereSeparator: { ".-/".contains($0) }).map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        let numbers = parts.compactMap(Int.init)
        guard numbers.count == parts.count else { return nil }

        switch numbers.count {
        case 2:
            // A month and a year, in whichever order the year appears.
            if let year = year(for: parts[0]), (1...12).contains(numbers[1]) {
                return .month(numbers[1], year: year)
            }
            if let year = year(for: parts[1]), (1...12).contains(numbers[0]) {
                return .month(numbers[0], year: year)
            }
            return nil
        case 3:
            guard let (day, month, year) = dayMonthYear(numbers) else { return nil }
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.dateComponents([.day], from: date).day == day
            else { return nil }
            return .day(date)
        default:
            return nil
        }
    }

    private func dayMonthYear(_ numbers: [Int]) -> (day: Int, month: Int, year: Int)? {
        // ISO first: a leading four-digit year is never a day.
        if Self.yearRange.contains(numbers[0]), numbers[0] > 31 {
            guard (1...12).contains(numbers[1]), (1...31).contains(numbers[2]) else { return nil }
            return (numbers[2], numbers[1], numbers[0])
        }
        guard Self.yearRange.contains(numbers[2]) else { return nil }
        let first = numbers[0], second = numbers[1]
        guard (1...31).contains(first), (1...31).contains(second) else { return nil }
        if first > 12, second <= 12 { return (first, second, numbers[2]) }
        if second > 12, first <= 12 { return (second, first, numbers[2]) }
        guard first <= 12, second <= 12 else { return nil }
        return dayComesFirst ? (first, second, numbers[2]) : (second, first, numbers[2])
    }

    /// Whether this locale writes 15.09. rather than 9/15.
    private var dayComesFirst: Bool {
        guard let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale),
              let day = format.firstIndex(of: "d"),
              let month = format.firstIndex(of: "M")
        else { return true }
        return day < month
    }

    // MARK: - Relative phrases

    /// Matches with the spaces taken out on both sides, so "이번주" finds "이번 주" and the words
    /// of a phrase can be split however the keyboard split them. A phrase may be typed in part once
    /// three characters are in; one of only two characters (ja 今日, ko 오늘) has to be typed in full.
    private func relativeToken(for phrase: String) -> SearchDateToken? {
        let normalized = Self.removingSpaces(normalize(phrase))
        guard !normalized.isEmpty else { return nil }
        let matches = tables.relativePhrases.filter {
            let candidate = Self.removingSpaces($0.phrase)
            return normalized.count >= min(3, candidate.count) && candidate.hasPrefix(normalized)
        }
        guard let first = matches.first,
              matches.allSatisfy({ $0.kind == first.kind })
        else { return nil }
        // A single word only begun ("hie", "heu") gives way to a name that starts the same way; a
        // phrase typed in full, or one spanning words, is a date.
        let isComplete = matches.contains { Self.removingSpaces($0.phrase) == normalized }
        if !isComplete, !phrase.contains(where: \.isWhitespace),
           nameWords.hasWord(startingWith: normalized)
        {
            return nil
        }
        return token(for: first.kind)
    }

    private static func removingSpaces(_ string: String) -> String {
        string.filter { !$0.isWhitespace }
    }

    enum RelativeKind: Hashable {
        case today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, lastYear
    }

    private func token(for kind: RelativeKind) -> SearchDateToken? {
        let today = now()
        switch kind {
        case .today:
            return .day(today)
        case .yesterday:
            guard let date = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
            return .day(date)
        case .thisWeek:
            return weekToken(offset: 0, name: NSLocalizedString("thisWeek", comment: ""))
        case .lastWeek:
            return weekToken(offset: -1, name: NSLocalizedString("lastWeek", comment: ""))
        case .thisMonth:
            return monthToken(offset: 0)
        case .lastMonth:
            return monthToken(offset: -1)
        case .thisYear:
            return .year(calendar.component(.year, from: today))
        case .lastYear:
            return .year(calendar.component(.year, from: today) - 1)
        }
    }

    private func weekToken(offset: Int, name: String) -> SearchDateToken? {
        guard let date = calendar.date(byAdding: .weekOfYear, value: offset, to: now()),
              let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        else { return nil }
        return .span(interval, name: name)
    }

    private func monthToken(offset: Int) -> SearchDateToken? {
        guard let date = calendar.date(byAdding: .month, value: offset, to: now()) else { return nil }
        let components = calendar.dateComponents([.month, .year], from: date)
        guard let month = components.month, let year = components.year else { return nil }
        return .month(month, year: year)
    }

    static let relativeKeys: [(key: String, kind: RelativeKind)] = [
        ("today", .today),
        ("yesterday", .yesterday),
        ("thisWeek", .thisWeek),
        ("lastWeek", .lastWeek),
        ("thisMonth", .thisMonth),
        ("lastMonth", .lastMonth),
        ("thisYear", .thisYear),
        ("lastYear", .lastYear),
    ]

    // MARK: - Normalising

    private func normalize(_ string: String) -> String {
        Tables.normalize(string, locale: locale)
    }

    // MARK: - Word tables

    private var tables: Tables { Tables.forLocale(locale, calendar: calendar) }

    /// The month names, weekday names and relative phrases this parser matches
    /// against, already normalised.
    ///
    /// Built once per language and kept: every one of them needs a `DateFormatter`
    /// or a bundle lookup, and the parser runs on every keystroke in the Search
    /// tab — rebuilding these per word made typing do real work for nothing.
    struct Tables {
        let months: [(symbol: String, index: Int)]
        let weekdays: [(symbol: String, index: Int)]
        /// The months and weekdays written out in full ("dezember", "mittwoch"), which are dates
        /// whatever a name in the library starts with.
        let fullMonthNames: Set<String>
        let fullWeekdayNames: Set<String>
        let relativePhrases: [(phrase: String, kind: RelativeKind)]

        private static let cache = Cache()

        static func forLocale(_ locale: Locale, calendar: Calendar) -> Tables {
            cache.tables(for: locale, calendar: calendar)
        }

        static func normalize(_ string: String, locale: Locale) -> String {
            string
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
                // The keyboard types a curly apostrophe ("aujourd’hui", "quest’anno") while the
                // strings files use a straight one.
                .replacingOccurrences(of: "\u{2019}", with: "'")
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        }

        fileprivate final class Cache {
            private let lock = NSLock()
            private var storage = [String: Tables]()

            func tables(for locale: Locale, calendar: Calendar) -> Tables {
                let key = "\(locale.identifier)|\(calendar.identifier.hashValue)"
                lock.lock()
                defer { lock.unlock() }
                if let cached = storage[key] { return cached }
                let tables = Tables(locale: locale, calendar: calendar)
                storage[key] = tables
                return tables
            }
        }

        fileprivate init(locale: Locale, calendar: Calendar) {
            let formatters = [locale, Locale(identifier: "en_US_POSIX")].map { locale -> DateFormatter in
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = locale
                return formatter
            }

            func symbols(_ keyPaths: [KeyPath<DateFormatter, [String]?>]) -> [(symbol: String, index: Int)] {
                var table = [(symbol: String, index: Int)]()
                for formatter in formatters {
                    for keyPath in keyPaths {
                        guard let symbols = formatter[keyPath: keyPath] else { continue }
                        for (offset, symbol) in symbols.enumerated() {
                            table.append(
                                (symbol: Tables.normalize(symbol, locale: locale), index: offset + 1)
                            )
                        }
                    }
                }
                return table
            }

            months = symbols([
                \.monthSymbols, \.standaloneMonthSymbols, \.shortMonthSymbols, \.shortStandaloneMonthSymbols,
            ])
            weekdays = symbols([
                \.weekdaySymbols, \.standaloneWeekdaySymbols, \.shortWeekdaySymbols, \.shortStandaloneWeekdaySymbols,
            ])
            fullMonthNames = Set(symbols([\.monthSymbols, \.standaloneMonthSymbols]).map(\.symbol))
            fullWeekdayNames = Set(symbols([\.weekdaySymbols, \.standaloneWeekdaySymbols]).map(\.symbol))

            // Every spelling of a relative phrase this device should understand:
            // the wording the app already prints for it (the same strings the
            // History screen uses) in the parser's language and in the app's,
            // plus English.
            var phrases = [(phrase: String, kind: RelativeKind)]()
            for bundle in [Tables.bundle(for: locale), Bundle.main] {
                for entry in SearchQueryParser.relativeKeys {
                    phrases.append(
                        (phrase: Tables.normalize(
                            bundle.localizedString(forKey: entry.key, value: entry.key, table: nil),
                            locale: locale
                         ),
                         kind: entry.kind)
                    )
                }
            }
            let english: [(String, RelativeKind)] = [
                ("today", .today),
                ("yesterday", .yesterday),
                ("this week", .thisWeek),
                ("last week", .lastWeek),
                ("this month", .thisMonth),
                ("last month", .lastMonth),
                ("this year", .thisYear),
                ("last year", .lastYear),
            ]
            relativePhrases = phrases + english.map { (phrase: $0.0, kind: $0.1) }
        }

        /// The `.lproj` for a locale. Month names come from `DateFormatter` and
        /// follow the locale on their own; these phrases only exist as app
        /// strings, so they have to be looked up in that language's bundle.
        private static func bundle(for locale: Locale) -> Bundle {
            let preferred = Bundle.preferredLocalizations(
                from: Bundle.main.localizations,
                forPreferences: [locale.identifier]
            )
            guard let name = preferred.first,
                  let path = Bundle.main.path(forResource: name, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else { return .main }
            return bundle
        }
    }

    // MARK: - Names

    /// The words of the library's exercise and template names, normalised the way a typed word is.
    /// Split and normalised on first use, because only a partly typed date word ever asks — most
    /// keystrokes never do.
    final class NameWords {
        private let names: [String]
        private let locale: Locale
        private lazy var words: [String] = names
            .flatMap { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }
            .map { Tables.normalize(String($0), locale: locale) }

        init(names: [String], locale: Locale) {
            self.names = names
            self.locale = locale
        }

        func hasWord(startingWith prefix: String) -> Bool {
            !prefix.isEmpty && words.contains { $0.hasPrefix(prefix) }
        }
    }
}
