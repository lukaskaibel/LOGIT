//
//  WorkoutSetGroupRepository.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.07.24.
//

import Combine
import Foundation

final class WorkoutSetGroupRepository: ObservableObject {
    
    enum WorkoutSetGroupSortingKey: String {
        case date, name
    }
    
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

    func getWorkoutSetGroups(with exercise: Exercise? = nil, includingCurrentWorkout: Bool = false) -> [WorkoutSetGroup] {
        (database.fetch(
            WorkoutSetGroup.self,
            sortingKey: "workout.date",
            ascending: false
        ) as! [WorkoutSetGroup])
        .filter { workoutSetGroup in
            let isSetInCurrentWorkout = currentWorkoutManager.getCurrentWorkout()?.setGroups.contains { workoutSetGroup.id == $0.id } ?? false
            return (exercise == nil || workoutSetGroup.exercise == exercise
                    || workoutSetGroup.secondaryExercise == exercise)
            && (includingCurrentWorkout ? true : !isSetInCurrentWorkout)
        }
    }

    func getGroupedWorkoutSetGroups(
        with exercise: Exercise? = nil,
        groupedBy sortingKey: WorkoutSetGroupSortingKey = .date
    ) -> [[WorkoutSetGroup]] {
        var result = [[WorkoutSetGroup]]()
        getWorkoutSetGroups(with: exercise)
            .forEach { setGroup in
                if let lastDate = result.last?.last?.workout?.date,
                    let setGroupDate = setGroup.workout?.date,
                    Calendar.current.isDate(lastDate, equalTo: setGroupDate, toGranularity: .month)
                {
                    result[result.count - 1].append(setGroup)
                } else {
                    result.append([setGroup])
                }
            }
        return result
    }

    
}
