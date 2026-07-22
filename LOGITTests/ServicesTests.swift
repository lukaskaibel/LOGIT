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

// MARK: - WorkoutRecorder Tests

final class WorkoutRecorderTests: XCTestCase {

    private var database: Database!
    private var workoutRecorder: WorkoutRecorder!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        workoutRecorder = WorkoutRecorder(database: database)
    }

    override func tearDown() {
        workoutRecorder = nil
        database = nil
        super.tearDown()
    }

    func testAutoRestBehaviorUsesConfiguredRestForTimerMode() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        database.newStandardSet(restDuration: 30, setGroup: setGroup)
        let lastSet = database.newStandardSet(restDuration: 90, setGroup: setGroup)

        let restBehavior = workoutRecorder.autoRestBehavior(
            forSet: lastSet,
            usesStopwatch: false,
            autoTimerEnabled: false,
            autoStopwatchEnabled: false,
            timerDuration: 45
        )

        XCTAssertEqual(restBehavior, .timer(90))
    }

    func testAutoRestBehaviorUsesAutoTimerWhenNoConfiguredRestExists() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        database.newStandardSet(restDuration: 30, setGroup: setGroup)
        let lastSet = database.newStandardSet(restDuration: 0, setGroup: setGroup)

        let restBehavior = workoutRecorder.autoRestBehavior(
            forSet: lastSet,
            usesStopwatch: false,
            autoTimerEnabled: true,
            autoStopwatchEnabled: false,
            timerDuration: 45
        )

        XCTAssertEqual(restBehavior, .timer(45))
    }

    func testAutoRestBehaviorUsesStopwatchWhenEnabledInStopwatchMode() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let lastSet = database.newStandardSet(restDuration: 90, setGroup: setGroup)

        let restBehavior = workoutRecorder.autoRestBehavior(
            forSet: lastSet,
            usesStopwatch: true,
            autoTimerEnabled: false,
            autoStopwatchEnabled: true,
            timerDuration: 45
        )

        XCTAssertEqual(restBehavior, .stopwatch)
    }

    func testAutoRestBehaviorDoesNotUseStopwatchWhenDisabledInStopwatchMode() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let lastSet = database.newStandardSet(restDuration: 90, setGroup: setGroup)

        let restBehavior = workoutRecorder.autoRestBehavior(
            forSet: lastSet,
            usesStopwatch: true,
            autoTimerEnabled: false,
            autoStopwatchEnabled: false,
            timerDuration: 45
        )

        XCTAssertNil(restBehavior)
    }

    func testAutoRestTriggerSetIgnoresWeightOnlyStandardSetEdit() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newStandardSet(setGroup: setGroup)
        let previousIDs = workoutRecorder.repetitionEnteredSetIDs(in: workout)

        workoutSet.weight = 60_000

        let trigger = workoutRecorder.autoRestTriggerSet(
            in: workout,
            previousRepetitionEntrySetIDs: previousIDs,
            preferredSet: workoutSet
        )

        XCTAssertNil(trigger.triggerSet)
        XCTAssertTrue(trigger.repetitionEntrySetIDs.isEmpty)
    }

    func testAutoRestTriggerSetIgnoresWeightOnlyDropSetEdit() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newDropSet(repetitions: [0, 0], weights: [0, 0], setGroup: setGroup)
        let previousIDs = workoutRecorder.repetitionEnteredSetIDs(in: workout)

        workoutSet.weights = [50_000, 40_000]

        let trigger = workoutRecorder.autoRestTriggerSet(
            in: workout,
            previousRepetitionEntrySetIDs: previousIDs,
            preferredSet: workoutSet
        )

        XCTAssertNil(trigger.triggerSet)
        XCTAssertTrue(trigger.repetitionEntrySetIDs.isEmpty)
    }

    func testAutoRestTriggerSetIgnoresWeightOnlySuperSetEdit() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newSuperSet(setGroup: setGroup)
        let previousIDs = workoutRecorder.repetitionEnteredSetIDs(in: workout)

        workoutSet.weightFirstExercise = 40_000
        workoutSet.weightSecondExercise = 30_000

        let trigger = workoutRecorder.autoRestTriggerSet(
            in: workout,
            previousRepetitionEntrySetIDs: previousIDs,
            preferredSet: workoutSet
        )

        XCTAssertNil(trigger.triggerSet)
        XCTAssertTrue(trigger.repetitionEntrySetIDs.isEmpty)
    }

    func testAutoRestTriggerSetReturnsLastSetInGroupWhenRepetitionsAreEntered() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        _ = database.newStandardSet(repetitions: 10, setGroup: setGroup)
        let lastSet = database.newStandardSet(setGroup: setGroup)
        let previousIDs = workoutRecorder.repetitionEnteredSetIDs(in: workout)

        lastSet.entries.first?.repetitions = 8

        let trigger = workoutRecorder.autoRestTriggerSet(
            in: workout,
            previousRepetitionEntrySetIDs: previousIDs,
            preferredSet: lastSet
        )

        XCTAssertEqual(trigger.triggerSet, lastSet)
        XCTAssertEqual(trigger.repetitionEntrySetIDs, Set([setGroup.sets.first!.objectID, lastSet.objectID]))
    }

    func testEndStopwatchPersistsElapsedForActiveRestSet() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newStandardSet(setGroup: setGroup)
        let chronograph = Chronograph()

        workoutRecorder.activeRestTimerSet = workoutSet
        chronograph.mode = .stopwatch
        chronograph.setSeconds(18)
        chronograph.status = .running

        workoutRecorder.endStopwatch(using: chronograph)

        XCTAssertEqual(workoutSet.restDurationSeconds, 18)
        XCTAssertNil(workoutRecorder.activeRestTimerSet)
        XCTAssertEqual(chronograph.status, .idle)
        XCTAssertEqual(chronograph.seconds, 0, accuracy: 0.001)
    }

    func testFinishRestAndStopChronographPersistsElapsedForActiveTimerSetWithoutConfiguredRest() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newStandardSet(restDuration: 0, setGroup: setGroup)
        let chronograph = Chronograph()

        workoutRecorder.activeRestTimerSet = workoutSet
        chronograph.mode = .timer
        chronograph.setSeconds(45.99)
        chronograph.seconds = 30.99
        chronograph.status = .running

        workoutRecorder.finishRestAndStopChronograph(
            using: chronograph,
            persistTrackedValue: true
        )

        XCTAssertEqual(workoutSet.restDurationSeconds, 15)
        XCTAssertNil(workoutRecorder.activeRestTimerSet)
        XCTAssertEqual(chronograph.status, .idle)
        XCTAssertEqual(chronograph.seconds, 0, accuracy: 0.001)
    }

    func testFinishRestAndStopChronographDoesNotOverrideConfiguredTimerRest() {
        let workout = database.newWorkout(name: "Test")
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workout
        )
        let workoutSet = database.newStandardSet(restDuration: 90, setGroup: setGroup)
        let chronograph = Chronograph()

        workoutRecorder.activeRestTimerSet = workoutSet
        chronograph.mode = .timer
        chronograph.setSeconds(45.99)
        chronograph.seconds = 10.99
        chronograph.status = .running

        workoutRecorder.finishRestAndStopChronograph(
            using: chronograph,
            persistTrackedValue: true
        )

        XCTAssertEqual(workoutSet.restDurationSeconds, 90)
        XCTAssertNil(workoutRecorder.activeRestTimerSet)
        XCTAssertEqual(chronograph.status, .idle)
    }

    func testFinishRestAndStopChronographStopsManualChronographWithoutActiveRestSet() {
        let chronograph = Chronograph()

        chronograph.mode = .stopwatch
        chronograph.setSeconds(18)
        chronograph.status = .running

        workoutRecorder.finishRestAndStopChronograph(
            using: chronograph,
            persistTrackedValue: true
        )

        XCTAssertNil(workoutRecorder.activeRestTimerSet)
        XCTAssertEqual(chronograph.status, .idle)
        XCTAssertEqual(chronograph.seconds, 0, accuracy: 0.001)
    }

    func testStartWorkoutFromTemplateCopiesRestDurationsForAllTemplateSetTypes() {
        let template = database.newTemplate(name: "Template")

        let standardGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            template: template
        )
        _ = database.newTemplateStandardSet(
            repetitions: 10,
            weight: 60000,
            restDuration: 90,
            setGroup: standardGroup
        )

        let dropGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            template: template
        )
        _ = database.newTemplateDropSet(
            repetitions: [10, 8],
            weights: [60000, 50000],
            restDuration: 75,
            templateSetGroup: dropGroup
        )

        let superGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            template: template
        )
        _ = database.newTemplateSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 60000,
            weightSecondExercise: 40000,
            restDuration: 60,
            setGroup: superGroup
        )

        workoutRecorder.startWorkout(from: template)

        guard let workout = workoutRecorder.workout else {
            XCTFail("Expected workout to be created from template")
            return
        }

        XCTAssertEqual(workout.setGroups.count, 3)
        XCTAssertEqual(workout.setGroups[0].sets[0].restDurationSeconds, 90)
        XCTAssertEqual(workout.setGroups[1].sets[0].restDurationSeconds, 75)
        XCTAssertEqual(workout.setGroups[2].sets[0].restDurationSeconds, 60)
    }

    func testAutoRestBehaviorUsesTemplateRestDurationForTemplateBackedWorkoutSet() {
        let template = database.newTemplate(name: "Template")
        let setGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            template: template
        )
        _ = database.newTemplateStandardSet(
            repetitions: 10,
            weight: 60000,
            restDuration: 120,
            setGroup: setGroup
        )

        workoutRecorder.startWorkout(from: template)

        guard let workoutSet = workoutRecorder.workout?.setGroups.first?.sets.first else {
            XCTFail("Expected template-backed workout set")
            return
        }

        let restBehavior = workoutRecorder.autoRestBehavior(
            forSet: workoutSet,
            usesStopwatch: false,
            autoTimerEnabled: true,
            autoStopwatchEnabled: false,
            timerDuration: 45
        )

        XCTAssertEqual(restBehavior, .timer(120))
    }

    // MARK: - Save / Discard Workout

    /// saveWorkout and discardWorkout run their cleanup asynchronously on the context's
    /// queue, and those blocks enqueue follow-up blocks of their own. Each round waits for
    /// one sentinel block, so `depth` rounds drain `depth` levels of nested enqueues.
    private func drainContextQueue(depth: Int = 5) {
        for _ in 0..<depth {
            let drained = expectation(description: "context queue drained")
            database.context.perform { drained.fulfill() }
            wait(for: [drained], timeout: 2)
        }
    }

    private func fetchWorkout(with id: UUID) -> Workout? {
        (database.fetch(
            Workout.self,
            predicate: NSPredicate(format: "id == %@", id as CVarArg)
        ) as? [Workout])?.first
    }

    func testSaveWorkoutPersistsWorkoutAndDeletesSetsWithoutEntries() {
        workoutRecorder.startWorkout()
        guard let workoutID = workoutRecorder.workout?.id else {
            XCTFail("Expected started workout with id")
            return
        }
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: database.newExercise(name: "Bench Press", muscleGroup: .chest),
            workout: workoutRecorder.workout
        )
        database.newStandardSet(repetitions: 12, weight: 60000, setGroup: setGroup)
        database.newStandardSet(setGroup: setGroup)

        workoutRecorder.saveWorkout()

        XCTAssertNil(workoutRecorder.workout)

        drainContextQueue()

        guard let workout = fetchWorkout(with: workoutID) else {
            XCTFail("Expected workout to be persisted")
            return
        }
        XCTAssertFalse(workout.isCurrentWorkout)
        XCTAssertFalse(workout.name?.isEmpty ?? true)
        XCTAssertNotNil(workout.endDate)
        XCTAssertEqual(workout.sets.count, 1)
        XCTAssertTrue(workout.sets.allSatisfy { $0.hasEntry })
    }

    func testSaveWorkoutDeletesWorkoutWhenNoSetHasEntries() {
        workoutRecorder.startWorkout()
        guard let workoutID = workoutRecorder.workout?.id else {
            XCTFail("Expected started workout with id")
            return
        }
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workoutRecorder.workout
        )
        database.newStandardSet(setGroup: setGroup)

        workoutRecorder.saveWorkout()
        drainContextQueue()

        XCTAssertNil(workoutRecorder.workout)
        XCTAssertNil(fetchWorkout(with: workoutID))
    }

    func testSaveWorkoutConvertsSuperSetsWithoutSecondaryExerciseToStandardSets() {
        workoutRecorder.startWorkout()
        guard let workoutID = workoutRecorder.workout?.id else {
            XCTFail("Expected started workout with id")
            return
        }
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workoutRecorder.workout
        )
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            weightFirstExercise: 50000,
            setGroup: setGroup
        )

        workoutRecorder.saveWorkout()
        drainContextQueue()

        guard let workout = fetchWorkout(with: workoutID) else {
            XCTFail("Expected workout to be persisted")
            return
        }
        XCTAssertEqual(workout.sets.count, 1)
        guard let standardSet = workout.sets.first as? StandardSet else {
            XCTFail("Expected super set to be converted to a standard set")
            return
        }
        XCTAssertEqual(standardSet.entryValues.map { $0.repetitions }, [10])
        XCTAssertEqual(standardSet.entryValues.map { $0.weight }, [50000])
    }

    func testDiscardWorkoutDeletesWorkout() {
        workoutRecorder.startWorkout()
        guard let workoutID = workoutRecorder.workout?.id else {
            XCTFail("Expected started workout with id")
            return
        }
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            workout: workoutRecorder.workout
        )
        database.newStandardSet(repetitions: 10, weight: 50000, setGroup: setGroup)

        workoutRecorder.discardWorkout()

        XCTAssertNil(workoutRecorder.workout)

        drainContextQueue()

        XCTAssertNil(fetchWorkout(with: workoutID))
    }

}

final class ChronographTests: XCTestCase {
    private let modeStorageKey = "selectedChronographMode"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: modeStorageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: modeStorageKey)
        super.tearDown()
    }

    func testSetSecondsPreservingElapsedKeepsElapsedProgress() {
        let chronograph = Chronograph()
        chronograph.mode = .timer
        chronograph.setSeconds(30.99)
        chronograph.seconds = 10.99

        chronograph.setSeconds(25.99, preservingElapsed: true)

        XCTAssertEqual(Int(chronograph.initialTimerSeconds.rounded(.down)), 45)
        XCTAssertEqual(chronograph.initialTimerSeconds - chronograph.seconds, 20, accuracy: 0.02)
    }

    func testSetSecondsWithTimerTotalOverrideUpdatesRemainingAndTotalIndependently() {
        let chronograph = Chronograph()
        chronograph.mode = .timer
        chronograph.status = .paused

        chronograph.setSeconds(21.99)
        chronograph.setSeconds(30.99, timerTotalSecondsOverride: 39.99)

        XCTAssertEqual(Int(chronograph.seconds.rounded(.down)), 30)
        XCTAssertEqual(Int(chronograph.initialTimerSeconds.rounded(.down)), 39)
    }

    func testInitializesWithPersistedMode() {
        UserDefaults.standard.set(Chronograph.Mode.stopwatch.rawValue, forKey: modeStorageKey)

        let chronograph = Chronograph()

        XCTAssertEqual(chronograph.mode, .stopwatch)
    }

    func testPersistingModeSelectionUpdatesDefaults() {
        let chronograph = Chronograph()

        chronograph.mode = .stopwatch

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: modeStorageKey),
            Chronograph.Mode.stopwatch.rawValue
        )
    }

    func testStopwatchNotificationScheduleStartsAtFirstThirtySeconds() {
        let schedule = Chronograph.stopwatchMinuteNotificationSchedule(
            elapsedSeconds: 0,
            maxNotificationCount: 3
        )

        XCTAssertEqual(
            schedule,
            [
                .init(minuteMark: 1, timeInterval: 60),
                .init(minuteMark: 2, timeInterval: 120),
                .init(minuteMark: 3, timeInterval: 180),
            ]
        )
    }

    func testStopwatchNotificationScheduleResumesAtNextMinuteBoundary() {
        let schedule = Chronograph.stopwatchMinuteNotificationSchedule(
            elapsedSeconds: 75.4,
            maxNotificationCount: 2
        )

        XCTAssertEqual(schedule[0].minuteMark, 2)
        XCTAssertEqual(schedule[0].timeInterval, 44.6, accuracy: 0.001)
        XCTAssertEqual(schedule[1].minuteMark, 3)
        XCTAssertEqual(schedule[1].timeInterval, 104.6, accuracy: 0.001)
    }

    func testStopwatchNotificationScheduleWaitsOneMinuteOnBoundary() {
        let schedule = Chronograph.stopwatchMinuteNotificationSchedule(
            elapsedSeconds: 120,
            maxNotificationCount: 1
        )

        XCTAssertEqual(schedule, [.init(minuteMark: 3, timeInterval: 60)])
    }
}

// MARK: - DefaultTemplateService Tests

final class DefaultTemplateServiceTests: XCTestCase {

    private var database: Database!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var exerciseService: DefaultExerciseService!
    private var templateService: DefaultTemplateService!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        // Fresh suite per test so version gates and tombstones from earlier runs can't leak in
        defaultsSuiteName = "DefaultTemplateServiceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        exerciseService = DefaultExerciseService(database: database, defaults: defaults)
        templateService = DefaultTemplateService(database: database, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        database = nil
        defaults = nil
        exerciseService = nil
        templateService = nil
        super.tearDown()
    }

    private var defaultTemplates: [Template] {
        (database.fetch(Template.self) as! [Template]).filter { $0.isDefaultTemplate }
    }

    func testSeedsDefaultTemplatesWithSetGroupsAndLocalizedNames() {
        exerciseService.loadDefaultExercisesIfNeeded()
        templateService.loadDefaultTemplatesIfNeeded()

        let templates = defaultTemplates
        XCTAssertEqual(templates.count, 5, "All 5 bundled templates should be seeded")

        for template in templates {
            XCTAssertNotNil(template.id, "Seeded templates need a deterministic id")
            XCTAssertFalse(template.setGroups.isEmpty, "Seeded templates need set groups")
            for setGroup in template.setGroups {
                let exercise = try? XCTUnwrap(setGroup.exercise)
                XCTAssertEqual(exercise?.isDefaultExercise, true, "Templates must reference default exercises")
                XCTAssertFalse(setGroup.sets.isEmpty, "Each set group needs sets")
            }
            XCTAssertFalse(
                template.displayName.hasPrefix("_default."),
                "Name key \(template.name ?? "") must resolve to a localized name"
            )
            let description = try? XCTUnwrap(template.displayDescription)
            XCTAssertEqual(
                description?.hasPrefix("_default."), false,
                "Description key \(template.descriptionText ?? "") must resolve to localized text"
            )
        }
    }

    func testSeedingTwiceCreatesNoDuplicates() {
        exerciseService.loadDefaultExercisesIfNeeded()
        templateService.loadDefaultTemplatesIfNeeded()
        let countAfterFirst = defaultTemplates.count

        templateService.loadDefaultTemplatesIfNeeded()

        XCTAssertEqual(defaultTemplates.count, countAfterFirst)
    }

    func testDeletedDefaultTemplateStaysDeleted() {
        exerciseService.loadDefaultExercisesIfNeeded()
        templateService.loadDefaultTemplatesIfNeeded()

        let victim = defaultTemplates.first!
        database.context.performAndWait {
            self.database.context.delete(victim)
        }

        // Simulate a future version bump re-running the seeding pass
        defaults.set(0, forKey: "lastLoadedDefaultTemplatesVersion")
        templateService.loadDefaultTemplatesIfNeeded()

        XCTAssertEqual(defaultTemplates.count, 4, "A deleted default template must not be resurrected")
    }

    func testEditedDefaultTemplateIsNotOverwritten() {
        exerciseService.loadDefaultExercisesIfNeeded()
        templateService.loadDefaultTemplatesIfNeeded()

        let template = defaultTemplates.first!
        template.name = "My Custom Name"

        defaults.set(0, forKey: "lastLoadedDefaultTemplatesVersion")
        templateService.loadDefaultTemplatesIfNeeded()

        XCTAssertEqual(template.name, "My Custom Name")
        XCTAssertEqual(
            (database.fetch(Template.self) as! [Template]).filter { $0.name == "My Custom Name" }.count,
            1,
            "The renamed template must not be re-seeded as a duplicate"
        )
    }

    func testSeedingWaitsForDefaultExercises() {
        // Exercises intentionally not loaded: nothing to attach templates to
        templateService.loadDefaultTemplatesIfNeeded()
        XCTAssertTrue(defaultTemplates.isEmpty, "Without default exercises no template should be seeded")

        // Next launch, exercises are there — seeding must retry because the version was not advanced
        exerciseService.loadDefaultExercisesIfNeeded()
        templateService.loadDefaultTemplatesIfNeeded()
        XCTAssertEqual(defaultTemplates.count, 5)
    }

    func testBackfillAssignsIdsToPreexistingTemplates() {
        // Templates created before model version 7 have no id
        let legacyTemplate = Template(context: database.context)
        legacyTemplate.name = "Legacy"
        XCTAssertNil(legacyTemplate.id)

        templateService.loadDefaultTemplatesIfNeeded()

        XCTAssertNotNil(legacyTemplate.id, "Backfill should assign ids to legacy templates")
    }

    func testResolvedNameAndDisplayDescription() {
        let template = database.newTemplate(name: "_default.template.pushDay")
        template.descriptionText = "_default.template.pushDay.description"

        XCTAssertTrue(template.isDefaultTemplate)
        XCTAssertEqual(template.resolvedName, NSLocalizedString("_default.template.pushDay", comment: ""))
        XCTAssertFalse(template.displayName.hasPrefix("_default."))
        XCTAssertEqual(template.displayDescription, NSLocalizedString("_default.template.pushDay.description", comment: ""))

        let custom = database.newTemplate(name: "Mein Plan")
        XCTAssertEqual(custom.resolvedName, "Mein Plan")
        XCTAssertFalse(custom.isDefaultTemplate)
        XCTAssertNil(custom.displayDescription)
    }
}

// MARK: - HealthKitSyncManagerTests

final class HealthKitSyncManagerTests: XCTestCase {

    private var database: Database!

    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
    }

    override func tearDown() {
        database = nil
        super.tearDown()
    }

    func testIsExportableRequiresBothDates() {
        XCTAssertFalse(HealthKitSyncManager.isExportable(start: nil, end: nil))
        XCTAssertFalse(HealthKitSyncManager.isExportable(start: .now, end: nil))
        XCTAssertFalse(HealthKitSyncManager.isExportable(start: nil, end: .now))
    }

    func testIsExportableRequiresPositiveDuration() {
        let now = Date()
        XCTAssertFalse(HealthKitSyncManager.isExportable(start: now, end: now, now: now))
        XCTAssertFalse(
            HealthKitSyncManager.isExportable(start: now, end: now.addingTimeInterval(-60), now: now)
        )
        XCTAssertTrue(
            HealthKitSyncManager.isExportable(
                start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-60), now: now
            )
        )
    }

    func testIsExportableRejectsFutureEndDates() {
        // The date editor allows picking an end date in the future; HealthKit rejects such samples.
        let now = Date()
        XCTAssertFalse(
            HealthKitSyncManager.isExportable(
                start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(600), now: now
            )
        )
    }

    func testHealthKitPayloadCapturesWorkoutFields() {
        let workout = database.newWorkout()
        workout.id = UUID()
        workout.name = "Push Day"
        workout.date = Date(timeIntervalSinceNow: -7200)
        workout.endDate = Date(timeIntervalSinceNow: -3600)

        let payload = workout.healthKitPayload
        XCTAssertEqual(payload?.id, workout.id)
        XCTAssertEqual(payload?.name, "Push Day")
        XCTAssertEqual(payload?.start, workout.date)
        XCTAssertEqual(payload?.end, workout.endDate)
    }

    func testHealthKitPayloadIsNilWithoutLoggedDuration() {
        let workout = database.newWorkout()
        workout.id = UUID()
        workout.date = Date(timeIntervalSinceNow: -3600)
        workout.endDate = nil

        XCTAssertNil(workout.healthKitPayload)
    }
}
