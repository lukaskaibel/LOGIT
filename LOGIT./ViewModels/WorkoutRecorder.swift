//
//  WorkoutRecorder.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.03.24.
//

import Foundation
import CoreData
import OSLog
import Combine

final class WorkoutRecorder: ObservableObject {
    
    // MARK: - Static
    
    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "WorkoutRecorder")
    private static let CURRENT_WORKOUT_ID_KEY = "CURRENT_WORKOUT_ID_KEY"
    
    // MARK: - Public Variables
    
    @Published var workout: Workout?
    
    // MARK: - Private Variables
    
    private let database: Database
    private let currentWorkoutManager: CurrentWorkoutManager
    private var workoutSetTemplateSetDictionary = [WorkoutSet: TemplateSet]()
    private var cancellable: AnyCancellable?
    
    // MARK: - Init
    
    init(database: Database, currentWorkoutManager: CurrentWorkoutManager) {
        self.database = database
        self.currentWorkoutManager = currentWorkoutManager
        workout = currentWorkoutManager.getCurrentWorkout()
    }
    
    // MARK: - Public Methods
    
    func startWorkout(from template: Template? = nil) {
        workout = database.newWorkout()
        currentWorkoutManager.setCurrentWorkout(workout!)
        if let template = template {
            template.workouts.append(workout!)
            workout!.name = template.name
            for templateSetGroup in template.setGroups {
                let setGroup = database.newWorkoutSetGroup(
                    createFirstSetAutomatically: false,
                    exercise: templateSetGroup.exercise,
                    workout: workout
                )
                templateSetGroup.sets
                    .forEach { templateSet in
                        if let templateStandardSet = templateSet as? TemplateStandardSet {
                            let standardSet = database.newStandardSet(setGroup: setGroup)
                            workoutSetTemplateSetDictionary[standardSet] = templateStandardSet
                        } else if let templateDropSet = templateSet as? TemplateDropSet {
                            let dropSet = database.newDropSet(from: templateDropSet, setGroup: setGroup)
                            workoutSetTemplateSetDictionary[dropSet] = templateDropSet
                        } else if let templateSuperSet = templateSet as? TemplateSuperSet {
                            let superSet = database.newSuperSet(
                                from: templateSuperSet,
                                setGroup: setGroup
                            )
                            workoutSetTemplateSetDictionary[superSet] = templateSuperSet
                        }
                    }
            }
        }
        database.save()
    }
    
    func saveWorkout() {
        guard let workout = workout else {
            Self.logger.warning("Attempted to save empty workout")
            return
        }
        
        // Use a local copy of the workout for the background operations to avoid race conditions
        let workoutCopy = workout
        self.workout = nil
        currentWorkoutManager.setCurrentWorkout(nil)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let database = self?.database else {
                Self.logger.error("Failed to clean up workout after finish: self already uninitialized")
                return
            }
            
            if workoutCopy.name?.isEmpty ?? true {
                workoutCopy.name = Workout.getStandardName(for: workoutCopy.date!)
            }
            workoutCopy.endDate = .now
            workoutCopy.setGroups.forEach {
                if $0.setType == .superSet && $0.secondaryExercise == nil {
                    database.convertSetGroupToStandardSets($0)
                }
            }
            
            workoutCopy.exercises.forEach { database.unflagAsTemporary($0) }
            database.deleteAllTemporaryObjects()
            
            workoutCopy.sets.filter({ !$0.hasEntry }).forEach { database.delete($0) }
            
            // This refresh is needed, as otherwise workoutCopy.isEmpty will still put out false
            // even if all the WorkoutSetGroups have been deleted, as the workoutCopy object has not refreshed yet
            
            if workoutCopy.isEmpty {
                database.delete(workoutCopy, saveContext: true)
            }
            
            database.save()
        }
    }

    
    func discardWorkout() {
        guard let workout = workout else {
            Self.logger.warning("Attempted to discard empty workout")
            return
        }
        
        let workoutCopy = workout
        self.workout = nil
        currentWorkoutManager.setCurrentWorkout(nil)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let database = self?.database else {
                Self.logger.error("Failed to discard workout: self already uninitialized")
                return
            }
            database.deleteAllTemporaryObjects()

            workoutCopy.sets.filter({ !$0.hasEntry }).forEach { database.delete($0) }
            
            database.delete(workoutCopy, saveContext: true)
        }
    }
    
    func addSetGroup(with exercise: Exercise) {
        database.newWorkoutSetGroup(
            createFirstSetAutomatically: true,
            exercise: exercise,
            workout: workout
        )
        objectWillChange.send()
    }
    
    func moveSetGroups(from source: IndexSet, to destination: Int) {
        workout?.setGroups.move(fromOffsets: source, toOffset: destination)
        objectWillChange.send()
    }
    
    func toggleSetCompleted(for workoutSet: WorkoutSet) {
        if let templateSet = workoutSetTemplateSetDictionary[workoutSet] {
            if workoutSet.hasEntry {
                workoutSet.clearEntries()
            } else {
                workoutSet.match(templateSet)
            }
            objectWillChange.send()
        }
    }
    
    func toggleCopyPrevious(for workoutSet: WorkoutSet) {
        if workoutSet.hasEntry {
            workoutSet.clearEntries()
        } else {
            guard let previousSet = workoutSet.previousSetInSetGroup else { return }
            workoutSet.match(previousSet)
        }
        objectWillChange.send()
    }
    
    func templateSet(for workoutSet: WorkoutSet) -> TemplateSet? {
        workoutSetTemplateSetDictionary[workoutSet]
    }
    
    /// Returns the next workout set to be executed. This is the first workout set, that has no workout set with entries after it.
    var nextPerformedWorkoutSet: WorkoutSet? {
        workout?.sets.reversed().reduce(nil, { $1.hasEntry ? $0 : $1 })
    }

}
