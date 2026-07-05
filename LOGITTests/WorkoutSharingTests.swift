//
//  WorkoutSharingTests.swift
//  LOGITTests
//
//  Comprehensive tests for workout/template sharing functionality
//

import XCTest
import CoreData

@testable import LOGIT

// MARK: - WorkoutDTO Tests

final class WorkoutDTOTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    // MARK: - WorkoutDTO from Workout
    
    func testWorkoutDTOFromSimpleWorkout() {
        let workout = builder.createCompleteWorkout(
            name: "Push Day",
            exerciseCount: 2,
            setsPerExercise: 3
        )
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.name, "Push Day")
        XCTAssertNotNil(dto.date)
        XCTAssertEqual(dto.formatVersion, WorkoutDTO.formatVersion)
        XCTAssertEqual(dto.setGroups.count, 2)
        XCTAssertFalse(dto.appStoreURL.isEmpty)
        
        // Each set group should have 3 standard sets
        for setGroup in dto.setGroups {
            XCTAssertEqual(setGroup.sets.count, 3)
            for set in setGroup.sets {
                XCTAssertEqual(set.type, .standard)
                XCTAssertNotNil(set.repetitions)
                XCTAssertNotNil(set.weight)
            }
        }
    }
    
    func testWorkoutDTOFromWorkoutWithSuperSets() {
        let workout = database.newWorkout(name: "Superset Workout", date: Date())
        let exerciseA = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let exerciseB = builder.createExercise(name: "Bent Over Row", muscleGroup: .back)
        
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exerciseA,
            workout: workout
        )
        setGroup.secondaryExercise = exerciseB
        
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 80000,
            weightSecondExercise: 60000,
            setGroup: setGroup
        )
        database.newSuperSet(
            repetitionsFirstExercise: 8,
            repetitionsSecondExercise: 10,
            weightFirstExercise: 85000,
            weightSecondExercise: 65000,
            setGroup: setGroup
        )
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.setGroups.count, 1)
        let sgDTO = dto.setGroups[0]
        XCTAssertNotNil(sgDTO.secondaryExercise)
        XCTAssertEqual(sgDTO.exercise.name, "Bench Press")
        XCTAssertEqual(sgDTO.secondaryExercise?.name, "Bent Over Row")
        XCTAssertEqual(sgDTO.sets.count, 2)
        
        // First super set
        let firstSet = sgDTO.sets[0]
        XCTAssertEqual(firstSet.type, .superSet)
        XCTAssertEqual(firstSet.repetitionsFirstExercise, 10)
        XCTAssertEqual(firstSet.repetitionsSecondExercise, 12)
        XCTAssertEqual(firstSet.weightFirstExercise, 80000)
        XCTAssertEqual(firstSet.weightSecondExercise, 60000)
        XCTAssertNil(firstSet.repetitions)
        XCTAssertNil(firstSet.weight)
        XCTAssertNil(firstSet.dropSetRepetitions)
        XCTAssertNil(firstSet.dropSetWeights)
        
        // Second super set
        let secondSet = sgDTO.sets[1]
        XCTAssertEqual(secondSet.type, .superSet)
        XCTAssertEqual(secondSet.repetitionsFirstExercise, 8)
        XCTAssertEqual(secondSet.repetitionsSecondExercise, 10)
    }
    
    func testWorkoutDTOFromWorkoutWithDropSets() {
        let workout = database.newWorkout(name: "Drop Set Workout", date: Date())
        let exercise = builder.createExercise(name: "Bicep Curl", muscleGroup: .biceps)
        
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        
        database.newDropSet(
            repetitions: [10, 8, 6],
            weights: [20000, 15000, 10000],
            setGroup: setGroup
        )
        database.newDropSet(
            repetitions: [12, 10],
            weights: [18000, 12000],
            setGroup: setGroup
        )
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.setGroups.count, 1)
        XCTAssertEqual(dto.setGroups[0].sets.count, 2)
        
        let firstDrop = dto.setGroups[0].sets[0]
        XCTAssertEqual(firstDrop.type, .dropSet)
        XCTAssertEqual(firstDrop.dropSetRepetitions, [10, 8, 6])
        XCTAssertEqual(firstDrop.dropSetWeights, [20000, 15000, 10000])
        XCTAssertNil(firstDrop.repetitions)
        XCTAssertNil(firstDrop.weight)
        XCTAssertNil(firstDrop.repetitionsFirstExercise)
        
        let secondDrop = dto.setGroups[0].sets[1]
        XCTAssertEqual(secondDrop.type, .dropSet)
        XCTAssertEqual(secondDrop.dropSetRepetitions, [12, 10])
        XCTAssertEqual(secondDrop.dropSetWeights, [18000, 12000])
    }
    
    func testWorkoutDTOFromWorkoutWithMixedSetTypes() {
        let workout = database.newWorkout(name: "Mixed Workout", date: Date())
        
        // Set group 1: Standard sets
        let exerciseA = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let sgStandard = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exerciseA,
            workout: workout
        )
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sgStandard)
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sgStandard)
        
        // Set group 2: Super sets
        let exerciseB = builder.createExercise(name: "Lat Pulldown", muscleGroup: .back)
        let exerciseC = builder.createExercise(name: "Face Pull", muscleGroup: .shoulders)
        let sgSuper = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exerciseB,
            workout: workout
        )
        sgSuper.secondaryExercise = exerciseC
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 50000,
            weightSecondExercise: 20000,
            setGroup: sgSuper
        )
        
        // Set group 3: Drop sets
        let exerciseD = builder.createExercise(name: "Leg Extension", muscleGroup: .legs)
        let sgDrop = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exerciseD,
            workout: workout
        )
        database.newDropSet(
            repetitions: [15, 12, 10, 8],
            weights: [40000, 30000, 25000, 20000],
            setGroup: sgDrop
        )
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.setGroups.count, 3)
        XCTAssertEqual(dto.setGroups[0].sets[0].type, .standard)
        XCTAssertEqual(dto.setGroups[1].sets[0].type, .superSet)
        XCTAssertEqual(dto.setGroups[2].sets[0].type, .dropSet)
    }
    
    func testWorkoutDTOFromEmptyWorkout() {
        let workout = database.newWorkout(name: "Empty", date: Date())
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.name, "Empty")
        XCTAssertEqual(dto.setGroups.count, 0)
        XCTAssertEqual(dto.formatVersion, 1)
    }
    
    func testWorkoutDTOPreservesEndDate() {
        let start = Date()
        let end = Date().addingTimeInterval(3600) // 1 hour later
        let workout = database.newWorkout(name: "Timed", date: start)
        workout.endDate = end
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.date, start)
        XCTAssertEqual(dto.endDate, end)
    }
    
    func testWorkoutDTOPreservesRestDurationsForAllSetTypes() {
        let workout = database.newWorkout(name: "Rest Duration DTO", date: Date())
        
        let standardExercise = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let standardGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: standardExercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 8, weight: 80000, restDuration: 90, setGroup: standardGroup)
        
        let superPrimary = builder.createExercise(name: "Row", muscleGroup: .back)
        let superSecondary = builder.createExercise(name: "Face Pull", muscleGroup: .shoulders)
        let superGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: superPrimary,
            workout: workout
        )
        superGroup.secondaryExercise = superSecondary
        database.newSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 50000,
            weightSecondExercise: 15000,
            restDuration: 75,
            setGroup: superGroup
        )
        
        let dropExercise = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let dropGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: dropExercise,
            workout: workout
        )
        database.newDropSet(
            repetitions: [12, 10, 8],
            weights: [20000, 15000, 10000],
            restDuration: 60,
            setGroup: dropGroup
        )
        
        let dto = WorkoutDTO(from: workout)
        
        XCTAssertEqual(dto.setGroups[0].sets[0].restDuration, 90)
        XCTAssertEqual(dto.setGroups[1].sets[0].restDuration, 75)
        XCTAssertEqual(dto.setGroups[2].sets[0].restDuration, 60)
    }
    
    // MARK: - JSON Encoding/Decoding Round-Trip
    
    func testWorkoutDTORoundTripStandardSets() throws {
        let workout = builder.createCompleteWorkout(
            name: "Round Trip Test",
            exerciseCount: 2,
            setsPerExercise: 3
        )
        
        let dto = WorkoutDTO(from: workout)
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.name, dto.name)
        XCTAssertEqual(decoded.formatVersion, dto.formatVersion)
        XCTAssertEqual(decoded.setGroups.count, dto.setGroups.count)
        XCTAssertEqual(decoded.appStoreURL, dto.appStoreURL)
        
        for (origGroup, decodedGroup) in zip(dto.setGroups, decoded.setGroups) {
            XCTAssertEqual(origGroup.sets.count, decodedGroup.sets.count)
            XCTAssertEqual(origGroup.exercise.name, decodedGroup.exercise.name)
            XCTAssertEqual(origGroup.exercise.type, decodedGroup.exercise.type)
        }
    }
    
    func testWorkoutDTORoundTripSuperSets() throws {
        let workout = database.newWorkout(name: "Superset RT", date: Date())
        let exA = builder.createExercise(name: "Press", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Row", muscleGroup: .back)
        let sg = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exA,
            workout: workout
        )
        sg.secondaryExercise = exB
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 80000,
            weightSecondExercise: 60000,
            setGroup: sg
        )
        
        let dto = WorkoutDTO(from: workout)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        let decodedSet = decoded.setGroups[0].sets[0]
        XCTAssertEqual(decodedSet.type, .superSet)
        XCTAssertEqual(decodedSet.repetitionsFirstExercise, 10)
        XCTAssertEqual(decodedSet.repetitionsSecondExercise, 12)
        XCTAssertEqual(decodedSet.weightFirstExercise, 80000)
        XCTAssertEqual(decodedSet.weightSecondExercise, 60000)
        XCTAssertNotNil(decoded.setGroups[0].secondaryExercise)
        XCTAssertEqual(decoded.setGroups[0].secondaryExercise?.name, "Row")
    }
    
    func testWorkoutDTORoundTripDropSets() throws {
        let workout = database.newWorkout(name: "Drop RT", date: Date())
        let ex = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let sg = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: ex,
            workout: workout
        )
        database.newDropSet(
            repetitions: [10, 8, 6, 4],
            weights: [25000, 20000, 15000, 10000],
            setGroup: sg
        )
        
        let dto = WorkoutDTO(from: workout)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        let decodedSet = decoded.setGroups[0].sets[0]
        XCTAssertEqual(decodedSet.type, .dropSet)
        XCTAssertEqual(decodedSet.dropSetRepetitions, [10, 8, 6, 4])
        XCTAssertEqual(decodedSet.dropSetWeights, [25000, 20000, 15000, 10000])
    }
    
    func testWorkoutDTORoundTripMixedSets() throws {
        let workout = database.newWorkout(name: "Mixed RT", date: Date())
        
        // Standard set group
        let ex1 = builder.createExercise(name: "Deadlift", muscleGroup: .back)
        let sg1 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex1, workout: workout)
        database.newStandardSet(repetitions: 5, weight: 150000, setGroup: sg1)
        
        // Superset group
        let ex2a = builder.createExercise(name: "Pushup", muscleGroup: .chest)
        let ex2b = builder.createExercise(name: "Pullup", muscleGroup: .back)
        let sg2 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex2a, workout: workout)
        sg2.secondaryExercise = ex2b
        database.newSuperSet(
            repetitionsFirstExercise: 15,
            repetitionsSecondExercise: 10,
            weightFirstExercise: 0,
            weightSecondExercise: 0,
            setGroup: sg2
        )
        
        // Drop set group
        let ex3 = builder.createExercise(name: "Tricep Extension", muscleGroup: .triceps)
        let sg3 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex3, workout: workout)
        database.newDropSet(repetitions: [12, 10, 8], weights: [15000, 12000, 9000], setGroup: sg3)
        
        let dto = WorkoutDTO(from: workout)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups.count, 3)
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .standard)
        XCTAssertEqual(decoded.setGroups[0].sets[0].repetitions, 5)
        XCTAssertEqual(decoded.setGroups[0].sets[0].weight, 150000)
        XCTAssertEqual(decoded.setGroups[1].sets[0].type, .superSet)
        XCTAssertNotNil(decoded.setGroups[1].secondaryExercise)
        XCTAssertEqual(decoded.setGroups[2].sets[0].type, .dropSet)
        XCTAssertEqual(decoded.setGroups[2].sets[0].dropSetRepetitions, [12, 10, 8])
    }
    
    func testWorkoutDTOExerciseMuscleGroupPreserved() throws {
        let workout = database.newWorkout(name: "MG Test", date: Date())
        let exercise = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sg)
        
        let dto = WorkoutDTO(from: workout)
        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let decoded = try JSONDecoder().decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].exercise.type, .legs)
    }
    
    func testWorkoutDTODefaultExerciseFlagPreserved() throws {
        let workout = database.newWorkout(name: "Default Ex Test", date: Date())
        let defaultExercise = builder.createExercise(name: "_default.benchPress", muscleGroup: .chest)
        let customExercise = builder.createExercise(name: "My Custom Press", muscleGroup: .chest)
        
        let sg1 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: defaultExercise, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 80000, setGroup: sg1)
        
        let sg2 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: customExercise, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 50000, setGroup: sg2)
        
        let dto = WorkoutDTO(from: workout)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].exercise.isDefaultExercise, true)
        XCTAssertEqual(decoded.setGroups[1].exercise.isDefaultExercise, false)
    }
}

// MARK: - TemplateDTOCodable Tests (Codable round-trip for sharing)

final class TemplateDTOCodableTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    func testTemplateDTOFromEntityRoundTrip() throws {
        let exercise = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let template = database.newTemplate(name: "Push Template")
        let sg = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 8, weight: 85000, setGroup: sg)
        
        let dto = TemplateDTO(from: template)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.name, "Push Template")
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertNotNil(decoded.appStoreURL)
        XCTAssertEqual(decoded.setGroups.count, 1)
        XCTAssertEqual(decoded.setGroups[0].sets.count, 2)
    }
    
    func testTemplateDTOWithSuperSetRoundTrip() throws {
        let exA = builder.createExercise(name: "Military Press", muscleGroup: .shoulders)
        let exB = builder.createExercise(name: "Lateral Raise", muscleGroup: .shoulders)
        let template = database.newTemplate(name: "Shoulder Template")
        let sg = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: exA,
            template: template
        )
        sg.secondaryExercise = exB
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 8,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 40000,
            weightSecondExercise: 10000,
            setGroup: sg
        )
        
        let dto = TemplateDTO(from: template)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        let decodedSet = decoded.setGroups[0].sets[0]
        XCTAssertEqual(decodedSet.type, .superSet)
        XCTAssertEqual(decodedSet.repetitionsFirstExercise, 8)
        XCTAssertEqual(decodedSet.repetitionsSecondExercise, 15)
        XCTAssertNotNil(decoded.setGroups[0].secondaryExercise)
        XCTAssertEqual(decoded.setGroups[0].secondaryExercise?.name, "Lateral Raise")
    }
    
    func testTemplateDTOWithDropSetRoundTrip() throws {
        let exercise = builder.createExercise(name: "Leg Press", muscleGroup: .legs)
        let template = database.newTemplate(name: "Leg Template")
        let sg = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            template: template
        )
        database.newTemplateDropSet(
            repetitions: [12, 10, 8, 6],
            weights: [100000, 80000, 60000, 40000],
            templateSetGroup: sg
        )
        
        let dto = TemplateDTO(from: template)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        let decodedSet = decoded.setGroups[0].sets[0]
        XCTAssertEqual(decodedSet.type, .dropSet)
        XCTAssertEqual(decodedSet.dropSetRepetitions, [12, 10, 8, 6])
        XCTAssertEqual(decodedSet.dropSetWeights, [100000, 80000, 60000, 40000])
    }
    
    func testTemplateDTOMixedSetTypesRoundTrip() throws {
        let ex1 = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let ex2a = builder.createExercise(name: "Lunge", muscleGroup: .legs)
        let ex2b = builder.createExercise(name: "Step Up", muscleGroup: .legs)
        let ex3 = builder.createExercise(name: "Calf Raise", muscleGroup: .legs)
        
        let template = database.newTemplate(name: "Full Leg Day")
        
        // Standard set group
        let sg1 = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: ex1, template: template)
        database.newTemplateStandardSet(repetitions: 5, weight: 120000, setGroup: sg1)
        database.newTemplateStandardSet(repetitions: 5, weight: 120000, setGroup: sg1)
        
        // Superset group
        let sg2 = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: ex2a, template: template)
        sg2.secondaryExercise = ex2b
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 40000,
            weightSecondExercise: 20000,
            setGroup: sg2
        )
        
        // Drop set group
        let sg3 = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: ex3, template: template)
        database.newTemplateDropSet(repetitions: [20, 15, 10], weights: [30000, 25000, 20000], templateSetGroup: sg3)
        
        let dto = TemplateDTO(from: template)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups.count, 3)
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .standard)
        XCTAssertEqual(decoded.setGroups[0].sets.count, 2)
        XCTAssertEqual(decoded.setGroups[1].sets[0].type, .superSet)
        XCTAssertEqual(decoded.setGroups[2].sets[0].type, .dropSet)
    }
    
    func testTemplateDTOPreservesRestDurationsForAllSetTypes() throws {
        let primary = builder.createExercise(name: "Incline Press", muscleGroup: .chest)
        let secondary = builder.createExercise(name: "Cable Fly", muscleGroup: .chest)
        let dropExercise = builder.createExercise(name: "Lateral Raise", muscleGroup: .shoulders)
        
        let template = database.newTemplate(name: "Rest Template")
        
        let standardGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: primary,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 10, weight: 70000, restDuration: 120, setGroup: standardGroup)
        
        let superGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: primary,
            template: template
        )
        superGroup.secondaryExercise = secondary
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 15,
            weightFirstExercise: 30000,
            weightSecondExercise: 12000,
            restDuration: 45,
            setGroup: superGroup
        )
        
        let dropGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: dropExercise,
            template: template
        )
        database.newTemplateDropSet(
            repetitions: [15, 12, 10],
            weights: [12000, 10000, 8000],
            restDuration: 30,
            templateSetGroup: dropGroup
        )
        
        let dto = TemplateDTO(from: template)
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].restDuration, 120)
        XCTAssertEqual(decoded.setGroups[1].sets[0].restDuration, 45)
        XCTAssertEqual(decoded.setGroups[2].sets[0].restDuration, 30)
    }
}

// MARK: - WorkoutSharingService Tests

final class WorkoutSharingServiceTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    private var sharingService: WorkoutSharingService!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
        sharingService = WorkoutSharingService(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        sharingService = nil
        super.tearDown()
    }
    
    /// Creates a `Database(isPreview: true)` with all preview exercises removed,
    /// so only exercises explicitly added in the test exist.
    private func createCleanDatabase() -> Database {
        let db = Database(isPreview: true)
        let allExercises = db.fetch(Exercise.self) as! [Exercise]
        for exercise in allExercises {
            db.context.delete(exercise)
        }
        try? db.context.save()
        return db
    }
    
    // MARK: - Export Workout Tests
    
    func testExportWorkoutCreatesFile() {
        let workout = builder.createCompleteWorkout(name: "Test Workout", exerciseCount: 2, setsPerExercise: 3)
        
        let url = sharingService.exportWorkout(workout)
        
        XCTAssertNotNil(url, "Export should return a URL")
        XCTAssertEqual(url?.pathExtension, "logitworkout")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
        
        // Clean up
        try? FileManager.default.removeItem(at: url!)
    }
    
    func testExportWorkoutFileContainsValidJSON() throws {
        let workout = builder.createCompleteWorkout(name: "JSON Test", exerciseCount: 1, setsPerExercise: 2)
        
        guard let url = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.name, "JSON Test")
        XCTAssertEqual(decoded.setGroups.count, 1)
        XCTAssertEqual(decoded.setGroups[0].sets.count, 2)
    }
    
    func testExportWorkoutWithSpecialCharactersInName() {
        let workout = builder.createCompleteWorkout(
            name: "Push/Pull: Day*1",
            exerciseCount: 1,
            setsPerExercise: 1
        )
        
        let url = sharingService.exportWorkout(workout)
        
        XCTAssertNotNil(url)
        // Filename should be sanitized — no / : * in filename
        let filename = url!.lastPathComponent
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("*"))
        
        try? FileManager.default.removeItem(at: url!)
    }
    
    func testExportWorkoutWithSuperSets() throws {
        let workout = database.newWorkout(name: "Superset Export", date: Date())
        let exA = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Row", muscleGroup: .back)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exA, workout: workout)
        sg.secondaryExercise = exB
        database.newSuperSet(
            repetitionsFirstExercise: 10, repetitionsSecondExercise: 12,
            weightFirstExercise: 80000, weightSecondExercise: 60000,
            setGroup: sg
        )
        
        guard let url = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .superSet)
        XCTAssertNotNil(decoded.setGroups[0].secondaryExercise)
    }
    
    func testExportWorkoutWithDropSets() throws {
        let workout = database.newWorkout(name: "DropSet Export", date: Date())
        let ex = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
        database.newDropSet(repetitions: [10, 8, 6], weights: [20000, 15000, 10000], setGroup: sg)
        
        guard let url = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .dropSet)
        XCTAssertEqual(decoded.setGroups[0].sets[0].dropSetRepetitions, [10, 8, 6])
    }
    
    func testExportWorkoutIncludesRestDurations() throws {
        let workout = database.newWorkout(name: "Rest Export", date: Date())
        let exercise = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let group = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 5, weight: 140000, restDuration: 180, setGroup: group)
        
        guard let url = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkoutDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].restDuration, 180)
    }
    
    func testExportEmptyWorkout() {
        let workout = database.newWorkout(name: "Empty", date: Date())
        
        let url = sharingService.exportWorkout(workout)
        
        XCTAssertNotNil(url)
        try? FileManager.default.removeItem(at: url!)
    }
    
    // MARK: - Export Template Tests
    
    func testExportTemplateCreatesFile() {
        let exercise = builder.createExercise(name: "Press", muscleGroup: .chest)
        let template = database.newTemplate(name: "Push Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        
        let url = sharingService.exportTemplate(template)
        
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.pathExtension, "logittemplate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
        
        try? FileManager.default.removeItem(at: url!)
    }
    
    func testExportTemplateContainsValidJSON() throws {
        let exercise = builder.createExercise(name: "Squat", muscleGroup: .legs)
        let template = database.newTemplate(name: "Leg Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateStandardSet(repetitions: 5, weight: 120000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 5, weight: 120000, setGroup: sg)
        
        guard let url = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.name, "Leg Template")
        XCTAssertEqual(decoded.setGroups.count, 1)
        XCTAssertEqual(decoded.setGroups[0].sets.count, 2)
    }
    
    // MARK: - Export Workout as Template Tests
    
    func testExportWorkoutAsTemplateCreatesFile() {
        let workout = builder.createCompleteWorkout(name: "Export As Template", exerciseCount: 2, setsPerExercise: 2)
        
        let url = sharingService.exportWorkoutAsTemplate(workout)
        
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.pathExtension, "logittemplate")
        
        try? FileManager.default.removeItem(at: url!)
    }
    
    func testExportWorkoutAsTemplatePreservesValues() throws {
        let exercise = builder.createExercise(name: "Bench", muscleGroup: .chest)
        let workout = database.newWorkout(name: "Preserved", date: Date())
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        database.newStandardSet(repetitions: 8, weight: 85000, setGroup: sg)
        
        guard let url = sharingService.exportWorkoutAsTemplate(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        // Should preserve actual reps and weight values
        XCTAssertEqual(decoded.setGroups.count, 1)
        XCTAssertEqual(decoded.setGroups[0].sets[0].repetitions, 10)
        XCTAssertEqual(decoded.setGroups[0].sets[0].weight, 80000)
        XCTAssertEqual(decoded.setGroups[0].sets[1].repetitions, 8)
        XCTAssertEqual(decoded.setGroups[0].sets[1].weight, 85000)
    }
    
    func testExportWorkoutAsTemplatePreservesSuperSetStructure() throws {
        let workout = database.newWorkout(name: "Superset Template", date: Date())
        let exA = builder.createExercise(name: "Press A", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Press B", muscleGroup: .chest)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exA, workout: workout)
        sg.secondaryExercise = exB
        database.newSuperSet(
            repetitionsFirstExercise: 10, repetitionsSecondExercise: 12,
            weightFirstExercise: 80000, weightSecondExercise: 60000,
            setGroup: sg
        )
        
        guard let url = sharingService.exportWorkoutAsTemplate(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .superSet)
        // Values should be preserved from the workout
        XCTAssertEqual(decoded.setGroups[0].sets[0].repetitionsFirstExercise, 10)
        XCTAssertEqual(decoded.setGroups[0].sets[0].repetitionsSecondExercise, 12)
        XCTAssertEqual(decoded.setGroups[0].sets[0].weightFirstExercise, 80000)
        XCTAssertEqual(decoded.setGroups[0].sets[0].weightSecondExercise, 60000)
    }
    
    func testExportWorkoutAsTemplatePreservesDropSetStructure() throws {
        let workout = database.newWorkout(name: "DropSet Template", date: Date())
        let ex = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
        database.newDropSet(repetitions: [10, 8, 6], weights: [20000, 15000, 10000], setGroup: sg)
        
        guard let url = sharingService.exportWorkoutAsTemplate(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].type, .dropSet)
        // Drop set structure and values should be preserved from the workout
        XCTAssertEqual(decoded.setGroups[0].sets[0].dropSetRepetitions?.count, 3)
        XCTAssertEqual(decoded.setGroups[0].sets[0].dropSetWeights?.count, 3)
        XCTAssertEqual(decoded.setGroups[0].sets[0].dropSetRepetitions, [10, 8, 6])
        XCTAssertEqual(decoded.setGroups[0].sets[0].dropSetWeights, [20000, 15000, 10000])
    }
    
    func testExportWorkoutAsTemplatePreservesRestDurations() throws {
        let workout = database.newWorkout(name: "Rest Template Export", date: Date())
        let exercise = builder.createExercise(name: "Split Squat", muscleGroup: .legs)
        let group = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 10, weight: 30000, restDuration: 95, setGroup: group)
        
        guard let url = sharingService.exportWorkoutAsTemplate(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(TemplateDTO.self, from: data)
        
        XCTAssertEqual(decoded.setGroups[0].sets[0].restDuration, 95)
    }
    
    // MARK: - Import Workout Tests
    
    func testImportWorkoutFromFile() throws {
        // Create and export a workout
        let originalWorkout = builder.createCompleteWorkout(name: "Import Test", exerciseCount: 2, setsPerExercise: 3)
        guard let exportURL = sharingService.exportWorkout(originalWorkout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        // Import into a fresh database
        let importDatabase = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDatabase)
        let importedWorkout = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual(importedWorkout.name, "Import Test")
        XCTAssertEqual(importedWorkout.setGroups.count, 2)

        for setGroup in importedWorkout.setGroups {
            XCTAssertEqual(setGroup.sets.count, 3)
            XCTAssertNotNil(setGroup.exercise)
        }
    }

    // LOGITApp.handleIncomingFile dispatches imports to a background queue, so the
    // service must confine entity creation to the context's queue itself.

    func testImportWorkoutFromBackgroundQueue() throws {
        let originalWorkout = builder.createCompleteWorkout(name: "Background Import", exerciseCount: 2, setsPerExercise: 3)
        guard let exportURL = sharingService.exportWorkout(originalWorkout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)

        let importCompleted = expectation(description: "Import completed")
        var importResult: Result<Workout, Error>?
        DispatchQueue.global(qos: .userInitiated).async {
            importResult = Result { try importService.importWorkout(from: exportURL) }
            importCompleted.fulfill()
        }
        wait(for: [importCompleted], timeout: 10)

        let imported = try XCTUnwrap(importResult).get()
        XCTAssertEqual(imported.name, "Background Import")
        XCTAssertEqual(imported.setGroups.count, 2)
        for setGroup in imported.setGroups {
            XCTAssertEqual(setGroup.sets.count, 3)
            XCTAssertNotNil(setGroup.exercise)
        }
    }

    func testImportTemplateFromBackgroundQueue() throws {
        let exercise = builder.createExercise(name: "Cable Row Custom", muscleGroup: .back)
        let template = database.newTemplate(name: "Background Template Import")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateStandardSet(repetitions: 12, weight: 60000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 10, weight: 65000, setGroup: sg)

        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)

        let importCompleted = expectation(description: "Import completed")
        var importResult: Result<Template, Error>?
        DispatchQueue.global(qos: .userInitiated).async {
            importResult = Result { try importService.importTemplate(from: exportURL) }
            importCompleted.fulfill()
        }
        wait(for: [importCompleted], timeout: 10)

        let imported = try XCTUnwrap(importResult).get()
        XCTAssertEqual(imported.name, "Background Template Import")
        XCTAssertEqual(imported.setGroups.count, 1)
        XCTAssertEqual(imported.setGroups[0].sets.count, 2)
        XCTAssertNotNil(imported.setGroups[0].exercise)
    }

    func testImportWorkoutWithSuperSets() throws {
        let workout = database.newWorkout(name: "Superset Import", date: Date())
        let exA = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Dumbbell Row", muscleGroup: .back)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exA, workout: workout)
        sg.secondaryExercise = exB
        database.newSuperSet(
            repetitionsFirstExercise: 10, repetitionsSecondExercise: 12,
            weightFirstExercise: 80000, weightSecondExercise: 60000,
            setGroup: sg
        )
        database.newSuperSet(
            repetitionsFirstExercise: 8, repetitionsSecondExercise: 10,
            weightFirstExercise: 85000, weightSecondExercise: 65000,
            setGroup: sg
        )
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual(imported.setGroups.count, 1)
        let importedSG = imported.setGroups[0]
        XCTAssertNotNil(importedSG.secondaryExercise)
        XCTAssertEqual(importedSG.sets.count, 2)
        
        // Verify first super set
        let firstSet = importedSG.sets[0]
        XCTAssertTrue(firstSet is SuperSet, "Imported set should be a SuperSet")
        if let superSet = firstSet as? SuperSet {
            XCTAssertEqual(Int(superSet.repetitionsFirstExercise), 10)
            XCTAssertEqual(Int(superSet.repetitionsSecondExercise), 12)
            XCTAssertEqual(Int(superSet.weightFirstExercise), 80000)
            XCTAssertEqual(Int(superSet.weightSecondExercise), 60000)
        }
        
        // Verify second super set
        let secondSet = importedSG.sets[1]
        XCTAssertTrue(secondSet is SuperSet, "Second imported set should be a SuperSet")
        if let superSet = secondSet as? SuperSet {
            XCTAssertEqual(Int(superSet.repetitionsFirstExercise), 8)
            XCTAssertEqual(Int(superSet.repetitionsSecondExercise), 10)
        }
    }
    
    func testImportWorkoutWithDropSets() throws {
        let workout = database.newWorkout(name: "DropSet Import", date: Date())
        let ex = builder.createExercise(name: "Leg Curl", muscleGroup: .legs)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
        database.newDropSet(repetitions: [12, 10, 8, 6], weights: [40000, 35000, 30000, 25000], setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        let importedSet = imported.setGroups[0].sets[0]
        XCTAssertTrue(importedSet is DropSet, "Imported set should be a DropSet")
        if let dropSet = importedSet as? DropSet {
            XCTAssertEqual(dropSet.repetitions?.map { Int($0) }, [12, 10, 8, 6])
            XCTAssertEqual(dropSet.weights?.map { Int($0) }, [40000, 35000, 30000, 25000])
        }
    }
    
    func testImportWorkoutWithMixedSetTypes() throws {
        let workout = database.newWorkout(name: "Mixed Import", date: Date())
        
        // Standard
        let ex1 = builder.createExercise(name: "Deadlift Custom", muscleGroup: .back)
        let sg1 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex1, workout: workout)
        database.newStandardSet(repetitions: 5, weight: 150000, setGroup: sg1)
        
        // Superset
        let ex2a = builder.createExercise(name: "PushCustom", muscleGroup: .chest)
        let ex2b = builder.createExercise(name: "PullCustom", muscleGroup: .back)
        let sg2 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex2a, workout: workout)
        sg2.secondaryExercise = ex2b
        database.newSuperSet(
            repetitionsFirstExercise: 15, repetitionsSecondExercise: 10,
            weightFirstExercise: 0, weightSecondExercise: 0,
            setGroup: sg2
        )
        
        // Drop set
        let ex3 = builder.createExercise(name: "ExtensionCustom", muscleGroup: .triceps)
        let sg3 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex3, workout: workout)
        database.newDropSet(repetitions: [12, 10, 8], weights: [15000, 12000, 9000], setGroup: sg3)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual(imported.setGroups.count, 3)
        XCTAssertTrue(imported.setGroups[0].sets[0] is StandardSet)
        XCTAssertTrue(imported.setGroups[1].sets[0] is SuperSet)
        XCTAssertTrue(imported.setGroups[2].sets[0] is DropSet)
    }
    
    func testImportWorkoutPreservesRestDurations() throws {
        let workout = database.newWorkout(name: "Rest Import", date: Date())
        
        let standardExercise = builder.createExercise(name: "Bench Press", muscleGroup: .chest)
        let standardGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: standardExercise,
            workout: workout
        )
        database.newStandardSet(repetitions: 8, weight: 80000, restDuration: 120, setGroup: standardGroup)
        
        let superPrimary = builder.createExercise(name: "Row", muscleGroup: .back)
        let superSecondary = builder.createExercise(name: "Rear Delt Fly", muscleGroup: .shoulders)
        let superGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: superPrimary,
            workout: workout
        )
        superGroup.secondaryExercise = superSecondary
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 14,
            weightFirstExercise: 60000,
            weightSecondExercise: 12000,
            restDuration: 75,
            setGroup: superGroup
        )
        
        let dropExercise = builder.createExercise(name: "Hammer Curl", muscleGroup: .biceps)
        let dropGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: dropExercise,
            workout: workout
        )
        database.newDropSet(
            repetitions: [12, 10, 8],
            weights: [20000, 15000, 10000],
            restDuration: 45,
            setGroup: dropGroup
        )
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual((imported.setGroups[0].sets[0] as? StandardSet)?.restDurationSeconds, 120)
        XCTAssertEqual((imported.setGroups[1].sets[0] as? SuperSet)?.restDurationSeconds, 75)
        XCTAssertEqual((imported.setGroups[2].sets[0] as? DropSet)?.restDurationSeconds, 45)
    }
    
    func testImportWorkoutFlagsAsTemporary() throws {
        let workout = builder.createCompleteWorkout(name: "Temp Flag Test", exerciseCount: 1, setsPerExercise: 1)
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        // Import using the same database so objectID URIs are from the same store
        let imported = try sharingService.importWorkout(from: exportURL)
        
        // The workout should be flagged as temporary
        XCTAssertTrue(database.isTemporaryObject(imported), "Imported workout should be flagged as temporary")
    }
    
    func testImportWorkoutInvalidExtension() {
        let tempDir = FileManager.default.temporaryDirectory
        let wrongURL = tempDir.appendingPathComponent("test.wrongextension")
        FileManager.default.createFile(atPath: wrongURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: wrongURL) }
        
        XCTAssertThrowsError(try sharingService.importWorkout(from: wrongURL)) { error in
            XCTAssertTrue(error is WorkoutSharingService.ImportError)
        }
    }
    
    func testImportWorkoutInvalidJSON() {
        let tempDir = FileManager.default.temporaryDirectory
        let badURL = tempDir.appendingPathComponent("bad.logitworkout")
        
        let badData = "not json content".data(using: .utf8)!
        FileManager.default.createFile(atPath: badURL.path, contents: badData, attributes: nil)
        defer { try? FileManager.default.removeItem(at: badURL) }
        
        XCTAssertThrowsError(try sharingService.importWorkout(from: badURL)) { error in
            if case WorkoutSharingService.ImportError.decodingFailed = error {
                // Expected
            } else {
                XCTFail("Expected decodingFailed error but got \(error)")
            }
        }
    }
    
    // MARK: - Import Template Tests
    
    func testImportTemplateFromFile() throws {
        let exercise = builder.createExercise(name: "Lat Pulldown Custom", muscleGroup: .back)
        let template = database.newTemplate(name: "Back Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateStandardSet(repetitions: 12, weight: 60000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 10, weight: 65000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 8, weight: 70000, setGroup: sg)
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: exportURL)
        
        XCTAssertEqual(imported.name, "Back Template")
        XCTAssertEqual(imported.setGroups.count, 1)
        XCTAssertEqual(imported.setGroups[0].sets.count, 3)
    }
    
    func testImportTemplateWithSuperSets() throws {
        let exA = builder.createExercise(name: "Press Custom", muscleGroup: .shoulders)
        let exB = builder.createExercise(name: "Raise Custom", muscleGroup: .shoulders)
        let template = database.newTemplate(name: "Superset Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exA, template: template)
        sg.secondaryExercise = exB
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 8, repetitionsSecondExercise: 15,
            weightFirstExercise: 40000, weightSecondExercise: 10000,
            setGroup: sg
        )
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: exportURL)
        
        let importedSet = imported.setGroups[0].sets[0]
        XCTAssertTrue(importedSet is TemplateSuperSet, "Imported set should be a TemplateSuperSet")
        XCTAssertNotNil(imported.setGroups[0].secondaryExercise)
        if let superSet = importedSet as? TemplateSuperSet {
            XCTAssertEqual(Int(superSet.repetitionsFirstExercise), 8)
            XCTAssertEqual(Int(superSet.repetitionsSecondExercise), 15)
            XCTAssertEqual(Int(superSet.weightFirstExercise), 40000)
            XCTAssertEqual(Int(superSet.weightSecondExercise), 10000)
        }
    }
    
    func testImportTemplateWithDropSets() throws {
        let exercise = builder.createExercise(name: "Leg Press Custom", muscleGroup: .legs)
        let template = database.newTemplate(name: "DropSet Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateDropSet(
            repetitions: [15, 12, 10, 8, 6],
            weights: [80000, 70000, 60000, 50000, 40000],
            templateSetGroup: sg
        )
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: exportURL)
        
        let importedSet = imported.setGroups[0].sets[0]
        XCTAssertTrue(importedSet is TemplateDropSet, "Imported set should be a TemplateDropSet")
        if let dropSet = importedSet as? TemplateDropSet {
            XCTAssertEqual(dropSet.repetitions?.map { Int($0) }, [15, 12, 10, 8, 6])
            XCTAssertEqual(dropSet.weights?.map { Int($0) }, [80000, 70000, 60000, 50000, 40000])
        }
    }
    
    func testImportTemplatePreservesRestDurations() throws {
        let template = database.newTemplate(name: "Rest Template Import")
        
        let standardExercise = builder.createExercise(name: "Overhead Press", muscleGroup: .shoulders)
        let standardGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: standardExercise,
            template: template
        )
        database.newTemplateStandardSet(repetitions: 8, weight: 50000, restDuration: 90, setGroup: standardGroup)
        
        let superPrimary = builder.createExercise(name: "Dip", muscleGroup: .chest)
        let superSecondary = builder.createExercise(name: "Pull Up", muscleGroup: .back)
        let superGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: superPrimary,
            template: template
        )
        superGroup.secondaryExercise = superSecondary
        database.newTemplateSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 8,
            weightFirstExercise: 0,
            weightSecondExercise: 0,
            restDuration: 60,
            setGroup: superGroup
        )
        
        let dropExercise = builder.createExercise(name: "Cable Curl", muscleGroup: .biceps)
        let dropGroup = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: dropExercise,
            template: template
        )
        database.newTemplateDropSet(
            repetitions: [12, 10, 8],
            weights: [25000, 20000, 15000],
            restDuration: 30,
            templateSetGroup: dropGroup
        )
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: exportURL)
        
        XCTAssertEqual(Int((imported.setGroups[0].sets[0] as? TemplateStandardSet)?.restDuration ?? -1), 90)
        XCTAssertEqual(Int((imported.setGroups[1].sets[0] as? TemplateSuperSet)?.restDuration ?? -1), 60)
        XCTAssertEqual(Int((imported.setGroups[2].sets[0] as? TemplateDropSet)?.restDuration ?? -1), 30)
    }
    
    func testImportTemplateInvalidExtension() {
        let tempDir = FileManager.default.temporaryDirectory
        let wrongURL = tempDir.appendingPathComponent("test.logitworkout")
        
        // Write valid template JSON but with wrong extension
        let dto = TemplateDTO(name: "Test", setGroups: [])
        let data = try! JSONEncoder().encode(dto)
        FileManager.default.createFile(atPath: wrongURL.path, contents: data, attributes: nil)
        defer { try? FileManager.default.removeItem(at: wrongURL) }
        
        XCTAssertThrowsError(try sharingService.importTemplate(from: wrongURL)) { error in
            XCTAssertTrue(error is WorkoutSharingService.ImportError)
        }
    }
    
    func testImportTemplateInvalidJSON() {
        let tempDir = FileManager.default.temporaryDirectory
        let badURL = tempDir.appendingPathComponent("bad.logittemplate")
        
        let badData = "{invalid}".data(using: .utf8)!
        FileManager.default.createFile(atPath: badURL.path, contents: badData, attributes: nil)
        defer { try? FileManager.default.removeItem(at: badURL) }
        
        XCTAssertThrowsError(try sharingService.importTemplate(from: badURL)) { error in
            if case WorkoutSharingService.ImportError.decodingFailed = error {
                // Expected
            } else {
                XCTFail("Expected decodingFailed error but got \(error)")
            }
        }
    }
    
    func testImportTemplateFlagsAsTemporary() throws {
        let exercise = builder.createExercise(name: "Press Test Custom", muscleGroup: .chest)
        let template = database.newTemplate(name: "Temp Test Template")
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        database.newTemplateStandardSet(repetitions: 10, weight: 50000, setGroup: sg)
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        // Import using the same database so objectID URIs are from the same store
        let imported = try sharingService.importTemplate(from: exportURL)
        
        // The template should be flagged as temporary
        XCTAssertTrue(database.isTemporaryObject(imported), "Imported template should be flagged as temporary")
    }
    
    // MARK: - Exercise Matching Tests
    
    func testImportMatchesDefaultExerciseByName() throws {
        // Create a "default" exercise in the import database
        let importDB = Database(isPreview: true)
        let defaultExercise = Exercise(context: importDB.context)
        defaultExercise.id = UUID()
        defaultExercise.name = "_default.benchPress"
        defaultExercise.muscleGroup = .chest
        try importDB.context.save()
        
        // Create a workout referencing a default exercise
        let workout = database.newWorkout(name: "Default Ex Match", date: Date())
        let exercise = builder.createExercise(name: "_default.benchPress", muscleGroup: .chest)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        // The imported workout should use the existing exercise, not create a new one
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertEqual(importedExercise?.objectID, defaultExercise.objectID,
                       "Should reuse existing default exercise")
    }
    
    func testImportCreatesNewCustomExercise() throws {
        let importDB = Database(isPreview: true)
        
        // Create a workout with a custom exercise
        let workout = database.newWorkout(name: "Custom Ex Test", date: Date())
        let uniqueName = "Unique Custom Exercise \(UUID().uuidString.prefix(8))"
        let exercise = builder.createExercise(name: uniqueName, muscleGroup: .biceps)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 20000, setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        // Should create a new exercise since no match exists
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.name, uniqueName)
        XCTAssertEqual(importedExercise?.muscleGroup, .biceps)
    }
    
    func testImportExerciseWithNilNameCreatesUnknown() throws {
        // Create a workout JSON manually with nil exercise name
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Nil Name Test",
            "setGroups": [
                [
                    "exercise": ["name": NSNull(), "type": "chest"],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 10, "weight": 50000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        
        let data = try JSONSerialization.data(withJSONObject: json)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("nilname.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        // Exercise should be created with "Unknown" name
        XCTAssertEqual(imported.setGroups[0].exercise?.name, "Unknown")
    }
    
    func testImportWorkoutWithoutSetTypeDefaultsToStandardSet() throws {
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Legacy Workout",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Legacy Bench", "type": "chest", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["repetitions": 10, "weight": 60000, "restDuration": 90]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("legacy.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let set = imported.setGroups[0].sets[0]
        XCTAssertTrue(set is StandardSet)
        XCTAssertEqual((set as? StandardSet)?.restDurationSeconds, 90)
        XCTAssertEqual((set as? StandardSet)?.repetitions, 10)
        XCTAssertEqual((set as? StandardSet)?.weight, 60000)
    }
    
    // MARK: - Custom Exercise Matching Tests
    
    func testImportCreatesNewExerciseWhenReceiverHasNoCustomExercises() throws {
        // Simulate: Sender has custom exercise "Zercher Squat", receiver has no exercises at all
        let importDB = createCleanDatabase()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Custom Only",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Zercher Squat", "type": "legs", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 8, "weight": 100000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("custom_new.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.name, "Zercher Squat")
        XCTAssertEqual(importedExercise?.muscleGroup, .legs)
        XCTAssertTrue(importDB.isTemporaryObject(importedExercise!), "Newly created exercise should be flagged as temporary")
    }
    
    func testImportCreatesNewExerciseWhenReceiverHasDifferentCustomExercises() throws {
        // Simulate: Receiver has "Goblet Squat", sender shares "Hip Thrust" — completely different, no match
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Goblet Squat"
        existingExercise.muscleGroup = .legs
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Different Custom",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Hip Thrust", "type": "legs", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 12, "weight": 60000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("custom_different.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.name, "Hip Thrust", "Should create new exercise, not reuse existing")
        XCTAssertNotEqual(importedExercise?.objectID, existingExercise.objectID)
    }
    
    func testImportFuzzyMatchesExerciseWithSpaceDifference() throws {
        // Simulate: Receiver has "Bench Press", sender has "BenchPress" (no space)
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Bench Press"
        existingExercise.muscleGroup = .chest
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Fuzzy Space Test",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "BenchPress", "type": "chest", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 10, "weight": 80000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_space.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        // Fuzzy search should match "BenchPress" to "Bench Press"
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match 'BenchPress' to 'Bench Press'")
    }
    
    func testImportFuzzyMatchesExerciseWithExtraSpace() throws {
        // Simulate: Receiver has "LatPulldown", sender has "Lat Pulldown" (added space)
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "LatPulldown"
        existingExercise.muscleGroup = .back
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Fuzzy Extra Space",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Lat Pulldown", "type": "back", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 12, "weight": 50000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_extra_space.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match 'Lat Pulldown' to 'LatPulldown'")
    }
    
    func testImportFuzzyMatchesExerciseWithMinorTypo() throws {
        // Simulate: Receiver has "Romanian Deadlift", sender has "Romanian Deadlifts" (extra 's')
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Romanian Deadlift"
        existingExercise.muscleGroup = .legs
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Fuzzy Typo Test",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Romanian Deadlifts", "type": "legs", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 8, "weight": 100000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_typo.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match 'Romanian Deadlifts' to 'Romanian Deadlift'")
    }
    
    func testImportFuzzyMatchesCaseInsensitive() throws {
        // Simulate: Receiver has "incline bench press", sender has "Incline Bench Press" (different case)
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "incline bench press"
        existingExercise.muscleGroup = .chest
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Case Test",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Incline Bench Press", "type": "chest", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 10, "weight": 60000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_case.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match regardless of case")
    }
    
    func testImportDoesNotFuzzyMatchCompletelyDifferentExercise() throws {
        // Simulate: Receiver has "Squat", sender has "Bicep Curl" — should NOT match
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Squat"
        existingExercise.muscleGroup = .legs
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "No False Match",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Bicep Curl", "type": "biceps", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 12, "weight": 15000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("no_false_match.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertNotEqual(importedExercise?.objectID, existingExercise.objectID,
                          "Should NOT match completely different exercises")
        XCTAssertEqual(importedExercise?.name, "Bicep Curl", "Should create new exercise")
    }
    
    func testImportFuzzyMatchWithMultipleCustomExercisesPicksBest() throws {
        // Simulate: Receiver has "Bench Press", "Incline Bench Press", "Cable Fly"
        // Sender shares "Bench press" — should match "Bench Press" (closest)
        let importDB = createCleanDatabase()
        let benchPress = Exercise(context: importDB.context)
        benchPress.id = UUID()
        benchPress.name = "Bench Press"
        benchPress.muscleGroup = .chest
        
        let inclineBench = Exercise(context: importDB.context)
        inclineBench.id = UUID()
        inclineBench.name = "Incline Bench Press"
        inclineBench.muscleGroup = .chest
        
        let cableFly = Exercise(context: importDB.context)
        cableFly.id = UUID()
        cableFly.name = "Cable Fly"
        cableFly.muscleGroup = .chest
        
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Best Match Test",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Bench press", "type": "chest", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 10, "weight": 80000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("best_match.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, benchPress.objectID,
                       "Should match 'Bench press' to 'Bench Press' (exact match up to case)")
    }
    
    func testImportCustomExerciseInTemplateCreatesNew() throws {
        // Same scenario but for template import: sender's custom exercise doesn't exist on receiver
        let importDB = createCleanDatabase()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Custom Template",
            "setGroups": [
                [
                    "exercise": ["name": "Landmine Press", "type": "shoulders", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 10, "weight": 40000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("custom_template.logittemplate")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.name, "Landmine Press")
        XCTAssertEqual(importedExercise?.muscleGroup, .shoulders)
    }
    
    func testImportFuzzyMatchCustomExerciseInTemplate() throws {
        // Template import: Receiver has "Skull Crushers", sender has "Skull Crusher" (singular vs plural)
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Skull Crushers"
        existingExercise.muscleGroup = .triceps
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Fuzzy Template Match",
            "setGroups": [
                [
                    "exercise": ["name": "Skull Crusher", "type": "triceps", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [
                        ["type": "standard", "repetitions": 12, "weight": 25000]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_template.logittemplate")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match 'Skull Crusher' to 'Skull Crushers'")
    }
    
    func testImportMultipleCustomExercisesSomeExistSomeDont() throws {
        // Simulate: Workout has 3 exercises
        //   - "Bench Press" — receiver has "BenchPress" (fuzzy match)
        //   - "Nordic Curl" — receiver doesn't have (create new)
        //   - "Face Pull"  — receiver has exact match
        let importDB = createCleanDatabase()
        
        let existingBenchPress = Exercise(context: importDB.context)
        existingBenchPress.id = UUID()
        existingBenchPress.name = "BenchPress"
        existingBenchPress.muscleGroup = .chest
        
        let existingFacePull = Exercise(context: importDB.context)
        existingFacePull.id = UUID()
        existingFacePull.name = "Face Pull"
        existingFacePull.muscleGroup = .shoulders
        
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Mixed Match Workout",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Bench Press", "type": "chest", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [["type": "standard", "repetitions": 10, "weight": 80000]]
                ] as [String: Any],
                [
                    "exercise": ["name": "Nordic Curl", "type": "legs", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [["type": "standard", "repetitions": 8, "weight": 0]]
                ] as [String: Any],
                [
                    "exercise": ["name": "Face Pull", "type": "shoulders", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [["type": "standard", "repetitions": 15, "weight": 20000]]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("mixed_match.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        XCTAssertEqual(imported.setGroups.count, 3)
        
        // "Bench Press" → fuzzy matches "BenchPress"
        let benchEx = imported.setGroups[0].exercise
        XCTAssertEqual(benchEx?.objectID, existingBenchPress.objectID,
                       "Should fuzzy match 'Bench Press' to 'BenchPress'")
        
        // "Nordic Curl" → no match, new exercise created
        let nordicEx = imported.setGroups[1].exercise
        XCTAssertNotEqual(nordicEx?.objectID, existingBenchPress.objectID)
        XCTAssertNotEqual(nordicEx?.objectID, existingFacePull.objectID)
        XCTAssertEqual(nordicEx?.name, "Nordic Curl")
        XCTAssertEqual(nordicEx?.muscleGroup, .legs)
        
        // "Face Pull" → exact match
        let facePullEx = imported.setGroups[2].exercise
        XCTAssertEqual(facePullEx?.objectID, existingFacePull.objectID,
                       "Should exact match 'Face Pull'")
    }
    
    func testImportFuzzyMatchExerciseWithHyphenVsSpace() throws {
        // Simulate: Receiver has "Close-Grip Bench Press", sender has "Close Grip Bench Press"
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Close-Grip Bench Press"
        existingExercise.muscleGroup = .triceps
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Hyphen Test",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Close Grip Bench Press", "type": "triceps", "isDefaultExercise": false] as [String: Any],
                    "setType": "standard",
                    "sets": [["type": "standard", "repetitions": 10, "weight": 70000]]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuzzy_hyphen.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let importedExercise = imported.setGroups[0].exercise
        XCTAssertNotNil(importedExercise)
        XCTAssertEqual(importedExercise?.objectID, existingExercise.objectID,
                       "Fuzzy search should match 'Close Grip Bench Press' to 'Close-Grip Bench Press'")
    }
    
    func testImportCustomExerciseWithSuperSetBothNew() throws {
        // Simulate: Superset where BOTH exercises are custom and the receiver has neither
        let importDB = createCleanDatabase()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "New Superset Exercises",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Zottman Curl", "type": "biceps", "isDefaultExercise": false] as [String: Any],
                    "secondaryExercise": ["name": "JM Press", "type": "triceps", "isDefaultExercise": false] as [String: Any],
                    "setType": "superSet",
                    "sets": [
                        [
                            "type": "superSet",
                            "repetitionsFirstExercise": 12,
                            "repetitionsSecondExercise": 10,
                            "weightFirstExercise": 15000,
                            "weightSecondExercise": 30000
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("superset_new.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let group = imported.setGroups[0]
        XCTAssertEqual(group.exercise?.name, "Zottman Curl")
        XCTAssertEqual(group.exercise?.muscleGroup, .biceps)
        XCTAssertEqual(group.secondaryExercise?.name, "JM Press")
        XCTAssertEqual(group.secondaryExercise?.muscleGroup, .triceps)
        XCTAssertNotEqual(group.exercise?.objectID, group.secondaryExercise?.objectID)
        
        let superSet = group.sets[0] as? SuperSet
        XCTAssertNotNil(superSet)
        XCTAssertEqual(superSet?.repetitionsFirstExercise, 12)
        XCTAssertEqual(superSet?.repetitionsSecondExercise, 10)
    }
    
    func testImportCustomExerciseWithSuperSetOneFuzzyMatchOneNew() throws {
        // Simulate: Superset where primary is "Hammer Curls" (receiver has "Hammer Curl"),
        // secondary is "Overhead Extension" (receiver doesn't have)
        let importDB = createCleanDatabase()
        let existingExercise = Exercise(context: importDB.context)
        existingExercise.id = UUID()
        existingExercise.name = "Hammer Curl"
        existingExercise.muscleGroup = .biceps
        try importDB.context.save()
        
        let json: [String: Any] = [
            "formatVersion": 1,
            "name": "Mixed Superset Match",
            "date": ISO8601DateFormatter().string(from: Date()),
            "setGroups": [
                [
                    "exercise": ["name": "Hammer Curls", "type": "biceps", "isDefaultExercise": false] as [String: Any],
                    "secondaryExercise": ["name": "Overhead Extension", "type": "triceps", "isDefaultExercise": false] as [String: Any],
                    "setType": "superSet",
                    "sets": [
                        [
                            "type": "superSet",
                            "repetitionsFirstExercise": 10,
                            "repetitionsSecondExercise": 12,
                            "weightFirstExercise": 20000,
                            "weightSecondExercise": 25000
                        ] as [String: Any]
                    ]
                ] as [String: Any]
            ],
            "appStoreURL": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("superset_mixed.logitworkout")
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: fileURL)
        
        let group = imported.setGroups[0]
        // Primary: "Hammer Curls" should fuzzy match "Hammer Curl"
        XCTAssertEqual(group.exercise?.objectID, existingExercise.objectID,
                       "Should fuzzy match 'Hammer Curls' to 'Hammer Curl'")
        
        // Secondary: "Overhead Extension" has no match, should be created new
        XCTAssertEqual(group.secondaryExercise?.name, "Overhead Extension")
        XCTAssertEqual(group.secondaryExercise?.muscleGroup, .triceps)
        XCTAssertNotEqual(group.secondaryExercise?.objectID, existingExercise.objectID)
    }
    
    // MARK: - Full Round-Trip Tests (Export → Import with all data)
    
    func testFullRoundTripWorkoutPreservesAllData() throws {
        let date = Date()
        let endDate = date.addingTimeInterval(3600)
        let workout = database.newWorkout(name: "Full Round Trip", date: date)
        workout.endDate = endDate
        
        let exercise = builder.createExercise(name: "Custom Squat RT", muscleGroup: .legs)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        database.newStandardSet(repetitions: 5, weight: 140000, setGroup: sg)
        database.newStandardSet(repetitions: 5, weight: 145000, setGroup: sg)
        database.newStandardSet(repetitions: 3, weight: 150000, setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual(imported.name, "Full Round Trip")
        XCTAssertEqual(imported.setGroups.count, 1)
        XCTAssertEqual(imported.setGroups[0].sets.count, 3)
        
        // Verify individual set values
        let sets = imported.setGroups[0].sets
        if let s1 = sets[0] as? StandardSet {
            XCTAssertEqual(Int(s1.repetitions), 5)
            XCTAssertEqual(Int(s1.weight), 140000)
        } else {
            XCTFail("Expected StandardSet")
        }
        if let s2 = sets[1] as? StandardSet {
            XCTAssertEqual(Int(s2.repetitions), 5)
            XCTAssertEqual(Int(s2.weight), 145000)
        }
        if let s3 = sets[2] as? StandardSet {
            XCTAssertEqual(Int(s3.repetitions), 3)
            XCTAssertEqual(Int(s3.weight), 150000)
        }
    }
    
    func testFullRoundTripTemplatePreservesAllData() throws {
        let template = database.newTemplate(name: "Full Template RT")
        
        let ex = builder.createExercise(name: "Custom OHP RT", muscleGroup: .shoulders)
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: ex, template: template)
        database.newTemplateStandardSet(repetitions: 8, weight: 40000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 8, weight: 40000, setGroup: sg)
        database.newTemplateStandardSet(repetitions: 6, weight: 45000, setGroup: sg)
        
        guard let exportURL = sharingService.exportTemplate(template) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importTemplate(from: exportURL)
        
        XCTAssertEqual(imported.name, "Full Template RT")
        XCTAssertEqual(imported.setGroups.count, 1)
        XCTAssertEqual(imported.setGroups[0].sets.count, 3)
        
        if let s1 = imported.setGroups[0].sets[0] as? TemplateStandardSet {
            XCTAssertEqual(Int(s1.repetitions), 8)
            XCTAssertEqual(Int(s1.weight), 40000)
        } else {
            XCTFail("Expected TemplateStandardSet")
        }
    }
    
    func testFullRoundTripComplexWorkout() throws {
        // A workout with ALL set types and multiple set groups
        let workout = database.newWorkout(name: "Complex RT", date: Date())
        
        // Group 1: 3 standard sets
        let ex1 = builder.createExercise(name: "RT Squat Custom", muscleGroup: .legs)
        let sg1 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex1, workout: workout)
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sg1)
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sg1)
        database.newStandardSet(repetitions: 5, weight: 100000, setGroup: sg1)
        
        // Group 2: 2 super sets
        let ex2a = builder.createExercise(name: "RT Bench Custom", muscleGroup: .chest)
        let ex2b = builder.createExercise(name: "RT Row Custom", muscleGroup: .back)
        let sg2 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex2a, workout: workout)
        sg2.secondaryExercise = ex2b
        database.newSuperSet(
            repetitionsFirstExercise: 10, repetitionsSecondExercise: 12,
            weightFirstExercise: 70000, weightSecondExercise: 50000,
            setGroup: sg2
        )
        database.newSuperSet(
            repetitionsFirstExercise: 8, repetitionsSecondExercise: 10,
            weightFirstExercise: 75000, weightSecondExercise: 55000,
            setGroup: sg2
        )
        
        // Group 3: 1 drop set with 5 drops
        let ex3 = builder.createExercise(name: "RT Curl Custom", muscleGroup: .biceps)
        let sg3 = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex3, workout: workout)
        database.newDropSet(
            repetitions: [12, 10, 8, 6, 4],
            weights: [25000, 22000, 18000, 15000, 12000],
            setGroup: sg3
        )
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        // Verify structure
        XCTAssertEqual(imported.name, "Complex RT")
        XCTAssertEqual(imported.setGroups.count, 3)
        
        // Group 1: Standard sets
        XCTAssertEqual(imported.setGroups[0].sets.count, 3)
        XCTAssertTrue(imported.setGroups[0].sets.allSatisfy { $0 is StandardSet })
        
        // Group 2: Super sets
        XCTAssertEqual(imported.setGroups[1].sets.count, 2)
        XCTAssertTrue(imported.setGroups[1].sets.allSatisfy { $0 is SuperSet })
        XCTAssertNotNil(imported.setGroups[1].secondaryExercise)
        
        // Group 3: Drop set
        XCTAssertEqual(imported.setGroups[2].sets.count, 1)
        let dropSet = imported.setGroups[2].sets[0] as! DropSet
        XCTAssertEqual(dropSet.repetitions?.count, 5)
        XCTAssertEqual(dropSet.repetitions?.map { Int($0) }, [12, 10, 8, 6, 4])
        XCTAssertEqual(dropSet.weights?.map { Int($0) }, [25000, 22000, 18000, 15000, 12000])
    }
    
    // MARK: - Edge Cases
    
    func testExportAndImportWorkoutWithZeroWeightSets() throws {
        let workout = database.newWorkout(name: "Bodyweight", date: Date())
        let ex = builder.createExercise(name: "Pushup Custom", muscleGroup: .chest)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
        database.newStandardSet(repetitions: 20, weight: 0, setGroup: sg)
        database.newStandardSet(repetitions: 15, weight: 0, setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        let set1 = imported.setGroups[0].sets[0] as! StandardSet
        XCTAssertEqual(Int(set1.repetitions), 20)
        XCTAssertEqual(Int(set1.weight), 0)
    }
    
    func testExportAndImportSingleDropWithOneElement() throws {
        let workout = database.newWorkout(name: "Single Drop", date: Date())
        let ex = builder.createExercise(name: "Single Drop Ex Custom", muscleGroup: .chest)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
        database.newDropSet(repetitions: [10], weights: [50000], setGroup: sg)
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        let dropSet = imported.setGroups[0].sets[0] as! DropSet
        XCTAssertEqual(dropSet.repetitions?.count, 1)
        XCTAssertEqual(dropSet.weights?.count, 1)
    }
    
    func testExportAndImportManySetGroups() throws {
        let workout = database.newWorkout(name: "Many Groups", date: Date())
        
        for i in 0..<10 {
            let ex = builder.createExercise(name: "Exercise \(i) Custom", muscleGroup: .chest)
            let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: ex, workout: workout)
            for j in 0..<5 {
                database.newStandardSet(repetitions: 10 + j, weight: (50 + j * 5) * 1000, setGroup: sg)
            }
        }
        
        guard let exportURL = sharingService.exportWorkout(workout) else {
            XCTFail("Export returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(at: exportURL) }
        
        let importDB = Database(isPreview: true)
        let importService = WorkoutSharingService(database: importDB)
        let imported = try importService.importWorkout(from: exportURL)
        
        XCTAssertEqual(imported.setGroups.count, 10)
        for sg in imported.setGroups {
            XCTAssertEqual(sg.sets.count, 5)
        }
    }
    
    // MARK: - Filename Sanitization Tests
    
    func testSanitizeFilenameRemovesInvalidChars() {
        let workout = database.newWorkout(name: "Test/Workout:Name*Bad", date: Date())
        let url = sharingService.exportWorkout(workout)
        
        XCTAssertNotNil(url)
        let filename = url!.deletingPathExtension().lastPathComponent
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("*"))
        
        try? FileManager.default.removeItem(at: url!)
    }
    
    func testSanitizeEmptyNameUsesFallback() throws {
        let workout = database.newWorkout(name: "", date: Date())
        let url = sharingService.exportWorkout(workout)
        
        XCTAssertNotNil(url)
        // Should use fallback name
        let filename = url!.deletingPathExtension().lastPathComponent
        XCTAssertFalse(filename.isEmpty)
        
        try? FileManager.default.removeItem(at: url!)
    }
}

// MARK: - ExerciseDTO Tests

final class ExerciseDTOTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    func testExerciseDTOFromDefaultExercise() {
        let exercise = builder.createExercise(name: "_default.benchPress", muscleGroup: .chest)
        
        let dto = ExerciseDTO(from: exercise)
        
        XCTAssertEqual(dto.name, "_default.benchPress")
        XCTAssertEqual(dto.type, .chest)
        XCTAssertEqual(dto.isDefaultExercise, true)
    }
    
    func testExerciseDTOFromCustomExercise() {
        let exercise = builder.createExercise(name: "My Custom Press", muscleGroup: .chest)
        
        let dto = ExerciseDTO(from: exercise)
        
        XCTAssertEqual(dto.name, "My Custom Press")
        XCTAssertEqual(dto.type, .chest)
        XCTAssertEqual(dto.isDefaultExercise, false)
    }
    
    func testExerciseDTOFromNilExercise() {
        let dto = ExerciseDTO(from: nil)
        
        XCTAssertNil(dto.name)
        XCTAssertNil(dto.type)
        XCTAssertNil(dto.isDefaultExercise)
    }
    
    func testExerciseDTORoundTrip() throws {
        let exercise = builder.createExercise(name: "Round Trip Exercise", muscleGroup: .legs)
        let dto = ExerciseDTO(from: exercise)
        
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(ExerciseDTO.self, from: data)
        
        XCTAssertEqual(decoded.name, "Round Trip Exercise")
        XCTAssertEqual(decoded.type, .legs)
        XCTAssertEqual(decoded.isDefaultExercise, false)
    }
    
    func testExerciseDTOAllMuscleGroups() throws {
        let muscleGroups: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .legs, .abdominals, .cardio]
        
        for mg in muscleGroups {
            let exercise = builder.createExercise(name: "Test \(mg)", muscleGroup: mg)
            let dto = ExerciseDTO(from: exercise)
            let data = try JSONEncoder().encode(dto)
            let decoded = try JSONDecoder().decode(ExerciseDTO.self, from: data)
            XCTAssertEqual(decoded.type, mg, "MuscleGroup \(mg) should survive encoding/decoding")
        }
    }
}

// MARK: - WorkoutSetDTO Tests

final class WorkoutSetDTOTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    func testStandardSetDTOFields() {
        let workout = database.newWorkout(name: "Test", date: Date())
        let exercise = builder.createExercise(name: "Press", muscleGroup: .chest)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        let standardSet = database.newStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        
        let dto = WorkoutSetDTO(from: standardSet)
        
        XCTAssertEqual(dto.type, .standard)
        XCTAssertEqual(dto.repetitions, 10)
        XCTAssertEqual(dto.weight, 80000)
        XCTAssertNil(dto.repetitionsFirstExercise)
        XCTAssertNil(dto.repetitionsSecondExercise)
        XCTAssertNil(dto.weightFirstExercise)
        XCTAssertNil(dto.weightSecondExercise)
        XCTAssertNil(dto.dropSetRepetitions)
        XCTAssertNil(dto.dropSetWeights)
    }
    
    func testSuperSetDTOFields() {
        let workout = database.newWorkout(name: "Test", date: Date())
        let exA = builder.createExercise(name: "Press A", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Row B", muscleGroup: .back)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exA, workout: workout)
        sg.secondaryExercise = exB
        let superSet = database.newSuperSet(
            repetitionsFirstExercise: 10, repetitionsSecondExercise: 12,
            weightFirstExercise: 80000, weightSecondExercise: 60000,
            setGroup: sg
        )
        
        let dto = WorkoutSetDTO(from: superSet)
        
        XCTAssertEqual(dto.type, .superSet)
        XCTAssertEqual(dto.repetitionsFirstExercise, 10)
        XCTAssertEqual(dto.repetitionsSecondExercise, 12)
        XCTAssertEqual(dto.weightFirstExercise, 80000)
        XCTAssertEqual(dto.weightSecondExercise, 60000)
        XCTAssertNil(dto.repetitions)
        XCTAssertNil(dto.weight)
        XCTAssertNil(dto.dropSetRepetitions)
        XCTAssertNil(dto.dropSetWeights)
    }
    
    func testDropSetDTOFields() {
        let workout = database.newWorkout(name: "Test", date: Date())
        let exercise = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        let dropSet = database.newDropSet(
            repetitions: [10, 8, 6],
            weights: [20000, 15000, 10000],
            setGroup: sg
        )
        
        let dto = WorkoutSetDTO(from: dropSet)
        
        XCTAssertEqual(dto.type, .dropSet)
        XCTAssertEqual(dto.dropSetRepetitions, [10, 8, 6])
        XCTAssertEqual(dto.dropSetWeights, [20000, 15000, 10000])
        XCTAssertNil(dto.repetitions)
        XCTAssertNil(dto.weight)
        XCTAssertNil(dto.repetitionsFirstExercise)
    }
    
    func testDropSetDTOWithManyDrops() {
        let workout = database.newWorkout(name: "Test", date: Date())
        let exercise = builder.createExercise(name: "Extension", muscleGroup: .triceps)
        let sg = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        let dropSet = database.newDropSet(
            repetitions: [15, 12, 10, 8, 6, 4, 2],
            weights: [35000, 30000, 25000, 20000, 18000, 15000, 12000],
            setGroup: sg
        )
        
        let dto = WorkoutSetDTO(from: dropSet)
        
        XCTAssertEqual(dto.dropSetRepetitions?.count, 7)
        XCTAssertEqual(dto.dropSetWeights?.count, 7)
    }
}

// MARK: - TemplateSetDTO Tests

final class TemplateSetDTOCodingTests: XCTestCase {
    
    private var database: Database!
    private var builder: TestDataBuilder!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        builder = TestDataBuilder(database: database)
    }
    
    override func tearDown() {
        database = nil
        builder = nil
        super.tearDown()
    }
    
    func testTemplateStandardSetDTO() {
        let template = database.newTemplate(name: "Test")
        let exercise = builder.createExercise(name: "Press", muscleGroup: .chest)
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        let set = database.newTemplateStandardSet(repetitions: 10, weight: 80000, setGroup: sg)
        
        let dto = TemplateSetDTO(from: set)
        
        XCTAssertEqual(dto.type, .standard)
        XCTAssertEqual(dto.repetitions, 10)
        XCTAssertEqual(dto.weight, 80000)
    }
    
    func testTemplateSuperSetDTO() {
        let template = database.newTemplate(name: "Test")
        let exA = builder.createExercise(name: "Press", muscleGroup: .chest)
        let exB = builder.createExercise(name: "Row", muscleGroup: .back)
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exA, template: template)
        sg.secondaryExercise = exB
        let set = database.newTemplateSuperSet(
            repetitionsFirstExercise: 8, repetitionsSecondExercise: 12,
            weightFirstExercise: 50000, weightSecondExercise: 40000,
            setGroup: sg
        )
        
        let dto = TemplateSetDTO(from: set)
        
        XCTAssertEqual(dto.type, .superSet)
        XCTAssertEqual(dto.repetitionsFirstExercise, 8)
        XCTAssertEqual(dto.repetitionsSecondExercise, 12)
        XCTAssertEqual(dto.weightFirstExercise, 50000)
        XCTAssertEqual(dto.weightSecondExercise, 40000)
    }
    
    func testTemplateDropSetDTO() {
        let template = database.newTemplate(name: "Test")
        let exercise = builder.createExercise(name: "Curl", muscleGroup: .biceps)
        let sg = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        let set = database.newTemplateDropSet(
            repetitions: [12, 10, 8],
            weights: [25000, 20000, 15000],
            templateSetGroup: sg
        )
        
        let dto = TemplateSetDTO(from: set)
        
        XCTAssertEqual(dto.type, .dropSet)
        XCTAssertEqual(dto.dropSetRepetitions, [12, 10, 8])
        XCTAssertEqual(dto.dropSetWeights, [25000, 20000, 15000])
    }
    
    func testTemplateSetDTOBackwardCompatibility() throws {
        // Test that a JSON with only repetitions/weight (no type) decodes as standard
        let json = """
        {"repetitions": 10, "weight": 50000}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TemplateSetDTO.self, from: data)
        
        XCTAssertNil(decoded.type, "Without explicit type, it should be nil")
        XCTAssertEqual(decoded.repetitions, 10)
        XCTAssertEqual(decoded.weight, 50000)
    }
}
