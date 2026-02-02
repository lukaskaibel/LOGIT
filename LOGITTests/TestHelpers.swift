//
//  TestHelpers.swift
//  LOGITTests
//
//  Test utilities and helpers for LOGIT unit tests
//

import XCTest
import CoreData

@testable import LOGIT

// MARK: - Test Data Builder

/// Factory class for creating test entities with sensible defaults
final class TestDataBuilder {
    let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    // MARK: - Exercise Creation
    
    @discardableResult
    func createExercise(
        name: String = "Test Exercise",
        muscleGroup: MuscleGroup = .chest
    ) -> Exercise {
        let exercise = Exercise(context: database.context)
        exercise.id = UUID()
        exercise.name = name
        exercise.muscleGroup = muscleGroup
        return exercise
    }
    
    // MARK: - Workout Creation
    
    @discardableResult
    func createWorkout(
        name: String = "Test Workout",
        date: Date = Date(),
        setGroupCount: Int = 0
    ) -> Workout {
        let workout = database.newWorkout(name: name, date: date)
        for _ in 0..<setGroupCount {
            database.newWorkoutSetGroup(workout: workout)
        }
        return workout
    }
    
    /// Creates a complete workout with exercises and sets for testing
    @discardableResult
    func createCompleteWorkout(
        name: String = "Complete Test Workout",
        date: Date = Date(),
        exerciseCount: Int = 3,
        setsPerExercise: Int = 3
    ) -> Workout {
        let workout = database.newWorkout(name: name, date: date)
        
        let muscleGroups: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .legs, .abdominals, .cardio]
        
        for i in 0..<exerciseCount {
            let exercise = createExercise(
                name: "Exercise \(i + 1)",
                muscleGroup: muscleGroups[i % muscleGroups.count]
            )
            let setGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: exercise,
                workout: workout
            )
            
            for j in 0..<setsPerExercise {
                database.newStandardSet(
                    repetitions: 10 + j,
                    weight: (50 + j * 5) * 1000, // Store as grams
                    setGroup: setGroup
                )
            }
        }
        
        return workout
    }
    
    // MARK: - Set Creation
    
    @discardableResult
    func createStandardSet(
        repetitions: Int = 10,
        weight: Int = 50000,
        exercise: Exercise? = nil,
        workout: Workout? = nil
    ) -> StandardSet {
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        return database.newStandardSet(
            repetitions: repetitions,
            weight: weight,
            setGroup: setGroup
        )
    }
    
    @discardableResult
    func createDropSet(
        drops: [(reps: Int, weight: Int)] = [(10, 50000), (8, 40000), (6, 30000)],
        exercise: Exercise? = nil,
        workout: Workout? = nil
    ) -> DropSet {
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: exercise,
            workout: workout
        )
        return database.newDropSet(
            repetitions: drops.map { $0.reps },
            weights: drops.map { $0.weight },
            setGroup: setGroup
        )
    }
    
    @discardableResult
    func createSuperSet(
        repsFirst: Int = 10,
        repsSecond: Int = 12,
        weightFirst: Int = 50000,
        weightSecond: Int = 40000,
        firstExercise: Exercise? = nil,
        secondExercise: Exercise? = nil,
        workout: Workout? = nil
    ) -> SuperSet {
        let setGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: firstExercise,
            workout: workout
        )
        setGroup.secondaryExercise = secondExercise
        
        return database.newSuperSet(
            repetitionsFirstExercise: repsFirst,
            repetitionsSecondExercise: repsSecond,
            weightFirstExercise: weightFirst,
            weightSecondExercise: weightSecond,
            setGroup: setGroup
        )
    }
    
    // MARK: - Measurement Creation
    
    @discardableResult
    func createMeasurementEntry(
        type: MeasurementEntryType = .bodyweight,
        value: Int = 75,
        date: Date = Date()
    ) -> MeasurementEntry {
        let entry = MeasurementEntry(context: database.context)
        entry.id = UUID()
        entry.type = type
        entry.value = value
        entry.date = date
        return entry
    }
}

// MARK: - XCTestCase Extension

extension XCTestCase {
    /// Creates a fresh preview database for testing
    func createTestDatabase() -> Database {
        Database(isPreview: true)
    }
    
    /// Creates a test data builder with a fresh database
    func createTestBuilder() -> (database: Database, builder: TestDataBuilder) {
        let database = Database(isPreview: true)
        let builder = TestDataBuilder(database: database)
        return (database, builder)
    }
}

// MARK: - UserDefaults Test Helper

/// Helper for managing UserDefaults in tests
final class UserDefaultsTestHelper {
    private var savedValues: [String: Any?] = [:]
    
    /// Saves current UserDefaults values for keys that will be modified
    func saveValue(forKey key: String) {
        savedValues[key] = UserDefaults.standard.object(forKey: key)
    }
    
    /// Sets a test value in UserDefaults
    func setTestValue(_ value: Any?, forKey key: String) {
        saveValue(forKey: key)
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    /// Restores all saved UserDefaults values
    func restoreAll() {
        for (key, optionalValue) in savedValues {
            if let value = optionalValue {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedValues.removeAll()
    }
}

// MARK: - Date Test Helpers

extension Date {
    /// Creates a date relative to now for testing
    static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }
    
    static func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date())!
    }
    
    static func weeksAgo(_ weeks: Int) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date())!
    }
}
