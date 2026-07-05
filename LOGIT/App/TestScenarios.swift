//
//  TestScenarios.swift
//  LOGIT
//
//  Launch scenarios for testing the app in its critical data states. Launching
//  with `-SCENARIO empty|one|many` boots a fresh in-memory store seeded for
//  that state, plus session-only UserDefaults overrides — the simulator's real
//  store and defaults are never touched, and every launch is identical.
//
//      empty   brand-new user: default content only, no workouts, no goal
//      one     exactly one completed workout: single-data-point charts,
//              trends without a prior period, singular strings
//      many    long-time user: the curated preview dataset (same as the
//              marketing screenshots) minus the in-progress workout
//      stress  power user: two years of dense history (hundreds of workouts,
//              thousands of sets) plus an in-progress workout — for
//              performance work; combine with -UITEST_SHOW_RECORDER to land
//              in the recorder mid-session
//
//  Combine with `-UITEST_FORCE_FREE` to see the free tier (DEBUG simulator
//  builds force-unlock Pro otherwise). Scenarios are ignored in Release
//  builds. Shared schemes "LOGIT Empty / One Workout / Many Workouts" have
//  the arguments preconfigured.
//

import Foundation

enum TestScenario: String {
    case empty
    case one
    case many
    case stress

    /// Parsed once at process start from `-SCENARIO <name>`. Always `nil` in
    /// Release builds, so scenario branches are unreachable outside DEBUG.
    static let active: TestScenario? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "-SCENARIO"),
              args.indices.contains(flagIndex + 1)
        else { return nil }
        guard let scenario = TestScenario(rawValue: args[flagIndex + 1]) else {
            NSLog("TestScenario: unknown scenario '%@' — expected empty|one|many|stress", args[flagIndex + 1])
            return nil
        }
        return scenario
        #else
        return nil
        #endif
    }()

    // MARK: - UserDefaults

    /// Injects session-only defaults into the argument domain (highest
    /// precedence, never persisted): reads see these values for the whole
    /// session while the developer's real defaults stay untouched. Flip side:
    /// writes to these keys during a scenario session aren't readable back,
    /// so e.g. the weight-unit toggle appears inert while a scenario runs.
    func prepareUserDefaults() {
        var overrides = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)

        // Skip onboarding, keep units deterministic across sim locales.
        overrides["setupDone"] = true
        overrides["weightUnit"] = WeightUnit.kg.rawValue
        // `empty` shows the no-goal state, the other scenarios a realistic goal.
        overrides["workoutPerWeekTarget"] = self == .empty ? -1 : self == .stress ? 2 : 4
        // Per-user layout state stored as Data (object URIs / JSON) must not
        // leak in from the real store — the URIs wouldn't resolve against the
        // in-memory store anyway. A string value makes the Data reads fail so
        // the views fall back to their defaults.
        overrides["pinnedExercises"] = "cleared"
        overrides["pinnedMeasurements"] = "cleared"
        overrides["muscleTargetSplit"] = "cleared"
        // Force the default exercises/templates to import into the fresh
        // in-memory store even though the persistent domain records them as
        // already loaded into the real store (templates additionally remember
        // every id they ever seeded).
        overrides["lastLoadedDefaultExercisesVersion"] = 0
        overrides["lastLoadedDefaultExercisesLocale"] = ""
        overrides["lastLoadedDefaultTemplatesVersion"] = 0
        overrides["seededDefaultTemplateIds"] = [String]()
        // No system permission / rating prompts mid-scenario.
        overrides["hasRequestedNotificationPermission"] = true
        overrides["wasPromptedToRateApp"] = true

        UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
    }

    // MARK: - Seeding

    /// Called from `LOGITApp.init` right after the in-memory database is
    /// created, before any views or services read from it.
    func seedAtLaunch(into database: Database) {
        switch self {
        case .empty, .one, .stress:
            break
        case .many:
            // The curated dataset the marketing screenshots use, but without
            // the in-progress workout so the recorder mini bar doesn't cover
            // the bottom of every screen. Use `-UITEST_FIXTURES` when the
            // mid-workout state itself is under test.
            database.setupPreviewDatabase(includeCurrentWorkout: false)
        }
    }

    /// Called from `LOGITApp.init` once the `MeasurementEntryController`
    /// exists — it owns the preview measurement entries.
    func seedMeasurements(using controller: MeasurementEntryController) {
        guard self == .many else { return }
        controller.setupPreviewMeasurementEntries()
    }

    /// Called from `LOGITApp.init` after the default exercise library import,
    /// so the single workout references built-in exercises instead of
    /// creating duplicate-looking copies (same approach as DemoWorkoutSeeder).
    func seedAfterDefaultContentLoaded(database: Database) {
        if self == .stress {
            seedStressData(database: database)
            return
        }
        guard self == .one else { return }

        let bench = exercise("_default.exercise.barbellBenchPress", "Bench Press", .chest, database)
        let squats = exercise("_default.exercise.squats", "Squats", .legs, database)
        let latPulldowns = exercise("_default.exercise.latPulldowns", "Lat Pulldowns", .back, database)

        // Earlier today, so the workout counts toward the current week (and
        // its stats stay "fresh period" single data points) on every weekday.
        let start = Date.now.addingTimeInterval(-2 * 3600)
        let workout = database.newWorkout(name: "Full Body", date: start)
        workout.endDate = start.addingTimeInterval(52 * 60)

        let benchGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: bench, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 60000, setGroup: benchGroup)
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: benchGroup)
        database.newStandardSet(repetitions: 8, weight: 70000, setGroup: benchGroup)

        let squatGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: squats, workout: workout)
        database.newStandardSet(repetitions: 10, weight: 80000, setGroup: squatGroup)
        database.newStandardSet(repetitions: 8, weight: 90000, setGroup: squatGroup)
        database.newStandardSet(repetitions: 8, weight: 90000, setGroup: squatGroup)

        let latGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: latPulldowns, workout: workout)
        database.newStandardSet(repetitions: 12, weight: 50000, setGroup: latGroup)
        database.newStandardSet(repetitions: 10, weight: 55000, setGroup: latGroup)
        database.newStandardSet(repetitions: 10, weight: 55000, setGroup: latGroup)

        database.save()
        NSLog("TestScenario: seeded single-workout scenario")
    }

    /// Two years of dense, deterministic history — two sessions per week
    /// alternating push/pull, four exercises with four sets each — plus an
    /// in-progress push workout (`isCurrentWorkout`). This is the data shape
    /// where per-keystroke work in the recorder becomes visible: every main
    /// exercise accumulates 400+ historical sets, so anything that scans an
    /// exercise's history per UI update gets amplified to realistic cost.
    private func seedStressData(database: Database) {
        let bench = exercise("_default.exercise.barbellBenchPress", "Bench Press", .chest, database)
        let overheadPress = exercise("_default.exercise.overheadPress", "Overhead Press", .shoulders, database)
        let inclineBench = exercise("_default.exercise.inclineBenchPress", "Incline Bench Press", .chest, database)
        let tricepsExtensions = exercise("_default.exercise.tricepsExtensions", "Triceps Extensions", .triceps, database)
        let deadlift = exercise("_default.exercise.deadlift", "Deadlift", .back, database)
        let rows = exercise("_default.exercise.barbellRows", "Barbell Rows", .back, database)
        let latPulldowns = exercise("_default.exercise.latPulldowns", "Lat Pulldowns", .back, database)
        let bicepsCurls = exercise("_default.exercise.bicepsCurls", "Biceps Curls", .biceps, database)

        let pushExercises = [bench, overheadPress, inclineBench, tricepsExtensions]
        let pullExercises = [deadlift, rows, latPulldowns, bicepsCurls]
        let baseWeights = [60000, 40000, 45000, 25000, 120000, 70000, 55000, 30000]

        let calendar = Calendar.current
        let sessionCount = 208 // 2 years, 2 sessions/week
        for session in 0 ..< sessionCount {
            let daysBack = (sessionCount - session) * 7 / 2 + 1
            let date = calendar.date(byAdding: .day, value: -daysBack, to: .now)!
            let isPush = session % 2 == 0
            let workout = database.newWorkout(name: isPush ? "Push Day" : "Pull Day", date: date)
            workout.endDate = date.addingTimeInterval(70 * 60)
            let exercises = isPush ? pushExercises : pullExercises
            for (slot, exercise) in exercises.enumerated() {
                let weightIndex = (isPush ? 0 : 4) + slot
                // Slow linear progression with a deterministic wobble so
                // trends, records, and current bests all have real signal.
                let progress = session / 8 * 2500
                let wobble = (session % 3) * 1250 - 1250
                let weight = baseWeights[weightIndex] + progress + wobble
                let group = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: exercise,
                    workout: workout
                )
                for setIndex in 0 ..< 4 {
                    database.newStandardSet(
                        repetitions: 12 - setIndex - (session % 3),
                        weight: weight,
                        setGroup: group
                    )
                }
            }
        }

        // The in-progress workout the recorder picks up: push day, first
        // half of the sets already entered, the rest waiting for input.
        let start = Date.now.addingTimeInterval(-23 * 60)
        let current = database.newWorkout(name: "Push Day", date: start)
        current.isCurrentWorkout = true
        for (slot, exercise) in pushExercises.enumerated() {
            let group = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: exercise,
                workout: current
            )
            let weight = baseWeights[slot] + sessionCount / 8 * 2500
            for setIndex in 0 ..< 4 {
                let isEntered = slot < 2 || (slot == 2 && setIndex < 2)
                database.newStandardSet(
                    repetitions: isEntered ? 12 - setIndex : 0,
                    weight: isEntered ? weight : 0,
                    setGroup: group
                )
            }
        }

        database.save()
        NSLog("TestScenario: seeded stress scenario (%d workouts)", sessionCount + 1)
    }

    /// The built-in exercise matching the default-library name key, or a new
    /// stand-alone exercise when the library isn't loaded (or the key changed).
    private func exercise(
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
}
