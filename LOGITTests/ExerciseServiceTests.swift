//
//  ExerciseServiceTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 05.08.23.
//
//  ⚠️ INTEGRATION TESTS - These tests require a valid OPENAI_API_KEY and network access.
//  They make live API calls and are non-deterministic due to AI responses.
//  Set RUN_INTEGRATION_TESTS=true in environment to run these tests.
//

import Combine
import XCTest

@testable import LOGIT

final class ExerciseServiceTests: XCTestCase {
    
    private var database: Database!
    private var exerciseService: ExerciseService!
    private var cancellables = Set<AnyCancellable>()
    
    /// Set this to true to run integration tests locally
    /// In CI, these tests will be skipped unless RUN_INTEGRATION_TESTS env var is set
    private var shouldRunIntegrationTests: Bool {
        ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true"
    }
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        exerciseService = ExerciseService(database: database)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        database = nil
        exerciseService = nil
        super.tearDown()
    }

    // MARK: - Integration Tests (Require OpenAI API)

    func testMatchingExerciseToExistingExercises() throws {
        // Skip if integration tests are disabled
        try XCTSkipUnless(shouldRunIntegrationTests, "Integration tests disabled. Set RUN_INTEGRATION_TESTS=true to run.")
        
        let expectation = XCTestExpectation(description: "Matching Exercise Expectation")
        let exerciseNames = ["Deadlift", "Barbell Benchpress", "Bankdrücken", "Squatss"]

        exerciseService.matchExercisesToExisting(exerciseNames)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case let .failure(error):
                        XCTFail("testMatchingExerciseToExistingExercises failed: \(error.localizedDescription)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { [unowned self] matches in
                    // Verify Deadlift match
                    if let deadliftExercise = database.getExercises(withNameIncluding: "Deadlift").first {
                        XCTAssertEqual(
                            matches["Deadlift"],
                            deadliftExercise,
                            "Unable to match 'Deadlift' to existing exercise"
                        )
                    }
                    
                    // Verify Squatss (typo) matches to Squat
                    if let squatExercise = database.getExercises(withNameIncluding: "Squat").first {
                        XCTAssertEqual(
                            matches["Squatss"],
                            squatExercise,
                            "Unable to match misspelled 'Squatss' to existing 'Squat' exercise"
                        )
                    }
                    
                    // Verify Barbell Benchpress doesn't match Deadlift
                    if let deadliftExercise = database.getExercises(withNameIncluding: "Deadlift").first {
                        XCTAssertNotEqual(
                            matches["Barbell Benchpress"],
                            deadliftExercise,
                            "'Barbell Benchpress' should not match to 'Deadlift'"
                        )
                    }
                    
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 20.0)
    }

    func testCreateExerciseForName() throws {
        // Skip if integration tests are disabled
        try XCTSkipUnless(shouldRunIntegrationTests, "Integration tests disabled. Set RUN_INTEGRATION_TESTS=true to run.")
        
        let expectation = XCTestExpectation(description: "Creating Exercise Expectation")

        exerciseService.createExercise(for: "barbell hip thrusts")
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case let .failure(error):
                        XCTFail("testCreateExerciseForName failed: \(error.localizedDescription)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { [unowned self] exercise in
                    // Verify the exercise was created
                    XCTAssertNotNil(exercise, "Exercise should be created")
                    
                    // Verify the exercise can be found in database
                    let foundExercises = database.getExercises(withNameIncluding: "hip thrust")
                    XCTAssertFalse(foundExercises.isEmpty, "Created exercise should be findable in database")
                    
                    // Verify muscle group assignment (hip thrusts target legs/glutes)
                    XCTAssertEqual(
                        exercise.muscleGroup,
                        MuscleGroup.legs,
                        "Hip thrusts should be categorized as legs exercise"
                    )
                    
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 20.0)
    }
}
