//
//  WorkoutSetRepository.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.07.24.
//

import Combine
import Foundation

final class WorkoutSetRepository: ObservableObject {
    
    private let database: Database
    private let currentWorkoutManager: CurrentWorkoutManager
    private var cancellables = Set<AnyCancellable>()
    
    init(database: Database, currentWorkoutManager: CurrentWorkoutManager) {
        self.database = database
        self.currentWorkoutManager = currentWorkoutManager
        
        self.database.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
        includingCurrentWorkout: Bool = false,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) -> [WorkoutSet] {
        // Build subpredicates based on the passed parameters.
        var subpredicates = [NSPredicate]()

        // 1. Optional Exercise Filtering
        //    If an exercise is specified, we only want sets whose
        //    primary OR secondary exercise matches.
        if let exerciseId = exercise?.id {
            let exercisePredicate = NSPredicate(format: "ANY setGroup.exercises_.id == %@", exerciseId.uuidString)
            subpredicates.append(exercisePredicate)
        }
        
        // 2. Optional Date Range
        //    If a startDate is provided, require date >= startDate.
        if let start = startDate {
            let startDatePredicate = NSPredicate(
                format: "setGroup.workout.date >= %@", start as NSDate
            )
            subpredicates.append(startDatePredicate)
        }
        
        //    If an endDate is provided, require date <= endDate.
        if let end = endDate {
            let endDatePredicate = NSPredicate(
                format: "setGroup.workout.date <= %@", end as NSDate
            )
            subpredicates.append(endDatePredicate)
        }
        
        // 3. Including / Excluding Current Workout Sets
        //    If we do NOT want to include sets in the current workout,
        //    exclude them by checking the workout’s ID.
        //    (Adjust for how you track the current workout’s ID.)
        if !includingCurrentWorkout {
            if let currentWorkoutID = currentWorkoutManager.getCurrentWorkout()?.id {
                let excludeCurrentPredicate = NSPredicate(
                    format: "setGroup.workout.id != %@", currentWorkoutID.uuidString
                )
                subpredicates.append(excludeCurrentPredicate)
            }
        }
        

        // Combine all subpredicates with AND logic.
        let finalPredicate = subpredicates.isEmpty
            ? nil
            : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        // 4. Fetch from Core Data
        //    Uses your database.fetch(...) method, passing in the final predicate
        //    and sorting by date in descending order.
        let fetchedSets = database.fetch(
            WorkoutSet.self,
            sortingKey: "setGroup.workout.date",
            ascending: false,
            predicate: finalPredicate
        ) as? [WorkoutSet] ?? []

        // Return the resulting array
        return fetchedSets
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
    
    func getGroupedWorkoutSets(
        with exercise: Exercise? = nil,
        groupedBy groupingComponents: [Calendar.Component],
        includingCurrentWorkout: Bool = false,
        from startDate: Date? = nil,
        to endDate: Date? = nil
    ) -> [[WorkoutSet]] {
        var result = [[WorkoutSet]]()
        getWorkoutSets(with: exercise, includingCurrentWorkout: includingCurrentWorkout, from: startDate, to: endDate)
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
    
    // TODO: Function is deprecated and should be removed. Use above function instead
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

    // TODO: Deprecated -> use function with from to
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
