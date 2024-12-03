//
//  WorkoutSetRepository.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.07.24.
//

import Foundation

final class WorkoutSetRepository: ObservableObject {
    
    private let database: Database
    private let currentWorkoutManager: CurrentWorkoutManager
    
    init(database: Database, currentWorkoutManager: CurrentWorkoutManager) {
        self.database = database
        self.currentWorkoutManager = currentWorkoutManager
    }
    
    func getWorkoutSets(with exercise: Exercise? = nil, includingCurrentWorkout: Bool = false) -> [WorkoutSet] {
        (database.fetch(
            WorkoutSet.self,
            sortingKey: "setGroup.workout.date",
            ascending: false
        ) as! [WorkoutSet])
        .filter { workoutSet in
            let isSetInCurrentWorkout = currentWorkoutManager.getCurrentWorkout()?.sets.contains { $0.id == workoutSet.id } ?? false
            return (exercise == nil || workoutSet.exercise == exercise 
                    || (workoutSet as? SuperSet)?.secondaryExercise == exercise)
                && (includingCurrentWorkout ? true : !isSetInCurrentWorkout)
        }
    }
    
    func getWorkoutSets(
        with exercise: Exercise? = nil,
        for calendarComponents: [Calendar.Component],
        including date: Date,
        includingCurrentWorkout: Bool = false
    ) -> [WorkoutSet] {
        getWorkoutSets(with: exercise, includingCurrentWorkout: includingCurrentWorkout)
            .filter {
                guard let workoutDate = $0.workout?.date else { return false }
                return Calendar.current.isDate(workoutDate, equalTo: date, toGranularity: calendarComponents)
            }
    }

//    func getWorkoutSets(
//        with exercise: Exercise? = nil,
//        onlyHighest attribute: WorkoutSet.Attribute,
//        in calendarComponent: Calendar.Component
//    ) -> [WorkoutSet] {
//        var result = [[WorkoutSet]]()
//        getWorkoutSets(with: exercise)
//            .forEach { workoutSet in
//                if let lastDate = result.last?.last?.workout?.date,
//                    let setGroupDate = workoutSet.workout?.date,
//                    Calendar.current.isDate(
//                        lastDate,
//                        equalTo: setGroupDate,
//                        toGranularity: calendarComponent
//                    )
//                {
//                    result[result.count - 1].append(workoutSet)
//                } else {
//                    result.append([workoutSet])
//                }
//            }
//        return
//            result
//            .compactMap { workoutSetsInWeek in
//                workoutSetsInWeek.max { $0.max(attribute) < $1.max(attribute) }
//            }
//            .sorted { $0.workout?.date ?? .now < $1.workout?.date ?? .now }
//    }
    
    func getGroupedWorkoutsSets(
        with exercise: Exercise? = nil,
        groupedBy groupingComponents: [Calendar.Component],
        includingCurrentWorkout: Bool = false
    ) -> [[WorkoutSet]] {
        var result = [[WorkoutSet]]()
        getWorkoutSets(with: exercise, includingCurrentWorkout: includingCurrentWorkout)
            .forEach { workoutSet in
                if let lastDate = result.last?.last?.workout?.date,
                    let setGroupDate = workoutSet.workout?.date,
                    Calendar.current.isDate(
                        lastDate,
                        equalTo: setGroupDate,
                        toGranularity: groupingComponents
                    )
                {
                    result[result.count - 1].append(workoutSet)
                } else {
                    result.append([workoutSet])
                }
            }
        return
            result
            .map { $0.sorted { $0.workout?.date ?? .now < $1.workout?.date ?? .now } }
            .sorted { $0.first?.workout?.date ?? .now < $1.first?.workout?.date ?? .now }
    }

    func getGroupedWorkoutsSets(
        with exercise: Exercise? = nil,
        for calendarComponents: [Calendar.Component],
        inclusing date: Date,
        groupedBy groupingComponents: [Calendar.Component],
        includingCurrentWorkout: Bool = false
    ) -> [[WorkoutSet]] {
        var result = [[WorkoutSet]]()
        getWorkoutSets(with: exercise, for: calendarComponents, including: date, includingCurrentWorkout: includingCurrentWorkout)
            .forEach { workoutSet in
                if let lastDate = result.last?.last?.workout?.date,
                    let setGroupDate = workoutSet.workout?.date,
                    Calendar.current.isDate(
                        lastDate,
                        equalTo: setGroupDate,
                        toGranularity: groupingComponents
                    )
                {
                    result[result.count - 1].append(workoutSet)
                } else {
                    result.append([workoutSet])
                }
            }
        return
            result
            .map { $0.sorted { $0.workout?.date ?? .now < $1.workout?.date ?? .now } }
            .sorted { $0.first?.workout?.date ?? .now < $1.first?.workout?.date ?? .now }
    }
}
