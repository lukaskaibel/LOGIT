//
//  Database+Preview.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 17.04.22.
//

import Foundation

extension Database {
    /// Seeds the curated preview dataset. `includeCurrentWorkout: false` skips the
    /// in-progress workout (and with it the recorder mini bar) — used by the `many`
    /// launch scenario, while previews and fastlane fixtures keep the default.
    func setupPreviewDatabase(includeCurrentWorkout: Bool = true) {
        let database = self

        (database.fetch(Workout.self) as! [Workout]).forEach { database.delete($0) }
        (database.fetch(Exercise.self) as! [Workout]).forEach { database.delete($0) }

        // MARK: Exercises

        let benchpress = database.newExercise(name: NSLocalizedString("previewBenchPress", comment: ""), muscleGroup: .chest)
        let inclinedBenchpress = database.newExercise(
            name: NSLocalizedString("previewInclineBenchPress", comment: ""),
            muscleGroup: .chest
        )
        let overheadPress = database.newExercise(name: NSLocalizedString("previewOverheadPress", comment: ""), muscleGroup: .shoulders)
        let lateralRaises = database.newExercise(name: NSLocalizedString("previewLateralRaises", comment: ""), muscleGroup: .shoulders)
        let tricepsExtensions = database.newExercise(
            name: NSLocalizedString("previewTricepsExtensions", comment: ""),
            muscleGroup: .triceps
        )
        let dips = database.newExercise(name: NSLocalizedString("previewDips", comment: ""), muscleGroup: .chest)
        let squat = database.newExercise(name: NSLocalizedString("previewSquat", comment: ""), muscleGroup: .legs)
        let lunges = database.newExercise(name: NSLocalizedString("previewLunges", comment: ""), muscleGroup: .legs)
        let legExtensions = database.newExercise(name: NSLocalizedString("previewLegExtensions", comment: ""), muscleGroup: .legs)
        let deadlift = database.newExercise(name: NSLocalizedString("previewDeadlift", comment: ""), muscleGroup: .back)
        let standingRows = database.newExercise(name: NSLocalizedString("previewStandingRows", comment: ""), muscleGroup: .back)
        let bicepsCurls = database.newExercise(name: NSLocalizedString("previewBicepsCurls", comment: ""), muscleGroup: .biceps)
        let latPulldown = database.newExercise(name: NSLocalizedString("previewLatPulldown", comment: ""), muscleGroup: .back)
        let crunches = database.newExercise(name: NSLocalizedString("previewCrunches", comment: ""), muscleGroup: .abdominals)

        // MARK: Workout history
        //
        // ~5 months of consistent 3x/week training (Push / Pull / Leg) so the
        // History reads like a long-time user and the weekly-goal streak spans
        // months, not weeks. Every workout lands cleanly inside its own calendar
        // week (aligned to `startOfWeek`), so each week clears the weekly target
        // and the streak stays unbroken. Every lift moves week over week — the
        // compounds climbing hard, the accessories drifting either way (see
        // `weights(week:)`) — which drives the exercise charts, the Strength
        // ranking, the Progress highlights and the pinned exercise tiles.

        let calendar = Calendar.current
        let numberOfWeeks = 20
        let thisWeekStart = Date.now.startOfWeek

        // A lift's working weight for a given week (grams): `base` in the oldest
        // week moving to `base + gain` in the newest, rounded to a tidy step so the
        // numbers read as hand-entered. A negative `gain` is a lift going backwards.
        //
        // `step` is 2.5 kg for barbell work and 1 kg for the lighter accessories,
        // where a 2.5 kg grid is too coarse to show a small drift at all.
        func progressedWeight(week w: Int, base: Int, gain: Int, step: Int = 2500) -> Int {
            let t = Double(numberOfWeeks - 1 - w) / Double(max(numberOfWeeks - 1, 1))
            return Int(((Double(base) + t * Double(gain)) / Double(step)).rounded()) * step
        }

        // Every lift gets its own trajectory instead of three climbing and the rest
        // pinned flat. The Strength screen ranks exercises from least to most
        // improved, so a fixture where only the compounds move renders three bars
        // against a row of flat stubs — the drifts, and especially the lifts going
        // backwards, are what make that ranking read as a real training history.
        //
        // Overall e1RM still trends up: the compounds climb 28-40 kg and dominate
        // the average, while the accessories that fade give up 4-7 kg.
        func weights(week w: Int) -> (
            bench: Int, incline: Int, ohp: Int, lateralRaise: Int, tricepsExt: Int,
            squat: Int, lunge: Int, legExt: Int,
            deadlift: Int, row: Int, latPulldown: Int, curl: Int
        ) {
            (
                bench: progressedWeight(week: w, base: 72000, gain: 28000),        // 72 -> 100 kg
                incline: progressedWeight(week: w, base: 45000, gain: 12500),      // 45 -> 57.5
                ohp: progressedWeight(week: w, base: 45000, gain: -7500),          // 45 -> 37.5, stalled out
                lateralRaise: progressedWeight(week: w, base: 20000, gain: -4000, step: 1000),  // 20 -> 16
                tricepsExt: progressedWeight(week: w, base: 22000, gain: 6000, step: 1000),     // 22 -> 28
                squat: progressedWeight(week: w, base: 80000, gain: 40000),        // 80 -> 120 kg
                lunge: progressedWeight(week: w, base: 55000, gain: -7000, step: 1000),         // 55 -> 48
                legExt: progressedWeight(week: w, base: 35000, gain: 10000, step: 1000),        // 35 -> 45
                deadlift: progressedWeight(week: w, base: 100_000, gain: 40000),   // 100 -> 140 kg
                row: progressedWeight(week: w, base: 45000, gain: 13000, step: 1000),           // 45 -> 58
                latPulldown: progressedWeight(week: w, base: 52000, gain: 18000, step: 1000),   // 52 -> 70
                curl: progressedWeight(week: w, base: 32000, gain: -4000, step: 1000)           // 32 -> 28
            )
        }

        // The date `offset` days into the calendar week `w` weeks before this one.
        func date(dayOffset offset: Int, weeksAgo w: Int) -> Date {
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -w, to: thisWeekStart) ?? thisWeekStart
            return calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
        }

        func seedPushDay(on day: Date, week w: Int, minutes: Int) {
            let kg = weights(week: w)
            let push = database.newWorkout(name: NSLocalizedString("previewPushDay", comment: ""), date: day)
            push.endDate = calendar.date(byAdding: .minute, value: minutes, to: day)
            let benchGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: benchpress, workout: push)
            for _ in 0 ..< 5 { database.newStandardSet(repetitions: 5, weight: kg.bench, setGroup: benchGroup) }
            let ohpGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: overheadPress, workout: push)
            for _ in 0 ..< 3 { database.newStandardSet(repetitions: 10, weight: kg.ohp, setGroup: ohpGroup) }
            let inclineGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: inclinedBenchpress, workout: push)
            for _ in 0 ..< 3 { database.newStandardSet(repetitions: 12, weight: kg.incline, setGroup: inclineGroup) }
            let dipsGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: dips, workout: push)
            for reps in [8, 8, 6] { database.newStandardSet(repetitions: reps, weight: 0, setGroup: dipsGroup) }
            let superGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: tricepsExtensions, workout: push)
            superGroup.secondaryExercise = lateralRaises
            for _ in 0 ..< 3 {
                database.newSuperSet(repetitionsFirstExercise: 12, repetitionsSecondExercise: 14, weightFirstExercise: kg.tricepsExt, weightSecondExercise: kg.lateralRaise, setGroup: superGroup)
            }
        }

        func seedPullDay(on day: Date, week w: Int, minutes: Int) {
            let kg = weights(week: w)
            let pull = database.newWorkout(name: NSLocalizedString("previewPullDay", comment: ""), date: day)
            pull.endDate = calendar.date(byAdding: .minute, value: minutes, to: day)
            let deadliftGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: deadlift, workout: pull)
            for _ in 0 ..< 4 { database.newStandardSet(repetitions: 5, weight: kg.deadlift, setGroup: deadliftGroup) }
            let latGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: latPulldown, workout: pull)
            for _ in 0 ..< 3 { database.newDropSet(repetitions: [5, 8], weights: [kg.latPulldown, kg.latPulldown * 3 / 4], setGroup: latGroup) }
            let rowGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: standingRows, workout: pull)
            for _ in 0 ..< 4 { database.newStandardSet(repetitions: 8, weight: kg.row, setGroup: rowGroup) }
            let curlGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: bicepsCurls, workout: pull)
            for _ in 0 ..< 3 { database.newStandardSet(repetitions: 12, weight: kg.curl, setGroup: curlGroup) }
        }

        func seedLegDay(on day: Date, week w: Int, minutes: Int) {
            let kg = weights(week: w)
            let leg = database.newWorkout(name: NSLocalizedString("previewLegDay", comment: ""), date: day)
            leg.endDate = calendar.date(byAdding: .minute, value: minutes, to: day)
            let squatGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: squat, workout: leg)
            for reps in [8, 8, 6, 6] { database.newStandardSet(repetitions: reps, weight: kg.squat, setGroup: squatGroup) }
            let lungesGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: lunges, workout: leg)
            for _ in 0 ..< 4 { database.newStandardSet(repetitions: 12, weight: kg.lunge, setGroup: lungesGroup) }
            let legExtGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: legExtensions, workout: leg)
            for reps in [[8, 5], [6, 4], [6, 4]] { database.newDropSet(repetitions: reps, weights: [kg.legExt, kg.legExt * 5 / 8], setGroup: legExtGroup) }
            let absGroup = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: crunches, workout: leg)
            for _ in 0 ..< 3 { database.newStandardSet(repetitions: 12, weight: 0, setGroup: absGroup) }
        }

        // Leg Sunday, Push Monday, Pull Wednesday — all inside one calendar week.
        // The current week additionally gets the Arm Day (Tuesday) seeded below,
        // so it out-volumes the prior full week and its weekly trends read
        // positive. `date(...) <= .now` guards against seeding into the future.
        let durations = [65, 58, 72, 55, 68, 61, 70]
        for w in 0 ..< numberOfWeeks {
            let push = date(dayOffset: 1, weeksAgo: w)
            let pull = date(dayOffset: 3, weeksAgo: w)
            let leg = date(dayOffset: 0, weeksAgo: w)
            if push <= .now { seedPushDay(on: push, week: w, minutes: durations[w % durations.count]) }
            if pull <= .now { seedPullDay(on: pull, week: w, minutes: durations[(w + 2) % durations.count]) }
            if leg <= .now { seedLegDay(on: leg, week: w, minutes: durations[(w + 4) % durations.count]) }
        }

        // MARK: Templates

        func addTemplateSet(exercise: Exercise, template: Template, reps: Int, weight: Int, extraSets: Int = 2) {
            let group = database.newTemplateSetGroup(
                createFirstSetAutomatically: false,
                exercise: exercise,
                template: template
            )
            for _ in 0 ... extraSets {
                database.newTemplateStandardSet(
                    repetitions: reps,
                    weight: weight,
                    setGroup: group
                )
            }
        }

        let pushTemplate = database.newTemplate(name: NSLocalizedString("previewPushDay", comment: ""))
        addTemplateSet(exercise: benchpress, template: pushTemplate, reps: 8, weight: 70000, extraSets: 3)
        addTemplateSet(exercise: inclinedBenchpress, template: pushTemplate, reps: 10, weight: 55000)
        addTemplateSet(exercise: overheadPress, template: pushTemplate, reps: 8, weight: 45000)
        // A superset finisher — templates render these as the containerless per-exercise pager
        // (see `TemplateSetGroupCell`), so the fixtures have to contain one.
        let pushFinisher = database.newTemplateSetGroup(
            createFirstSetAutomatically: false,
            exercise: tricepsExtensions,
            template: pushTemplate
        )
        pushFinisher.secondaryExercise = lateralRaises
        for _ in 0 ..< 3 {
            database.newTemplateSuperSet(
                repetitionsFirstExercise: 12,
                repetitionsSecondExercise: 15,
                weightFirstExercise: 25000,
                weightSecondExercise: 12000,
                setGroup: pushFinisher
            )
        }

        let pullTemplate = database.newTemplate(name: NSLocalizedString("previewPullDay", comment: ""))
        addTemplateSet(exercise: deadlift, template: pullTemplate, reps: 5, weight: 120000, extraSets: 3)
        addTemplateSet(exercise: latPulldown, template: pullTemplate, reps: 10, weight: 60000)
        addTemplateSet(exercise: standingRows, template: pullTemplate, reps: 10, weight: 55000)
        addTemplateSet(exercise: bicepsCurls, template: pullTemplate, reps: 12, weight: 30000)

        let legTemplate = database.newTemplate(name: NSLocalizedString("previewLegDay", comment: ""))
        addTemplateSet(exercise: squat, template: legTemplate, reps: 6, weight: 100000, extraSets: 3)
        addTemplateSet(exercise: lunges, template: legTemplate, reps: 10, weight: 40000)
        addTemplateSet(exercise: legExtensions, template: legTemplate, reps: 12, weight: 50000)
        addTemplateSet(exercise: crunches, template: legTemplate, reps: 20, weight: 0)

        // MARK: Current (in-progress) Workout
        //
        // The WorkoutRecorder fetches the single `isCurrentWorkout` workout on
        // init, so seeding one here puts the app in a realistic mid-session
        // state where the Start Workout button at the bottom of the tab bar
        // instead shows "Push Day · 00:23". This is what the fastlane test
        // for the Workout Recorder taps into to capture a populated set list.
        //
        // We mark the first few sets of each exercise as "entered" (non-zero
        // reps + weight) so the screenshot shows completed work in the log,
        // and leave later sets empty so the "what's next" state is obvious.
        if includeCurrentWorkout {
            let inProgressStart = Calendar.current.date(byAdding: .minute, value: -23, to: .now)!
            let currentPushDay = database.newWorkout(name: NSLocalizedString("previewPushDay", comment: ""), date: inProgressStart)
            currentPushDay.isCurrentWorkout = true

            // Ordering matters for the screenshot: the recorder scrolls its set
            // list to the bottom on appear, so we put the exercise with the most
            // filled-in sets (Benchpress) LAST so it's fully visible when the
            // capture test fires.
            let currentOhpGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: overheadPress,
                workout: currentPushDay
            )
            database.newStandardSet(repetitions: 8, weight: 45000, setGroup: currentOhpGroup)
            database.newStandardSet(repetitions: 8, weight: 45000, setGroup: currentOhpGroup)
            database.newStandardSet(repetitions: 0, weight: 0, setGroup: currentOhpGroup)

            let currentInclineGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: inclinedBenchpress,
                workout: currentPushDay
            )
            database.newStandardSet(repetitions: 10, weight: 55000, setGroup: currentInclineGroup)
            database.newStandardSet(repetitions: 10, weight: 55000, setGroup: currentInclineGroup)
            database.newStandardSet(repetitions: 9, weight: 55000, setGroup: currentInclineGroup)

            let currentBenchGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: benchpress,
                workout: currentPushDay
            )
            database.newStandardSet(repetitions: 8, weight: 70000, setGroup: currentBenchGroup)
            database.newStandardSet(repetitions: 8, weight: 70000, setGroup: currentBenchGroup)
            database.newStandardSet(repetitions: 7, weight: 70000, setGroup: currentBenchGroup)
            database.newStandardSet(repetitions: 0, weight: 0, setGroup: currentBenchGroup)
        }

        // MARK: Completed NSLocalizedString("previewArmDay", comment: "") workout with superset + drop set
        //
        // Dedicated fixture for the marketing screenshot that shows a super
        // set and a drop set one after another inside the same completed
        // workout. Uses NSLocalizedString("previewArmDay", comment: "") as the name so the UI test can find it
        // unambiguously (other seeded workouts are named Push/Pull/Leg Day).
        let armDayDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let armDay = database.newWorkout(name: NSLocalizedString("previewArmDay", comment: ""), date: armDayDate)
        armDay.endDate = Calendar.current.date(byAdding: .minute, value: 42, to: armDayDate)

        let armsSuperSetGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: bicepsCurls,
            workout: armDay
        )
        armsSuperSetGroup.secondaryExercise = tricepsExtensions
        database.newSuperSet(
            repetitionsFirstExercise: 12,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 18000,
            weightSecondExercise: 22000,
            setGroup: armsSuperSetGroup
        )
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 12,
            weightFirstExercise: 18000,
            weightSecondExercise: 22000,
            setGroup: armsSuperSetGroup
        )
        database.newSuperSet(
            repetitionsFirstExercise: 10,
            repetitionsSecondExercise: 10,
            weightFirstExercise: 18000,
            weightSecondExercise: 22000,
            setGroup: armsSuperSetGroup
        )

        let shoulderDropGroup = database.newWorkoutSetGroup(
            createFirstSetAutomatically: false,
            exercise: lateralRaises,
            workout: armDay
        )
        database.newDropSet(
            repetitions: [12, 10, 8],
            weights: [14000, 10000, 6000],
            setGroup: shoulderDropGroup
        )
        database.newDropSet(
            repetitions: [12, 8, 6],
            weights: [14000, 10000, 6000],
            setGroup: shoulderDropGroup
        )
        database.newDropSet(
            repetitions: [10, 8, 6],
            weights: [14000, 10000, 6000],
            setGroup: shoulderDropGroup
        )

        database.save()
    }

    var testWorkout: Workout {
        fetch(Workout.self).first as! Workout
    }

    var testTemplate: Template {
        let exampleExerciseNames = [NSLocalizedString("previewPushup", comment: ""), NSLocalizedString("previewDeadlift", comment: ""), NSLocalizedString("previewSquats", comment: ""), NSLocalizedString("previewPushup", comment: ""), NSLocalizedString("previewBarbellCurl", comment: "")]
        let template = newTemplate(name: NSLocalizedString("previewPerfectPushDay", comment: ""))
        for name in exampleExerciseNames {
            let exercise = newExercise(
                name: name,
                muscleGroup: MuscleGroup.allCases.randomElement()!
            )
            let setGroup = newTemplateSetGroup(exercise: exercise, template: template)
            for _ in 1 ..< Int.random(in: 2 ... 5) {
                newTemplateStandardSet(
                    repetitions: Int.random(in: 0 ... 10),
                    weight: Int.random(in: 0 ... 150),
                    setGroup: setGroup
                )
            }
        }
        // self.save()
        return template
    }
}
