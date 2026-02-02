//
//  ServicesTests.swift
//  LOGITTests
//
//  Tests for non-AI dependent services
//

import XCTest

@testable import LOGIT

// MARK: - DefaultExerciseService Tests

final class DefaultExerciseServiceTests: XCTestCase {
    
    private var database: Database!
    private var service: DefaultExerciseService!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        service = DefaultExerciseService(database: database)
    }
    
    override func tearDown() {
        database = nil
        service = nil
        super.tearDown()
    }
    
    func testLoadDefaultExercisesIfNeeded() {
        // The service should be able to load without crashing
        // Note: This tests that the JSON parsing works correctly
        service.loadDefaultExercisesIfNeeded()
        
        // After loading, there should be exercises in the database
        let exercises = database.fetch(Exercise.self) as! [Exercise]
        XCTAssertFalse(exercises.isEmpty, "Should have exercises after loading defaults")
    }
    
    func testDefaultExercisesHaveRequiredFields() {
        service.loadDefaultExercisesIfNeeded()
        
        let exercises = database.fetch(Exercise.self) as! [Exercise]
        
        for exercise in exercises {
            XCTAssertNotNil(exercise.id, "Every exercise should have an ID")
            XCTAssertNotNil(exercise.name, "Every exercise should have a name")
            XCTAssertFalse(exercise.name?.isEmpty ?? true, "Exercise name should not be empty")
        }
    }
    
    func testMultipleLoadsAreIdempotent() {
        // Load twice
        service.loadDefaultExercisesIfNeeded()
        let countAfterFirst = (database.fetch(Exercise.self) as! [Exercise]).count
        
        service.loadDefaultExercisesIfNeeded()
        let countAfterSecond = (database.fetch(Exercise.self) as! [Exercise]).count
        
        // Count should remain the same (version-based loading prevents duplicates)
        XCTAssertEqual(countAfterFirst, countAfterSecond, "Loading twice should not create duplicates")
    }
}

// MARK: - MuscleGroupService Tests

final class MuscleGroupServiceTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    private var service: MuscleGroupService!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
        service = MuscleGroupService()
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        service = nil
        super.tearDown()
    }
    
    func testGetMuscleGroupOccurrencesEmpty() {
        let occurrences = service.getMuscleGroupOccurances(in: [WorkoutSet]())
        XCTAssertTrue(occurrences.isEmpty, "Empty sets should return empty occurrences")
    }
    
    func testGetMuscleGroupOccurrencesSingleExercise() {
        let exercise = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        
        let set1 = database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)
        let set2 = database.newStandardSet(repetitions: 8, weight: 55000, setGroup: setGroup)
        let set3 = database.newStandardSet(repetitions: 6, weight: 60000, setGroup: setGroup)
        
        let occurrences = service.getMuscleGroupOccurances(in: [set1, set2, set3])
        
        XCTAssertEqual(occurrences.count, 1, "Should have one muscle group")
        XCTAssertEqual(occurrences.first?.0, .chest, "Should be chest")
        XCTAssertEqual(occurrences.first?.1, 3, "Should have 3 occurrences")
    }
    
    func testGetMuscleGroupOccurrencesMultipleExercises() {
        let chest = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let back = builder.createExercise(name: "Row", muscleGroup: .back)
        
        let workout = database.newWorkout(name: "Test")
        
        let chestGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: chest,
            workout: workout
        )
        let chestSet1 = database.newStandardSet(setGroup: chestGroup)
        let chestSet2 = database.newStandardSet(setGroup: chestGroup)
        
        let backGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: back,
            workout: workout
        )
        let backSet = database.newStandardSet(setGroup: backGroup)
        
        let occurrences = service.getMuscleGroupOccurances(in: [chestSet1, chestSet2, backSet])
        
        XCTAssertEqual(occurrences.count, 2, "Should have two muscle groups")
        
        // Check chest is first (more occurrences)
        XCTAssertEqual(occurrences.first?.0, .chest, "Chest should be first (more sets)")
        XCTAssertEqual(occurrences.first?.1, 2, "Chest should have 2 sets")
        
        // Check back
        let backOccurrence = occurrences.first { $0.0 == .back }
        XCTAssertNotNil(backOccurrence)
        XCTAssertEqual(backOccurrence?.1, 1, "Back should have 1 set")
    }
    
    func testGetMuscleGroupOccurrencesSuperSet() {
        let biceps = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let shoulders = builder.createExercise(name: "Lateral Raise", muscleGroup: .shoulders)
        
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: biceps,
            workout: workout
        )
        setGroup.secondaryExercise = shoulders
        
        let superSet = database.newSuperSet(setGroup: setGroup)
        
        let occurrences = service.getMuscleGroupOccurances(in: [superSet])
        
        XCTAssertEqual(occurrences.count, 2, "Super set should count both muscle groups")
        
        let hasBiceps = occurrences.contains { $0.0 == .biceps && $0.1 == 1 }
        let hasShoulders = occurrences.contains { $0.0 == .shoulders && $0.1 == 1 }
        
        XCTAssertTrue(hasBiceps, "Should count biceps from super set")
        XCTAssertTrue(hasShoulders, "Should count shoulders from super set")
    }
    
    func testGetMuscleGroupOccurrencesInWorkout() {
        let workout = builder.createCompleteWorkout(
            exerciseCount: 2,
            setsPerExercise: 3
        )
        
        let occurrences = service.getMuscleGroupOccurances(in: workout)
        
        XCTAssertFalse(occurrences.isEmpty, "Should have muscle group occurrences")
        
        // Total should equal number of sets
        let totalOccurrences = occurrences.reduce(0) { $0 + $1.1 }
        XCTAssertEqual(totalOccurrences, 6, "Total occurrences should match total sets")
    }
    
    func testMuscleGroupOccurrencesSortedByCount() {
        let chest = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let back = builder.createExercise(name: "Row", muscleGroup: .back)
        let shoulders = builder.createExercise(name: "Press", muscleGroup: .shoulders)
        
        let workout = database.newWorkout(name: "Test")
        
        // Create sets with different counts: back(3) > chest(2) > shoulders(1)
        let chestGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: chest, workout: workout)
        database.newStandardSet(setGroup: chestGroup)
        database.newStandardSet(setGroup: chestGroup)
        
        let backGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: back, workout: workout)
        database.newStandardSet(setGroup: backGroup)
        database.newStandardSet(setGroup: backGroup)
        database.newStandardSet(setGroup: backGroup)
        
        let shoulderGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: shoulders, workout: workout)
        database.newStandardSet(setGroup: shoulderGroup)
        
        let occurrences = service.getMuscleGroupOccurances(in: workout)
        
        // Verify sorted by count descending
        XCTAssertEqual(occurrences[0].0, .back, "Back should be first (3 sets)")
        XCTAssertEqual(occurrences[0].1, 3)
        XCTAssertEqual(occurrences[1].0, .chest, "Chest should be second (2 sets)")
        XCTAssertEqual(occurrences[1].1, 2)
        XCTAssertEqual(occurrences[2].0, .shoulders, "Shoulders should be third (1 set)")
        XCTAssertEqual(occurrences[2].1, 1)
    }
}

// MARK: - FuzzySearchService Tests

final class FuzzySearchServiceTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    private var searchService: FuzzySearchService!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
        searchService = FuzzySearchService.shared
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    // MARK: - String Search Tests
    
    func testSearchEmptyQuery() {
        let strings = ["Apple", "Banana", "Cherry"]
        let results = searchService.search("", in: strings)
        XCTAssertEqual(results.count, 3, "Empty query should return all items")
    }
    
    func testSearchExactMatch() {
        let strings = ["Apple", "Banana", "Cherry"]
        let results = searchService.search("Apple", in: strings)
        XCTAssertTrue(results.contains("Apple"), "Should find exact match")
    }
    
    func testSearchFuzzyMatch() {
        let strings = ["Bench Press", "Squat", "Deadlift"]
        let results = searchService.search("Benc Pres", in: strings)  // typo
        XCTAssertTrue(results.contains("Bench Press"), "Should find fuzzy match with typos")
    }
    
    func testSearchCaseInsensitive() {
        let strings = ["Bench Press", "Squat", "Deadlift"]
        let results = searchService.search("bench press", in: strings)
        XCTAssertTrue(results.contains("Bench Press"), "Should find match regardless of case")
    }
    
    func testSearchNoMatch() {
        let strings = ["Bench Press", "Squat", "Deadlift"]
        let results = searchService.search("ZZZZZZZ", in: strings)
        XCTAssertTrue(results.isEmpty, "Should return empty for no match")
    }
    
    func testSearchPartialMatch() {
        let strings = ["Bench Press", "Incline Bench Press", "Decline Bench Press"]
        let results = searchService.search("Bench", in: strings)
        XCTAssertEqual(results.count, 3, "Should find all items containing 'Bench'")
    }
    
    // MARK: - Exercise Search Tests
    
    func testSearchExercises() {
        let ex1 = builder.createExercise(name: "Barbell Bench Press", muscleGroup: .chest)
        let ex2 = builder.createExercise(name: "Dumbbell Flyes", muscleGroup: .chest)
        let ex3 = builder.createExercise(name: "Barbell Squat", muscleGroup: .legs)
        
        let exercises = [ex1, ex2, ex3]
        let results = searchService.searchExercises("Barbell", in: exercises)
        
        // Fuzzy search may return all exercises with varying relevance
        // The key behavior to verify is that exact matches are included
        XCTAssertTrue(results.contains(ex1), "Should find Barbell Bench Press")
        XCTAssertTrue(results.contains(ex3), "Should find Barbell Squat")
    }
    
    func testSearchExercisesEmptyQuery() {
        let ex1 = builder.createExercise(name: "Bench Press")
        let ex2 = builder.createExercise(name: "Squat")
        
        let exercises = [ex1, ex2]
        let results = searchService.searchExercises("", in: exercises)
        
        XCTAssertEqual(results.count, 2, "Empty query should return all exercises")
    }
    
    // MARK: - Workout Search Tests
    
    func testSearchWorkouts() {
        let w1 = database.newWorkout(name: "Push Day")
        let w2 = database.newWorkout(name: "Pull Day")
        let w3 = database.newWorkout(name: "Leg Day")
        
        let workouts = [w1, w2, w3]
        let results = searchService.searchWorkouts("Push", in: workouts)
        
        XCTAssertTrue(results.contains(w1), "Should find Push Day")
    }
    
    func testSearchWorkoutsEmptyQuery() {
        let w1 = database.newWorkout(name: "Workout 1")
        let w2 = database.newWorkout(name: "Workout 2")
        
        let workouts = [w1, w2]
        let results = searchService.searchWorkouts("", in: workouts)
        
        XCTAssertEqual(results.count, 2, "Empty query should return all workouts")
    }
}
