//
//  FuzzySearchService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.12.24.
//

import Foundation
import Ifrit

/// A service that provides fuzzy search capabilities using the Ifrit library.
/// This service wraps Ifrit's Fuse algorithm to provide a consistent search interface across the app.
final class FuzzySearchService {
    
    // MARK: - Singleton
    
    static let shared = FuzzySearchService()
    
    // MARK: - Properties
    
    private let fuse: Fuse
    
    // MARK: - Init
    
    private init() {
        // Configure Fuse with optimal settings for search-as-you-type
        fuse = Fuse(
            distance: 100,         // How close match must be to fuzzy location
            threshold: 0.4,        // Lower = stricter matching (0.0 = exact, 1.0 = match anything)
            tokenize: true         // Search individual words and full string
        )
    }
    
    // MARK: - Search Methods
    
    /// Searches exercises using fuzzy matching on display name
    /// - Parameters:
    ///   - searchText: The search query
    ///   - exercises: The array of exercises to search
    /// - Returns: Filtered and sorted exercises based on fuzzy match score
    func searchExercises(_ searchText: String, in exercises: [Exercise]) -> [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        
        let results = fuse.searchSync(searchText, in: exercises, by: \.properties)
        return results.map { exercises[$0.index] }
    }
    
    /// Searches workouts using fuzzy matching on name
    /// - Parameters:
    ///   - searchText: The search query
    ///   - workouts: The array of workouts to search
    /// - Returns: Filtered and sorted workouts based on fuzzy match score
    func searchWorkouts(_ searchText: String, in workouts: [Workout]) -> [Workout] {
        guard !searchText.isEmpty else { return workouts }
        
        let results = fuse.searchSync(searchText, in: workouts, by: \.properties)
        return results.map { workouts[$0.index] }
    }
    
    /// Searches templates using fuzzy matching on name
    /// - Parameters:
    ///   - searchText: The search query
    ///   - templates: The array of templates to search
    /// - Returns: Filtered and sorted templates based on fuzzy match score
    func searchTemplates(_ searchText: String, in templates: [Template]) -> [Template] {
        guard !searchText.isEmpty else { return templates }
        
        let results = fuse.searchSync(searchText, in: templates, by: \.properties)
        return results.map { templates[$0.index] }
    }
    
    /// Searches measurement entries using fuzzy matching on type description
    /// - Parameters:
    ///   - searchText: The search query
    ///   - measurements: The array of measurement entries to search
    /// - Returns: Filtered and sorted measurement entries based on fuzzy match score
    func searchMeasurements(_ searchText: String, in measurements: [MeasurementEntry]) -> [MeasurementEntry] {
        guard !searchText.isEmpty else { return measurements }
        
        let results = fuse.searchSync(searchText, in: measurements, by: \.properties)
        return results.map { measurements[$0.index] }
    }
    
    /// Generic search in an array of strings
    /// - Parameters:
    ///   - searchText: The search query
    ///   - strings: The array of strings to search
    /// - Returns: Matching strings sorted by relevance
    func search(_ searchText: String, in strings: [String]) -> [String] {
        guard !searchText.isEmpty else { return strings }
        
        let results = fuse.searchSync(searchText, in: strings)
        return results.map { strings[$0.index] }
    }
}
