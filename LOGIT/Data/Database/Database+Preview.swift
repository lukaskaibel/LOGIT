//
//  Database+Preview.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 17.04.22.
//

import Foundation

extension Database {
    func setupPreviewDatabase() {
        let database = self

        (database.fetch(Workout.self) as! [Workout]).forEach { database.delete($0) }
        (database.fetch(Exercise.self) as! [Workout]).forEach { database.delete($0) }

        // MARK: Exercises

        let benchpress = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let inclinedBenchpress = database.newExercise(
            name: "Inclined Benchpress",
            muscleGroup: .chest
        )
        let overheadPress = database.newExercise(name: "Overhead Press", muscleGroup: .shoulders)
        let lateralRaises = database.newExercise(name: "Lateral Raises", muscleGroup: .shoulders)
        let tricepsExtensions = database.newExercise(
            name: "Triceps Extensions",
            muscleGroup: .triceps
        )
        let dips = database.newExercise(name: "Dips", muscleGroup: .chest)
        let squat = database.newExercise(name: "Squat", muscleGroup: .legs)
        let lunges = database.newExercise(name: "Lunges", muscleGroup: .legs)
        let legExtensions = database.newExercise(name: "Leg Extensions", muscleGroup: .legs)
        let deadlift = database.newExercise(name: "Deadlift", muscleGroup: .back)
        let standingRows = database.newExercise(name: "Standing Rows", muscleGroup: .back)
        let bicepsCurls = database.newExercise(name: "Biceps Curls", muscleGroup: .biceps)
        let latPulldown = database.newExercise(name: "Lat Pulldown", muscleGroup: .back)
        let crunches = database.newExercise(name: "Crunches", muscleGroup: .abdominals)

        // Create workouts with realistic durations (50-75 minutes)
        let workoutDurations = [65, 58, 72, 55, 68] // minutes
        
        for i in 0 ..< 5 {
            var date = Calendar.current.date(byAdding: .weekOfYear, value: -i, to: .now)!
            let pullday = database.newWorkout(name: "Pull Day", date: date)
            pullday.endDate = Calendar.current.date(byAdding: .minute, value: workoutDurations[i], to: date)
            
            let deadliftGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: deadlift,
                workout: pullday
            )
            database.newStandardSet(repetitions: 5, weight: 120_000, setGroup: deadliftGroup)
            database.newStandardSet(repetitions: 5, weight: 120_000, setGroup: deadliftGroup)
            database.newStandardSet(repetitions: 5, weight: 100_000, setGroup: deadliftGroup)
            database.newStandardSet(repetitions: 5, weight: 100_000, setGroup: deadliftGroup)
            let latGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: latPulldown,
                workout: pullday
            )
            database.newDropSet(repetitions: [5, 8], weights: [60000, 45000], setGroup: latGroup)
            database.newDropSet(repetitions: [5, 8], weights: [60000, 45000], setGroup: latGroup)
            database.newDropSet(repetitions: [5, 8], weights: [60000, 45000], setGroup: latGroup)
            let rowGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: standingRows,
                workout: pullday
            )
            database.newStandardSet(repetitions: 8, weight: 50000, setGroup: rowGroup)
            database.newStandardSet(repetitions: 8, weight: 50000, setGroup: rowGroup)
            database.newStandardSet(repetitions: 8, weight: 50000, setGroup: rowGroup)
            database.newStandardSet(repetitions: 8, weight: 50000, setGroup: rowGroup)
            let curlGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: bicepsCurls,
                workout: pullday
            )
            database.newStandardSet(repetitions: 12, weight: 30000, setGroup: curlGroup)
            database.newStandardSet(repetitions: 12, weight: 30000, setGroup: curlGroup)
            database.newStandardSet(repetitions: 12, weight: 30000, setGroup: curlGroup)

            date = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.date(byAdding: .weekOfYear, value: -i, to: .now)!)!
            let pushday = database.newWorkout(name: "Push Day", date: date)
            pushday.endDate = Calendar.current.date(byAdding: .minute, value: [62, 70, 54, 66, 59][i], to: date)
            
            let benchpressGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: benchpress,
                workout: pushday
            )
            database.newStandardSet(
                repetitions: 5,
                weight: i == 0
                    ? 100_000 : i == 1 ? 100_000 : i == 2 ? 90000 : i == 3 ? 91000 : 86000,
                setGroup: benchpressGroup
            )
            database.newStandardSet(
                repetitions: 5,
                weight: i == 0
                    ? 100_000 : i == 1 ? 100_000 : i == 2 ? 90000 : i == 3 ? 91000 : 86000,
                setGroup: benchpressGroup
            )
            database.newStandardSet(
                repetitions: 5,
                weight: i == 0
                    ? 100_000 : i == 1 ? 100_000 : i == 2 ? 90000 : i == 3 ? 91000 : 86000,
                setGroup: benchpressGroup
            )
            database.newStandardSet(
                repetitions: 5,
                weight: i == 0
                    ? 100_000 : i == 1 ? 100_000 : i == 2 ? 90000 : i == 3 ? 91000 : 86000,
                setGroup: benchpressGroup
            )
            database.newStandardSet(
                repetitions: 5,
                weight: i == 0
                    ? 100_000 : i == 1 ? 100_000 : i == 2 ? 90000 : i == 3 ? 91000 : 86000,
                setGroup: benchpressGroup
            )
            let overheadPressGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: overheadPress,
                workout: pushday
            )
            database.newStandardSet(
                repetitions: 10,
                weight: 30000,
                setGroup: overheadPressGroup
            )
            database.newStandardSet(
                repetitions: 10,
                weight: 30000,
                setGroup: overheadPressGroup
            )
            database.newStandardSet(
                repetitions: 10,
                weight: 30000,
                setGroup: overheadPressGroup
            )
            let inclinedBenchpressGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: inclinedBenchpress,
                workout: pushday
            )
            database.newStandardSet(
                repetitions: 12,
                weight: 50000,
                setGroup: inclinedBenchpressGroup
            )
            database.newStandardSet(
                repetitions: 12,
                weight: 50000,
                setGroup: inclinedBenchpressGroup
            )
            database.newStandardSet(
                repetitions: 12,
                weight: 50000,
                setGroup: inclinedBenchpressGroup
            )
            let dipsGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: dips,
                workout: pushday
            )
            database.newStandardSet(repetitions: 8, weight: 0, setGroup: dipsGroup)
            database.newStandardSet(repetitions: 8, weight: 0, setGroup: dipsGroup)
            database.newStandardSet(repetitions: 6, weight: 0, setGroup: dipsGroup)
            let tricepsShoulderGroup = database.newWorkoutSetGroup(
                createFirstSetAutomatically: false,
                exercise: tricepsExtensions,
                workout: pushday
            )
            tricepsShoulderGroup.secondaryExercise = lateralRaises
            database.newSuperSet(
                repetitionsFirstExercise: 12,
                repetitionsSecondExercise: 14,
                weightFirstExercise: 25000,
                weightSecondExercise: 18000,
                setGroup: tricepsShoulderGroup
            )
            database.newSuperSet(
                repetitionsFirstExercise: 12,
                repetitionsSecondExercise: 14,
                weightFirstExercise: 25000,
                weightSecondExercise: 18000,
                setGroup: tricepsShoulderGroup
            )
            database.newSuperSet(
                repetitionsFirstExercise: 12,
                repetitionsSecondExercise: 14,
                weightFirstExercise: 25000,
                weightSecondExercise: 18000,
                setGroup: tricepsShoulderGroup
            )

            if i > 0, i != 4 {
                date = Calendar.current.date(byAdding: .day, value: -4, to: Calendar.current.date(byAdding: .weekOfYear, value: -i, to: .now)!)!
                let legday = database.newWorkout(name: "Leg Day", date: date)
                legday.endDate = Calendar.current.date(byAdding: .minute, value: [0, 75, 68, 71][i-1], to: date)
                
                let squatGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: squat,
                    workout: legday
                )
                database.newStandardSet(repetitions: 8, weight: 100_000, setGroup: squatGroup)
                database.newStandardSet(repetitions: 8, weight: 100_000, setGroup: squatGroup)
                database.newStandardSet(repetitions: 6, weight: 100_000, setGroup: squatGroup)
                database.newStandardSet(repetitions: 6, weight: 100_000, setGroup: squatGroup)
                let lungesGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: lunges,
                    workout: legday
                )
                database.newStandardSet(repetitions: 12, weight: 50000, setGroup: lungesGroup)
                database.newStandardSet(repetitions: 12, weight: 50000, setGroup: lungesGroup)
                database.newStandardSet(repetitions: 12, weight: 50000, setGroup: lungesGroup)
                database.newStandardSet(repetitions: 12, weight: 50000, setGroup: lungesGroup)
                let legExtensionsGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: legExtensions,
                    workout: legday
                )
                database.newDropSet(
                    repetitions: [8, 5],
                    weights: [40000, 25000],
                    setGroup: legExtensionsGroup
                )
                database.newDropSet(
                    repetitions: [6, 4],
                    weights: [40000, 25000],
                    setGroup: legExtensionsGroup
                )
                database.newDropSet(
                    repetitions: [6, 4],
                    weights: [40000, 25000],
                    setGroup: legExtensionsGroup
                )
                let absGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: crunches,
                    workout: legday
                )
                database.newStandardSet(repetitions: 12, weight: 0, setGroup: absGroup)
                database.newStandardSet(repetitions: 12, weight: 0, setGroup: absGroup)
                database.newStandardSet(repetitions: 12, weight: 0, setGroup: absGroup)
            }
        }

        let date = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: .now)!
        let firstBenchWorkout = database.newWorkout(name: "Quick Bench Session", date: date)
        firstBenchWorkout.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: date)
        _ = database.newWorkoutSetGroup(
            sets: [database.newStandardSet(repetitions: 12, weight: 78000)],
            exercise: benchpress,
            workout: firstBenchWorkout
        )
        let secondBenchWorkout = database.newWorkout(
            name: "Bench Focus",
            date: Calendar.current.date(byAdding: .weekOfYear, value: -7, to: .now)!
        )
        secondBenchWorkout.endDate = Calendar.current.date(byAdding: .minute, value: 28, to: secondBenchWorkout.date!)
        _ = database.newWorkoutSetGroup(
            sets: [database.newStandardSet(repetitions: 12, weight: 67000)],
            exercise: benchpress,
            workout: secondBenchWorkout
        )
        let thirdBenchWorkout = database.newWorkout(
            name: "Morning Bench",
            date: Calendar.current.date(byAdding: .weekOfYear, value: -9, to: .now)!
        )
        thirdBenchWorkout.endDate = Calendar.current.date(byAdding: .minute, value: 25, to: thirdBenchWorkout.date!)
        _ = database.newWorkoutSetGroup(
            sets: [database.newStandardSet(repetitions: 12, weight: 55000)],
            exercise: benchpress,
            workout: thirdBenchWorkout
        )
        let fourthBenchWorkout = database.newWorkout(
            name: "Bench & Accessories",
            date: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now)!
        )
        fourthBenchWorkout.endDate = Calendar.current.date(byAdding: .minute, value: 45, to: fourthBenchWorkout.date!)
        _ = database.newWorkoutSetGroup(
            sets: [database.newStandardSet(repetitions: 12, weight: 50000)],
            exercise: benchpress,
            workout: fourthBenchWorkout
        )

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

        let pushTemplate = database.newTemplate(name: "Push Day")
        addTemplateSet(exercise: benchpress, template: pushTemplate, reps: 8, weight: 70000, extraSets: 3)
        addTemplateSet(exercise: inclinedBenchpress, template: pushTemplate, reps: 10, weight: 55000)
        addTemplateSet(exercise: overheadPress, template: pushTemplate, reps: 8, weight: 45000)
        addTemplateSet(exercise: tricepsExtensions, template: pushTemplate, reps: 12, weight: 25000)
        addTemplateSet(exercise: lateralRaises, template: pushTemplate, reps: 15, weight: 12000)

        let pullTemplate = database.newTemplate(name: "Pull Day")
        addTemplateSet(exercise: deadlift, template: pullTemplate, reps: 5, weight: 120000, extraSets: 3)
        addTemplateSet(exercise: latPulldown, template: pullTemplate, reps: 10, weight: 60000)
        addTemplateSet(exercise: standingRows, template: pullTemplate, reps: 10, weight: 55000)
        addTemplateSet(exercise: bicepsCurls, template: pullTemplate, reps: 12, weight: 30000)

        let legTemplate = database.newTemplate(name: "Leg Day")
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
        let inProgressStart = Calendar.current.date(byAdding: .minute, value: -23, to: .now)!
        let currentPushDay = database.newWorkout(name: "Push Day", date: inProgressStart)
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

        // MARK: Completed "Arm Day" workout with superset + drop set
        //
        // Dedicated fixture for the marketing screenshot that shows a super
        // set and a drop set one after another inside the same completed
        // workout. Uses "Arm Day" as the name so the UI test can find it
        // unambiguously (other seeded workouts are named Push/Pull/Leg Day).
        let armDayDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let armDay = database.newWorkout(name: "Arm Day", date: armDayDate)
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
        let exampleExerciseNames = ["Pushup", "Deadlift", "Squats", "Pushup", "Bar-Bell Curl"]
        let template = newTemplate(name: "Perfect Push-Day")
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
