//
//  ExerciseSuggestionService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.04.26.
//

import CoreData
import Foundation

final class ExerciseSuggestionService: ObservableObject {

    // MARK: - Constants

    private static let lambda: Double = 0.01
    private static let withinWorkoutMaxOrder = 3
    private static let crossWorkoutMaxOrder = 6
    private static let withinWorkoutWeight: Double = 0.7
    private static let crossWorkoutWeight: Double = 0.3
    private static let absoluteMinThreshold: Double = 0.10
    private static let relativeThreshold: Double = 0.15
    private static let maxSuggestions = 5
    private static let minWorkoutsRequired = 5

    // MARK: - Properties

    private let database: Database

    // MARK: - Init

    init(database: Database) {
        self.database = database
    }

    // MARK: - Public API

    func suggestedExercises(
        currentWorkoutExercises: [Exercise],
        allExercises: [Exercise]
    ) -> [Exercise] {
        let completedWorkouts = fetchCompletedWorkouts()
        guard completedWorkouts.count >= Self.minWorkoutsRequired else { return [] }

        let excludedIDs = Set(currentWorkoutExercises.compactMap(\.id))
        let position = currentWorkoutExercises.count

        let withinWorkoutScores = scoreWithinWorkout(
            currentWorkoutExercises: currentWorkoutExercises,
            completedWorkouts: completedWorkouts,
            excluding: excludedIDs
        )

        let crossWorkoutScores = scoreCrossWorkoutPosition(
            position: position,
            completedWorkouts: completedWorkouts,
            excluding: excludedIDs
        )

        let combined = combineScores(
            withinWorkoutScores,
            crossWorkoutScores,
            withinWeight: Self.withinWorkoutWeight,
            crossWeight: Self.crossWorkoutWeight
        )

        let exerciseByID = Dictionary(
            allExercises.compactMap { e in e.id.map { ($0, e) } },
            uniquingKeysWith: { first, _ in first }
        )

        return filterByThreshold(combined)
            .compactMap { exerciseByID[$0.0] }
    }

    func suggestedSupersetPartners(
        forPrimary primary: Exercise,
        currentWorkoutExercises: [Exercise],
        allExercises: [Exercise]
    ) -> [Exercise] {
        let completedWorkouts = fetchCompletedWorkouts()
        guard completedWorkouts.count >= Self.minWorkoutsRequired else { return [] }

        guard let primaryID = primary.id else { return [] }
        var excludedIDs = Set(currentWorkoutExercises.compactMap(\.id))
        excludedIDs.insert(primaryID)

        let scores = scoreSupersetPartners(
            primaryID: primaryID,
            completedWorkouts: completedWorkouts,
            excluding: excludedIDs
        )

        let exerciseByID = Dictionary(
            allExercises.compactMap { e in e.id.map { ($0, e) } },
            uniquingKeysWith: { first, _ in first }
        )

        return filterByThreshold(scores)
            .compactMap { exerciseByID[$0.0] }
    }

    // MARK: - Core Algorithm

    /// Variable-order Markov scoring: given a context and historical sequences,
    /// score each possible next element using exponential time decay.
    /// Context must be non-empty; first-exercise prediction is handled by scoreCrossWorkoutPosition.
    private static func scoreNextElements(
        context: [UUID],
        sequences: [(elements: [UUID], date: Date)],
        maxOrder: Int,
        lambda: Double,
        excluding: Set<UUID>,
        now: Date = Date()
    ) -> [(UUID, Double)] {
        guard !context.isEmpty else { return [] }
        var scores: [UUID: Double] = [:]

        for k in 1...max(maxOrder, 1) {
            guard k <= context.count else { continue }
            let contextWindow = Array(context.suffix(k))

            for (elements, date) in sequences {
                let daysAgo = now.timeIntervalSince(date) / 86400.0
                let decayWeight = exp(-lambda * max(daysAgo, 0))
                let orderWeight = Double(k)

                for i in 0..<elements.count - 1 {
                    let windowEnd = i + k
                    guard windowEnd < elements.count else { break }
                    let candidate = Array(elements[i..<windowEnd])
                    if candidate == contextWindow {
                        let nextID = elements[windowEnd]
                        guard !excluding.contains(nextID) else { continue }
                        scores[nextID, default: 0] += decayWeight * orderWeight
                    }
                }
            }
        }

        return scores.sorted { $0.value > $1.value }
    }

    // MARK: - Signal A: Within-Workout Markov

    private func scoreWithinWorkout(
        currentWorkoutExercises: [Exercise],
        completedWorkouts: [Workout],
        excluding: Set<UUID>
    ) -> [(UUID, Double)] {
        guard !currentWorkoutExercises.isEmpty else { return [] }

        let context = currentWorkoutExercises.compactMap(\.id)
        let sequences: [(elements: [UUID], date: Date)] = completedWorkouts.compactMap { workout in
            let exerciseIDs = workout.setGroups.compactMap(\.exercise?.id)
            guard !exerciseIDs.isEmpty, let date = workout.date else { return nil }
            return (exerciseIDs, date)
        }

        return Self.scoreNextElements(
            context: context,
            sequences: sequences,
            maxOrder: Self.withinWorkoutMaxOrder,
            lambda: Self.lambda,
            excluding: excluding
        )
    }

    // MARK: - Signal B: Cross-Workout Position-Cycle Markov

    private func scoreCrossWorkoutPosition(
        position: Int,
        completedWorkouts: [Workout],
        excluding: Set<UUID>
    ) -> [(UUID, Double)] {
        // Build the sequence of exercises at this position across workouts
        var positionSequenceEntries: [(exerciseID: UUID, date: Date)] = []
        for workout in completedWorkouts {
            let exerciseIDs = workout.setGroups.compactMap(\.exercise?.id)
            guard position < exerciseIDs.count, let date = workout.date else { continue }
            positionSequenceEntries.append((exerciseIDs[position], date))
        }

        guard !positionSequenceEntries.isEmpty else { return [] }

        // The cross-workout position sequence treated as one long sequence for Markov matching.
        // Context is the FULL sequence (including the most recent workout) because we want to
        // predict what comes AFTER the latest observation, not re-predict the latest itself.
        let fullSequence = positionSequenceEntries.map(\.exerciseID)
        let context = fullSequence

        // We can't use scoreNextElements directly since each entry has its own date.
        // Instead, implement the variable-order Markov inline for this cross-workout sequence.
        var scores: [UUID: Double] = [:]
        let now = Date()

        for k in 1...Self.crossWorkoutMaxOrder {
            guard k <= context.count else { continue }
            let contextWindow = Array(context.suffix(k))
            let upperBound = fullSequence.count - k - 1
            guard upperBound >= 0 else { continue }

            for i in 0...upperBound {
                let candidate = Array(fullSequence[i..<(i + k)])
                guard candidate == contextWindow else { continue }
                let nextIndex = i + k
                guard nextIndex < fullSequence.count else { continue }
                let nextID = fullSequence[nextIndex]
                guard !excluding.contains(nextID) else { continue }
                let date = positionSequenceEntries[nextIndex].date
                let daysAgo = now.timeIntervalSince(date) / 86400.0
                let decayWeight = exp(-Self.lambda * max(daysAgo, 0))
                let orderWeight = Double(k)
                scores[nextID, default: 0] += decayWeight * orderWeight
            }
        }

        // Fallback: if no pattern matched, use decayed frequency at this position
        if scores.isEmpty {
            for entry in positionSequenceEntries {
                guard !excluding.contains(entry.exerciseID) else { continue }
                let daysAgo = now.timeIntervalSince(entry.date) / 86400.0
                let decayWeight = exp(-Self.lambda * max(daysAgo, 0))
                scores[entry.exerciseID, default: 0] += decayWeight
            }
        }

        return scores.sorted { $0.value > $1.value }
    }

    // MARK: - Superset Pairing

    private func scoreSupersetPartners(
        primaryID: UUID,
        completedWorkouts: [Workout],
        excluding: Set<UUID>
    ) -> [(UUID, Double)] {
        var scores: [UUID: Double] = [:]
        let now = Date()

        for workout in completedWorkouts {
            guard let date = workout.date else { continue }
            let daysAgo = now.timeIntervalSince(date) / 86400.0
            let decayWeight = exp(-Self.lambda * max(daysAgo, 0))

            for setGroup in workout.setGroups {
                guard setGroup.setType == .superSet,
                      setGroup.exercise?.id == primaryID,
                      let secondaryID = setGroup.secondaryExercise?.id,
                      !excluding.contains(secondaryID)
                else { continue }
                scores[secondaryID, default: 0] += decayWeight
            }
        }

        return scores.sorted { $0.value > $1.value }
    }

    // MARK: - Score Combination

    private func combineScores(
        _ scoresA: [(UUID, Double)],
        _ scoresB: [(UUID, Double)],
        withinWeight: Double,
        crossWeight: Double
    ) -> [(UUID, Double)] {
        var combined: [UUID: Double] = [:]

        for (id, score) in scoresA {
            combined[id, default: 0] += withinWeight * score
        }
        for (id, score) in scoresB {
            combined[id, default: 0] += crossWeight * score
        }

        return combined.sorted { $0.value > $1.value }
    }

    // MARK: - Threshold Filtering

    private func filterByThreshold(_ scores: [(UUID, Double)]) -> [(UUID, Double)] {
        guard let topScore = scores.first?.1, topScore > 0 else { return [] }

        let totalScore = scores.reduce(0) { $0 + $1.1 }
        guard totalScore > 0 else { return [] }

        let topNormalized = topScore / totalScore
        guard topNormalized >= Self.absoluteMinThreshold else { return [] }

        let cutoff = topScore * Self.relativeThreshold
        return Array(
            scores
                .filter { $0.1 >= cutoff }
                .prefix(Self.maxSuggestions)
        )
    }

    // MARK: - Data Fetching

    private func fetchCompletedWorkouts() -> [Workout] {
        let workouts = database.fetch(
            Workout.self,
            sortingKey: "date",
            ascending: true,
            predicate: NSPredicate(format: "isCurrentWorkout == NO")
        ) as? [Workout]
        return workouts ?? []
    }
}
