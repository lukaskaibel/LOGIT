//
//  DatabaseTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 15.09.23.
//

import XCTest

@testable import LOGIT

/*
final class DatabaseTests: XCTestCase {

    private var database: Database!
    private var workoutSetRepository: WorkoutSetRepository!
    
    override func setUp() {
        self.database = Database(isPreview: true)
        self.workoutSetRepository = WorkoutSetRepository(database: database, currentWorkoutManager: CurrentWorkoutManager(database: database))
    }

    func testWorkoutSetsGroupedByCalendarComponent() {
        // Tests if there are workout sets with different weeks in the database to make sure that the following tests are correcty testing.
        let workoutSets = workoutSetRepository.getWorkoutSets()
        guard let firstSetDate = workoutSets.first?.workout?.date else {
            XCTFail("No workout sets available in the database.")
            return
        }

        let firstSetWeekOfYear = Calendar.current.dateComponents([.weekOfYear], from: firstSetDate)
            .weekOfYear

        var differentWeekFound = false
        for workoutSet in workoutSets {
            let weekOfYear = Calendar.current
                .dateComponents([.weekOfYear], from: workoutSet.workout?.date ?? Date()).weekOfYear
            if weekOfYear != firstSetWeekOfYear {
                differentWeekFound = true
                break
            }
        }

        XCTAssertTrue(differentWeekFound, "All workout sets belong to the same week.")

        // Test for .day component
        let groupedByDay = workoutSetRepository.getGroupedWorkoutsSets(in: .day)
        XCTAssertTrue(
            groupedByDay.count > 1,
            "Expected there two be workouts on at least 2 different days"
        )
        for group in groupedByDay {
            let referenceDate = group.first?.workout?.date
            let referenceComponents = Calendar.current.dateComponents(
                [.day, .month, .year],
                from: referenceDate ?? Date()
            )
            for set in group {
                let setDate = set.workout?.date
                let setDateComponents = Calendar.current.dateComponents(
                    [.day, .month, .year],
                    from: setDate ?? Date()
                )

                XCTAssertEqual(
                    referenceComponents,
                    setDateComponents,
                    "Expected all sets in the group to belong to the same day"
                )
            }
        }

        // Test for .weekOfYear component
        let groupedByWeek = workoutSetRepository.getGroupedWorkoutsSets(in: .weekOfYear)
        XCTAssertTrue(
            groupedByWeek.count > 1,
            "Expected there to be workouts in at least 2 different weeks"
        )
        for group in groupedByWeek {
            let referenceDate = group.first?.workout?.date
            let referenceComponents = Calendar.current.dateComponents(
                [.weekOfYear, .year],
                from: referenceDate ?? Date()
            )
            for set in group {
                let setDate = set.workout?.date
                let setDateComponents = Calendar.current.dateComponents(
                    [.weekOfYear, .year],
                    from: setDate ?? Date()
                )

                XCTAssertEqual(
                    referenceComponents,
                    setDateComponents,
                    "Expected all sets in the group to belong to the same week of the year"
                )
            }
        }
    }

}
*/
