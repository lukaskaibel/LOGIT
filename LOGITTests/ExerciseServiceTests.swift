//
//  ExerciseServiceTests.swift
//  ExerciseServiceTests
//
//  Created by Lukas Kaibel on 05.08.23.
//

import Combine
import XCTest

@testable import LOGIT

final class ExerciseServiceTests: XCTestCase {
    let database = Database(isPreview: true)
    private lazy var exerciseService = ExerciseService(database: database)

    private var cancellables = [AnyCancellable]()

    func testMatchingExerciseToExistingExercises() throws {
        let expectation = XCTestExpectation(description: "Matching Exercise Expectation")
        let exerciseNames = ["Deadlift", "Barbell Benchpress", "Bankdrücken", "Squatss"]

        exerciseService.matchExercisesToExisting(exerciseNames)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case let .failure(error):
                        XCTFail(
                            "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: \(error.localizedDescription)"
                        )
                    }
                    expectation.fulfill() // Fulfill the expectation when completed
                },
                receiveValue: { [unowned self] matches in
                    exerciseNames.forEach { _ in }
                    XCTAssertEqual(
                        matches["Deadlift"],
                        database.getExercises(withNameIncluding: "Deadlift").first!,
                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Unable to match 'Deadlift' to existing exercise"
                    )
                    XCTAssertNotEqual(
                        matches["Barbell Benchpress"],
                        database.getExercises(withNameIncluding: "Deadlift").first!,
                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Unable to match 'Barbell Benchpress' to existing exercise"
                    )
                    XCTAssertEqual(
                        matches["Squatss"],
                        database.getExercises(withNameIncluding: "Squat").first!,
                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Unable to match 'Barbell Benchpress' to existing exercise"
                    )
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 20.0)
    }

    func testCreateExerciseForName() throws {
        let expectation = XCTestExpectation(description: "Creating Exercise Expectation")

//        exerciseService.createExercise(for: "Bulgarian Split Squats")
//            .sink(
//                receiveCompletion: { completion in
//                    switch completion {
//                    case .finished:
//                        print("Completed")
//                        break
//                    case .failure(let error):
//                        XCTFail(
//                            "ExerciseServiceTests: testCreateExerciseForName failed: \(error.localizedDescription)"
//                        )
//                    }
//                    expectation.fulfill()  // Fulfill the expectation when completed
//                },
//                receiveValue: { [unowned self] exercise in
//                    XCTAssertEqual(
//                        "Bulgarian Split Squats",
//                        database.getExercises(withNameIncluding: "Bulgarian").first!.name,
//                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Unable to create Exercise from 'Bulgarian Split Squats'"
//                    )
//                    XCTAssertEqual(
//                        MuscleGroup.legs,
//                        database.getExercises(withNameIncluding: "Bulgarian").first!.muscleGroup,
//                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Wrong Muscle Group for 'Bulgarian Split Squats'"
//                    )
//                    expectation.fulfill()
//                }
//            )
//            .store(in: &cancellables)

        exerciseService.createExercise(for: "barbell hip thrusts")
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("Completed")
                    case let .failure(error):
                        XCTFail(
                            "ExerciseServiceTests: testCreateExerciseForName failed: \(error.localizedDescription)"
                        )
                    }
                    expectation.fulfill() // Fulfill the expectation when completed
                },
                receiveValue: { [unowned self] _ in
                    XCTAssertEqual(
                        "barbell hip thrusts",
                        database.getExercises(withNameIncluding: "thrust").first!.name,
                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Unable to create Exercise from 'barbell hip thrusts'"
                    )
                    XCTAssertEqual(
                        MuscleGroup.legs,
                        database.getExercises(withNameIncluding: "thrust").first!.muscleGroup,
                        "ExerciseServiceTests: testMatchingExerciseToExistingExercises failed: Wrong Muscle Group for 'barbell hip thrusts'"
                    )
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 20.0)
    }
}
