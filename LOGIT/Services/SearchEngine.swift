//
//  SearchEngine.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.09.25.
//

import Foundation

/// What a search turned up, grouped the way the Search tab shows it.
struct SearchResults {
    var exercises: [Exercise] = []
    var workouts: [Workout] = []
    var templates: [Template] = []

    var isEmpty: Bool { exercises.isEmpty && workouts.isEmpty && templates.isEmpty }
}

/// The one place that decides what a search means: it parses the raw text into a
/// `SearchQuery` (see `SearchQueryParser`), applies the date constraints, and
/// hands the rest to `FuzzySearchService` for name matching.
///
/// Screens do not filter on their own — they pass what the user typed in and
/// render what comes back, so "dezember" behaves the same everywhere.
final class SearchEngine {

    // MARK: - Singleton

    static let shared = SearchEngine()

    // MARK: - Properties

    private let fuzzySearch: FuzzySearchService
    private let calendar: Calendar

    // MARK: - Init

    init(fuzzySearch: FuzzySearchService = .shared, calendar: Calendar = .current) {
        self.fuzzySearch = fuzzySearch
        self.calendar = calendar
    }

    // MARK: - Searching

    /// Parses `searchText` and returns the results for it.
    ///
    /// A query that names a date — "Dezember", "last week", "15.09.2025" — only
    /// returns workouts, because a workout is the only thing in the app that
    /// happened on a day. Exercises and templates are not silently dropped: the
    /// Search tab says which date it understood, right above the results.
    func search(
        _ searchText: String,
        exercises: [Exercise],
        workouts: [Workout],
        templates: [Template],
        parser: SearchQueryParser = SearchQueryParser()
    ) -> SearchResults {
        let query = parser.parse(searchText)
        return results(for: query, exercises: exercises, workouts: workouts, templates: templates)
    }

    func results(
        for query: SearchQuery,
        exercises: [Exercise],
        workouts: [Workout],
        templates: [Template]
    ) -> SearchResults {
        guard !query.isEmpty else { return SearchResults() }

        let datedWorkouts = query.hasDateConstraint
            ? workouts.filter { query.matchesDate($0.date, calendar: calendar) }
            : workouts

        guard !query.text.isEmpty else {
            // A pure date query: every workout on those days, newest first, with
            // no name matching to narrow it down.
            return SearchResults(workouts: datedWorkouts)
        }

        let matchedWorkouts = fuzzySearch.searchWorkouts(query.text, in: datedWorkouts)
        guard !query.hasDateConstraint else {
            return SearchResults(workouts: matchedWorkouts)
        }

        return SearchResults(
            exercises: fuzzySearch.searchExercises(query.text, in: exercises),
            workouts: matchedWorkouts,
            templates: fuzzySearch.searchTemplates(query.text, in: templates)
        )
    }
}
