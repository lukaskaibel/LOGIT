//
//  WorkoutSetRepositoryTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 17.01.25.
//

import Foundation
@testable import LOGIT
import Testing
import XCTest

struct WorkoutSetRepositoryTests {
    let database = Database(isPreview: true)
    lazy var currentWorkoutManager = CurrentWorkoutManager(database: database)
    lazy var workoutSetRepository = WorkoutSetRepository(database: database, currentWorkoutManager: currentWorkoutManager)

    @Test mutating func getWorkoutSetsFromTo() async throws {
        var workoutSets = workoutSetRepository.getWorkoutSets(from: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now), to: .now)
        assert(workoutSets.count == 14)
        workoutSets = workoutSetRepository.getWorkoutSets(from: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: .now), to: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now))
        assert(workoutSets.count == 45)
    }
}
