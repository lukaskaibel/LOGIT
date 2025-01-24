//
//  CurrentWorkoutManager.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.04.24.
//

import Foundation
import OSLog

final class CurrentWorkoutManager {
    
    // MARK: - Static
    
    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "CurrentWorkoutManager")
    private static let CURRENT_WORKOUT_ID_KEY = "CURRENT_WORKOUT_ID_KEY"
    
    // MARK: - Private Variables
    
    private let database: Database
    
    // MARK: - Init
    
    init(database: Database) {
        self.database = database
    }
    
    // MARK: - Public
    
    func getCurrentWorkout() -> Workout? {
        guard let idString = UserDefaults.standard.value(forKey: CurrentWorkoutManager.CURRENT_WORKOUT_ID_KEY) as? String,
                let uuid = UUID(uuidString: idString)
        else {
            return nil
        }
        guard let currentWorkout = (database.fetch(Workout.self, predicate: NSPredicate(format: "id == %@", uuid as CVarArg)) as! [Workout]).first else {
            Self.logger.warning("Failed to get current workout: no workout matching id: \(uuid)")
            return nil
        }
        return currentWorkout
    }
    
    func setCurrentWorkout(_ workout: Workout?) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let workout = workout else {
                UserDefaults.standard.removeObject(forKey: CurrentWorkoutManager.CURRENT_WORKOUT_ID_KEY)
                Self.logger.log("Set to current workout to 'nil'")
                return
            }
            guard let id = workout.id else {
                Self.logger.error("Failed to set current workout: workout has no id")
                return
            }
            UserDefaults.standard.setValue(
                id.uuidString,
                forKey: CurrentWorkoutManager.CURRENT_WORKOUT_ID_KEY
            )
            Self.logger.log("Successfully set current workout with id: \(id)")
        }
    }
    
}
