//
//  WorkoutRepository.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.07.24.
//

import Combine
import Foundation

class WorkoutRepository: ObservableObject {
    
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
    
    enum WorkoutSortingKey: String {
        case date, name
    }

    enum WorkoutGroupingKey: Equatable {
        case date(calendarComponents: [Calendar.Component])
        case name

        static func == (lhs: WorkoutGroupingKey, rhs: WorkoutGroupingKey) -> Bool {
            switch lhs {
            case .name:
                switch rhs {
                case .name: return true
                case .date: return false
                }
            case .date:
                switch rhs {
                case .name: return false
                case .date: return true
                }
            }
        }
    }
    
    func getWorkout(with id: UUID) -> Workout? {
        (database.fetch(
            Workout.self,
            predicate: NSPredicate(format: "id == %@", id as CVarArg)
        ) as! [Workout]).first
    }

    func getWorkouts(
        withNameIncluding filteredText: String = "",
        sortedBy sortingKey: WorkoutSortingKey = .date,
        usingMuscleGroup muscleGroup: MuscleGroup? = nil,
        includingCurrentWorkout: Bool = false
    ) -> [Workout] {
        (database.fetch(
            Workout.self,
            sortingKey: sortingKey.rawValue,
            ascending: sortingKey == .name,
            predicate: filteredText.isEmpty
                ? nil
                : NSPredicate(
                    format: "name CONTAINS[c] %@",
                    filteredText
                )
        ) as! [Workout])
        .filter {
            (muscleGroup == nil || ($0.exercises.map { $0.muscleGroup }).contains(muscleGroup)) &&
            (includingCurrentWorkout ? true : $0 != currentWorkoutManager.getCurrentWorkout())
        }
    }

    func getWorkouts(
        withNameIncluding filteredText: String = "",
        sortedBy sortingKey: WorkoutSortingKey = .date,
        for calendarComponents: [Calendar.Component],
        including date: Date,
        includingCurrentWorkout: Bool = false
    ) -> [Workout] {
        getWorkouts(withNameIncluding: filteredText, sortedBy: sortingKey, includingCurrentWorkout: includingCurrentWorkout)
            .filter {
                guard let workoutDate = $0.date else { return false }
                return Calendar.current.isDate(workoutDate, equalTo: date, toGranularity: calendarComponents)
            }
    }

    func getGroupedWorkouts(
        withNameIncluding filteredText: String = "",
        groupedBy groupingKey: WorkoutGroupingKey = .name,
        usingMuscleGroup muscleGroup: MuscleGroup? = nil,
        includingCurrentWorkout: Bool = false
    ) -> [[Workout]] {
        var result = [[Workout]]()
        getWorkouts(
            withNameIncluding: filteredText,
            sortedBy: groupingKey == .name ? .name : .date,
            usingMuscleGroup: muscleGroup,
            includingCurrentWorkout: includingCurrentWorkout
        )
        .forEach { workout in
            switch groupingKey {
            case .date(let components):
                if let lastDate = result.last?.last?.date,
                    let workoutDate = workout.date,
                    Calendar.current.isDate(lastDate, equalTo: workoutDate, toGranularity: components)
                {
                    result[result.count - 1].append(workout)
                } else {
                    result.append([workout])
                }
            case .name:
                if let firstLetterOfLastWorkoutName = result.last?.last?.name?.first,
                    let workoutFirstLetter = workout.name?.first,
                    firstLetterOfLastWorkoutName == workoutFirstLetter
                {
                    result[result.count - 1].append(workout)
                } else {
                    result.append([workout])
                }
            }
        }
        return result
    }
    
}
