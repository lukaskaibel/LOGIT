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

    /// Parsed once at process start from `-SCENARIO <name>`. Always `nil` in
    /// Release builds, so scenario branches are unreachable outside DEBUG.
    static let active: TestScenario? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "-SCENARIO"),
              args.indices.contains(flagIndex + 1)
        else { return nil }
        guard let scenario = TestScenario(rawValue: args[flagIndex + 1]) else {
            NSLog("TestScenario: unknown scenario '%@' — expected empty|one|many", args[flagIndex + 1])
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
        overrides["workoutPerWeekTarget"] = self == .empty ? -1 : 4
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
        case .empty, .one:
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
