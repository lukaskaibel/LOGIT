//
//  WorkoutLiveActivitySnapshotBuilderTests.swift
//  LOGITTests
//
//  Created by Codex on 28.03.26.
//

import XCTest

@testable import LOGIT

final class WorkoutLiveActivitySnapshotBuilderTests: XCTestCase {
    private var defaultsHelper: UserDefaultsTestHelper!
    private let repetitionsUnit = NSLocalizedString("reps", comment: "")

    override func setUp() {
        super.setUp()
        defaultsHelper = UserDefaultsTestHelper()
        defaultsHelper.setTestValue(WeightUnit.kg.rawValue, forKey: "weightUnit")
    }

    override func tearDown() {
        defaultsHelper.restoreAll()
        defaultsHelper = nil
        super.tearDown()
    }

    func testFreshWorkoutUsesFirstSetGroupAndFirstSet() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout(name: "", setGroupCount: 0)
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let bench = builder.createExercise(name: "Bench", muscleGroup: .chest)

        let firstGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        database.newStandardSet(setGroup: firstGroup)
        database.newStandardSet(setGroup: firstGroup)

        let secondGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: bench,
            workout: workout
        )
        database.newStandardSet(setGroup: secondGroup)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.exerciseIndex, 1)
        XCTAssertEqual(snapshot.exerciseCount, 2)
        XCTAssertEqual(snapshot.setIndex, 1)
        XCTAssertEqual(snapshot.setCount, 2)
        XCTAssertEqual(snapshot.primaryExerciseName, "Squat")
        XCTAssertEqual(snapshot.workoutTitle, Workout.getStandardName(for: workout.date!))
        XCTAssertEqual(snapshot.themeToken, .legs)
    }

    func testFirstIncompleteStandardSetUsesCurrentSetWithinSetGroup() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        let firstSet = database.newStandardSet(repetitions: 8, weight: 100_000, setGroup: setGroup)
        _ = firstSet
        database.newStandardSet(setGroup: setGroup)
        database.newWorkoutSetGroup(exercise: builder.createExercise(name: "Bench"), workout: workout)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.exerciseIndex, 1)
        XCTAssertEqual(snapshot.setIndex, 2)
        XCTAssertEqual(snapshot.setCount, 2)
        XCTAssertEqual(snapshot.previousPrimaryMetrics?.repetitionSegments, ["8"])
        XCTAssertEqual(snapshot.previousPrimaryMetrics?.repetitionsUnit, repetitionsUnit)
        XCTAssertEqual(snapshot.previousPrimaryMetrics?.weightSegments, ["100"])
        XCTAssertEqual(snapshot.previousPrimaryMetrics?.repetitionSegmentPlaceholders, [false])
        XCTAssertEqual(snapshot.previousPrimaryMetrics?.weightSegmentPlaceholders, [false])
        XCTAssertNil(snapshot.previousSecondaryMetrics)
    }

    func testFirstSetHasNoPreviousSetMetrics() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        database.newStandardSet(setGroup: setGroup)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.setIndex, 1)
        XCTAssertNil(snapshot.previousPrimaryMetrics)
        XCTAssertNil(snapshot.previousSecondaryMetrics)
    }

    func testWeightWithoutRepetitionsShowsOnlyEnteredWeight() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let template = database.newTemplate(name: "Push Day")
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: builder.createExercise(name: "Bench", muscleGroup: .chest),
            template: template
        )
        database.newTemplateStandardSet(repetitions: 8, weight: 60_000, setGroup: templateGroup)
        workout.template = template

        let workoutGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: templateGroup.exercise,
            workout: workout
        )
        let workoutSet = database.newStandardSet(repetitions: 0, weight: 55_000, setGroup: workoutGroup)
        _ = workoutSet

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegments, ["8"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegmentPlaceholders, [true])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegments, ["55"])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegmentPlaceholders, [false])
    }

    func testTemplateBackedStandardSetUsesTemplateValuesWhenUntouched() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let template = database.newTemplate(name: "Push Day")
        let exercise = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 8, weight: 60_000, setGroup: templateGroup)
        workout.template = template

        let workoutGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(setGroup: workoutGroup)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegments, ["8"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionsUnit, repetitionsUnit)
        XCTAssertEqual(snapshot.primaryMetrics.weightSegments, ["60"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegmentPlaceholders, [true])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegmentPlaceholders, [true])
    }

    func testDropSetCurrentSetDetectionUsesFirstIncompleteDropSet() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let exercise = builder.createExercise(name: "Lat Pulldown", muscleGroup: .back)
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newDropSet(repetitions: [10, 8], weights: [70_000, 60_000], setGroup: setGroup)
        database.newDropSet(repetitions: [0, 0], weights: [0, 0], setGroup: setGroup)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.exerciseIndex, 1)
        XCTAssertEqual(snapshot.setIndex, 2)
        XCTAssertEqual(snapshot.setCount, 2)
    }

    func testSuperSetIncludesSecondaryExerciseAndPerExerciseMetrics() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let template = database.newTemplate(name: "Arms")
        let curls = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let pushdowns = builder.createExercise(name: "Pushdowns", muscleGroup: .triceps)
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            template: template
        )
        templateGroup.secondaryExercise = pushdowns
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 20_000,
            weightSecondExercise: 25_000,
            setGroup: templateGroup
        )
        workout.template = template

        let workoutGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            workout: workout
        )
        workoutGroup.secondaryExercise = pushdowns
        database.newSuperSet(setGroup: workoutGroup)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.primaryExerciseName, "Curls")
        XCTAssertEqual(snapshot.secondaryExerciseName, "Pushdowns")
        XCTAssertFalse(snapshot.supersetPartnerIsLeading)
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegments, ["12"])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegments, ["20"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegmentPlaceholders, [true])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegmentPlaceholders, [true])
        XCTAssertNil(snapshot.secondaryMetrics)
    }

    func testSuperSetFocusesSecondExerciseWhenFirstHasReps() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let template = database.newTemplate(name: "Arms")
        let curls = builder.createExercise(name: "Curls", muscleGroup: .biceps)
        let pushdowns = builder.createExercise(name: "Pushdowns", muscleGroup: .triceps)
        let templateGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            template: template
        )
        templateGroup.secondaryExercise = pushdowns
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 20_000,
            weightSecondExercise: 25_000,
            setGroup: templateGroup
        )
        workout.template = template

        let workoutGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: curls,
            workout: workout
        )
        workoutGroup.secondaryExercise = pushdowns
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 0,
            weightFirstExercise: 17_500,
            weightSecondExercise: 0,
            setGroup: workoutGroup
        )

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.primaryExerciseName, "Pushdowns")
        XCTAssertEqual(snapshot.secondaryExerciseName, "Curls")
        XCTAssertTrue(snapshot.supersetPartnerIsLeading)
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegments, ["15"])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegments, ["25"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegmentPlaceholders, [true])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegmentPlaceholders, [true])
        XCTAssertNil(snapshot.secondaryMetrics)
        XCTAssertEqual(snapshot.themeToken, .triceps)
    }

    func testAllCompletedWorkoutFallsBackToLastSetGroup() throws {
        let (_, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let first = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let second = builder.createExercise(name: "Row", muscleGroup: .back)
        builder.createStandardSet(
            repetitions: 8,
            weight: 80_000,
            exercise: first,
            workout: workout
        )
        builder.createStandardSet(
            repetitions: 10,
            weight: 60_000,
            exercise: second,
            workout: workout
        )

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.exerciseIndex, 2)
        XCTAssertEqual(snapshot.primaryExerciseName, "Row")
        XCTAssertEqual(snapshot.setIndex, 1)
    }

    func testIndicesTrackReorderAndDeleteOperations() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let bench = builder.createExercise(name: "Bench", muscleGroup: .chest)

        let squatGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        database.newStandardSet(repetitions: 8, weight: 100_000, setGroup: squatGroup)
        let incompleteSquatSet = database.newStandardSet(setGroup: squatGroup)
        _ = incompleteSquatSet
        database.newStandardSet(setGroup: squatGroup)

        let benchGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: bench,
            workout: workout
        )
        database.newStandardSet(setGroup: benchGroup)

        workout.setGroups.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        database.delete(squatGroup.sets.first)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.exerciseIndex, 1)
        XCTAssertEqual(snapshot.primaryExerciseName, "Bench")
        XCTAssertEqual(snapshot.setIndex, 1)
        XCTAssertEqual(snapshot.setCount, 1)
    }

    func testTemplateValuesAreResolvedByCurrentIndicesAfterReorder() throws {
        let (database, builder) = createTestBuilder()
        let workout = builder.createWorkout()
        let template = database.newTemplate(name: "Mixed")
        let squat = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let bench = builder.createExercise(name: "Bench", muscleGroup: .chest)

        let templateSquatGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 5, weight: 120_000, setGroup: templateSquatGroup)

        let templateBenchGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: bench,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 10, weight: 70_000, setGroup: templateBenchGroup)
        workout.template = template

        let workoutSquatGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: squat,
            workout: workout
        )
        database.newStandardSet(setGroup: workoutSquatGroup)

        let workoutBenchGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: bench,
            workout: workout
        )
        database.newStandardSet(setGroup: workoutBenchGroup)

        workout.setGroups.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let snapshot = try XCTUnwrap(WorkoutLiveActivitySnapshotBuilder.build(for: workout))

        XCTAssertEqual(snapshot.primaryExerciseName, "Bench")
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegments, ["5"])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegments, ["120"])
        XCTAssertEqual(snapshot.primaryMetrics.repetitionSegmentPlaceholders, [true])
        XCTAssertEqual(snapshot.primaryMetrics.weightSegmentPlaceholders, [true])
    }
}
