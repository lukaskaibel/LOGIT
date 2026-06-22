//
//  DemoWorkoutSeeder.swift
//  LOGIT
//
//  DEBUG-only helper for manual testing in the simulator. Launching the app
//  once with `-SEED_DEMO_WORKOUTS` fills the regular persistent store with a
//  handful of realistic workouts (push / pull / legs / upper body, including
//  a superset, drop sets and bodyweight sets) and skips onboarding. The data
//  survives normal launches afterwards; seeding is skipped when the demo
//  workouts already exist.
//

#if DEBUG
import Foundation

enum DemoWorkoutSeeder {
    private static let workoutNames = ["Push Day", "Pull Day", "Leg Day", "Upper Body"]

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-SEED_DEMO_WORKOUTS")
    }

    /// Called early in `LOGITApp.init` (like `ScreenshotFixtures`) so the
    /// onboarding flag is in place before any `@AppStorage` reads happen.
    static func prepareUserDefaultsIfNeeded() {
        guard isRequested else { return }
        UserDefaults.standard.set(true, forKey: "setupDone")
    }

    /// Call after the default exercise library has been loaded so the demo
    /// workouts reference the built-in exercises instead of creating copies.
    static func seedIfRequested(database: Database) {
        guard isRequested else { return }
        let existingWorkouts = (database.fetch(Workout.self) as? [Workout]) ?? []
        guard !existingWorkouts.contains(where: { workoutNames.contains($0.name ?? "") }) else {
            NSLog("DemoWorkoutSeeder: demo workouts already present, skipping")
            return
        }

        let benchPress = exercise("_default.exercise.barbellBenchPress", "Bench Press", .chest, database)
        let inclinePress = exercise("_default.exercise.inclinedDumbbellBenchPress", "Incline Dumbbell Press", .chest, database)
        let shoulderPress = exercise("_default.exercise.shoulderPress", "Shoulder Press", .shoulders, database)
        let lateralRaises = exercise("_default.exercise.lateralRaises", "Lateral Raises", .shoulders, database)
        let tricepPushdowns = exercise("_default.exercise.tricepPushdowns", "Tricep Pushdowns", .triceps, database)
        let deadlift = exercise("_default.exercise.deadlift", "Deadlift", .back, database)
        let pullups = exercise("_default.exercise.pullups", "Pull Ups", .back, database)
        let latPulldowns = exercise("_default.exercise.latPulldowns", "Lat Pulldowns", .back, database)
        let barbellRows = exercise("_default.exercise.barbellRows", "Barbell Rows", .back, database)
        let barbellCurls = exercise("_default.exercise.barbellCurls", "Barbell Curls", .biceps, database)
        let squats = exercise("_default.exercise.squats", "Squats", .legs, database)
        let legPress = exercise("_default.exercise.legPress", "Leg Press", .legs, database)
        let lunges = exercise("_default.exercise.dumbbellLunges", "Dumbbell Lunges", .legs, database)
        let legExtension = exercise("_default.exercise.legExtension", "Leg Extension", .legs, database)
        let cableCrunches = exercise("_default.exercise.cableCrunches", "Cable Crunches", .abdominals, database)

        // MARK: Push Day (2 days ago)

        let pushDay = database.newWorkout(name: "Push Day", date: startDate(daysAgo: 2, hour: 17, minute: 30))
        pushDay.endDate = pushDay.date?.addingTimeInterval(68 * 60)

        let benchGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: benchPress, workout: pushDay)
        database.newStandardSet(repetitions: 10, weight: 60000, setGroup: benchGroup)
        database.newStandardSet(repetitions: 8, weight: 80000, setGroup: benchGroup)
        database.newStandardSet(repetitions: 6, weight: 85000, setGroup: benchGroup)
        database.newStandardSet(repetitions: 6, weight: 85000, setGroup: benchGroup)

        let inclineGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: inclinePress, workout: pushDay)
        database.newStandardSet(repetitions: 10, weight: 30000, setGroup: inclineGroup)
        database.newStandardSet(repetitions: 10, weight: 30000, setGroup: inclineGroup)
        database.newStandardSet(repetitions: 8, weight: 34000, setGroup: inclineGroup)

        let shoulderGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: shoulderPress, workout: pushDay)
        database.newStandardSet(repetitions: 10, weight: 40000, setGroup: shoulderGroup)
        database.newStandardSet(repetitions: 8, weight: 45000, setGroup: shoulderGroup)
        database.newStandardSet(repetitions: 8, weight: 45000, setGroup: shoulderGroup)

        let pushFinisherGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: lateralRaises, workout: pushDay)
        pushFinisherGroup.secondaryExercise = tricepPushdowns
        for _ in 0 ..< 3 {
            database.newSuperSet(
                repetitionsFirstExercise: 12,
                repetitionsSecondExercise: 12,
                weightFirstExercise: 10000,
                weightSecondExercise: 25000,
                setGroup: pushFinisherGroup
            )
        }

        // MARK: Pull Day (4 days ago)

        let pullDay = database.newWorkout(name: "Pull Day", date: startDate(daysAgo: 4, hour: 18, minute: 0))
        pullDay.endDate = pullDay.date?.addingTimeInterval(72 * 60)

        let deadliftGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: deadlift, workout: pullDay)
        database.newStandardSet(repetitions: 5, weight: 120_000, setGroup: deadliftGroup)
        database.newStandardSet(repetitions: 5, weight: 140_000, setGroup: deadliftGroup)
        database.newStandardSet(repetitions: 3, weight: 150_000, setGroup: deadliftGroup)
        database.newStandardSet(repetitions: 3, weight: 150_000, setGroup: deadliftGroup)

        let pullupGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: pullups, workout: pullDay)
        database.newStandardSet(repetitions: 10, setGroup: pullupGroup)
        database.newStandardSet(repetitions: 8, setGroup: pullupGroup)
        database.newStandardSet(repetitions: 6, setGroup: pullupGroup)

        let pulldownGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: latPulldowns, workout: pullDay)
        database.newDropSet(repetitions: [10, 8], weights: [60000, 45000], setGroup: pulldownGroup)
        database.newDropSet(repetitions: [10, 8], weights: [60000, 45000], setGroup: pulldownGroup)
        database.newDropSet(repetitions: [8, 6], weights: [60000, 45000], setGroup: pulldownGroup)

        let rowGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: barbellRows, workout: pullDay)
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: rowGroup)
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: rowGroup)
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: rowGroup)

        let curlGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: barbellCurls, workout: pullDay)
        database.newStandardSet(repetitions: 12, weight: 30000, setGroup: curlGroup)
        database.newStandardSet(repetitions: 10, weight: 32500, setGroup: curlGroup)
        database.newStandardSet(repetitions: 8, weight: 35000, setGroup: curlGroup)

        // MARK: Leg Day (6 days ago)

        let legDay = database.newWorkout(name: "Leg Day", date: startDate(daysAgo: 6, hour: 17, minute: 45))
        legDay.endDate = legDay.date?.addingTimeInterval(75 * 60)

        let squatGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: squats, workout: legDay)
        database.newStandardSet(repetitions: 8, weight: 100_000, setGroup: squatGroup)
        database.newStandardSet(repetitions: 6, weight: 110_000, setGroup: squatGroup)
        database.newStandardSet(repetitions: 5, weight: 120_000, setGroup: squatGroup)
        database.newStandardSet(repetitions: 5, weight: 120_000, setGroup: squatGroup)

        let legPressGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: legPress, workout: legDay)
        database.newStandardSet(repetitions: 10, weight: 180_000, setGroup: legPressGroup)
        database.newStandardSet(repetitions: 10, weight: 200_000, setGroup: legPressGroup)
        database.newStandardSet(repetitions: 8, weight: 220_000, setGroup: legPressGroup)

        let lungeGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: lunges, workout: legDay)
        database.newStandardSet(repetitions: 12, weight: 40000, setGroup: lungeGroup)
        database.newStandardSet(repetitions: 12, weight: 40000, setGroup: lungeGroup)
        database.newStandardSet(repetitions: 12, weight: 40000, setGroup: lungeGroup)

        let legExtensionGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: legExtension, workout: legDay)
        database.newStandardSet(repetitions: 15, weight: 50000, setGroup: legExtensionGroup)
        database.newStandardSet(repetitions: 12, weight: 55000, setGroup: legExtensionGroup)
        database.newStandardSet(repetitions: 12, weight: 55000, setGroup: legExtensionGroup)

        let crunchGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: cableCrunches, workout: legDay)
        database.newStandardSet(repetitions: 15, weight: 20000, setGroup: crunchGroup)
        database.newStandardSet(repetitions: 15, weight: 20000, setGroup: crunchGroup)
        database.newStandardSet(repetitions: 15, weight: 20000, setGroup: crunchGroup)

        // MARK: Upper Body (9 days ago)

        let upperBody = database.newWorkout(name: "Upper Body", date: startDate(daysAgo: 9, hour: 18, minute: 15))
        upperBody.endDate = upperBody.date?.addingTimeInterval(60 * 60)

        let upperBenchGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: benchPress, workout: upperBody)
        database.newStandardSet(repetitions: 8, weight: 75000, setGroup: upperBenchGroup)
        database.newStandardSet(repetitions: 8, weight: 75000, setGroup: upperBenchGroup)
        database.newStandardSet(repetitions: 8, weight: 75000, setGroup: upperBenchGroup)
        database.newStandardSet(repetitions: 8, weight: 75000, setGroup: upperBenchGroup)

        let upperRowGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: barbellRows, workout: upperBody)
        database.newStandardSet(repetitions: 8, weight: 65000, setGroup: upperRowGroup)
        database.newStandardSet(repetitions: 8, weight: 65000, setGroup: upperRowGroup)
        database.newStandardSet(repetitions: 8, weight: 65000, setGroup: upperRowGroup)

        let upperShoulderGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: shoulderPress, workout: upperBody)
        database.newStandardSet(repetitions: 8, weight: 40000, setGroup: upperShoulderGroup)
        database.newStandardSet(repetitions: 8, weight: 40000, setGroup: upperShoulderGroup)
        database.newStandardSet(repetitions: 8, weight: 40000, setGroup: upperShoulderGroup)

        let upperArmsGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: barbellCurls, workout: upperBody)
        upperArmsGroup.secondaryExercise = tricepPushdowns
        for _ in 0 ..< 3 {
            database.newSuperSet(
                repetitionsFirstExercise: 10,
                repetitionsSecondExercise: 10,
                weightFirstExercise: 30000,
                weightSecondExercise: 25000,
                setGroup: upperArmsGroup
            )
        }

        database.save()
        NSLog("DemoWorkoutSeeder: seeded %d demo workouts", workoutNames.count)
    }

    /// The built-in exercise matching the default-library name key, or a new
    /// stand-alone exercise when the library isn't loaded (or the key changed).
    private static func exercise(
        _ nameKey: String,
        _ fallbackName: String,
        _ muscleGroup: MuscleGroup,
        _ database: Database
    ) -> Exercise {
        if let existing = (database.fetch(Exercise.self) as? [Exercise])?.first(where: { $0.name == nameKey }) {
            return existing
        }
        return database.newExercise(name: fallbackName, muscleGroup: muscleGroup)
    }

    private static func startDate(daysAgo: Int, hour: Int, minute: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
#endif
