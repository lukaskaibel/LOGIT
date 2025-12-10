//
//  DefaultExerciseService.swift
//  LOGIT
//
//  Created by GitHub Copilot
//

import Foundation
import CoreData

struct DefaultExerciseData: Codable {
    let version: Int
    let exercises: [DefaultExercise]
}

struct DefaultExercise: Codable {
    let id: String
    let nameKey: String
    let muscleGroup: String
}

class DefaultExerciseService {
    private let database: Database
    private let defaults = UserDefaults.standard
    private let lastLoadedVersionKey = "lastLoadedDefaultExercisesVersion"
    
    init(database: Database) {
        self.database = database
    }
    
    func loadDefaultExercisesIfNeeded() {
        guard let url = Bundle.main.url(forResource: "default_exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exerciseData = try? JSONDecoder().decode(DefaultExerciseData.self, from: data) else {
            print("DefaultExerciseService: Failed to load default exercises JSON")
            return
        }
        
        let lastLoadedVersion = defaults.integer(forKey: lastLoadedVersionKey)
        
        if exerciseData.version > lastLoadedVersion {
            createOrUpdateDefaultExercises(exerciseData.exercises)
            defaults.set(exerciseData.version, forKey: lastLoadedVersionKey)
            database.save()
            print("DefaultExerciseService: Loaded default exercises version \(exerciseData.version)")
        }
    }
    
    private func createOrUpdateDefaultExercises(_ exercises: [DefaultExercise]) {
        for exerciseData in exercises {
            if let existingExercise = fetchExerciseByDefaultId(exerciseData.id) {
                existingExercise.name = exerciseData.nameKey
                if let muscleGroup = MuscleGroup(rawValue: exerciseData.muscleGroup) {
                    existingExercise.muscleGroup = muscleGroup
                }
            } else {
                let exercise = Exercise(context: database.context)
                exercise.id = generateUUID(from: exerciseData.id)
                exercise.name = exerciseData.nameKey
                if let muscleGroup = MuscleGroup(rawValue: exerciseData.muscleGroup) {
                    exercise.muscleGroup = muscleGroup
                }
            }
        }
    }
    
    private func generateUUID(from defaultId: String) -> UUID {
        // Create deterministic UUID from default ID
        // Use MD5 hash to generate UUID v3-style identifier
        let namespace = "com.logit.defaultexercise"
        let input = namespace + defaultId
        
        guard let data = input.data(using: .utf8) else {
            return UUID()
        }
        
        // Simple hash-based UUID generation
        var hash = data.withUnsafeBytes { bytes -> [UInt8] in
            var result = [UInt8](repeating: 0, count: 16)
            for (index, byte) in bytes.enumerated() {
                result[index % 16] ^= byte
            }
            return result
        }
        
        // Set version (3) and variant bits for UUID
        hash[6] = (hash[6] & 0x0F) | 0x30
        hash[8] = (hash[8] & 0x3F) | 0x80
        
        let uuidString = String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                               hash[0], hash[1], hash[2], hash[3],
                               hash[4], hash[5], hash[6], hash[7],
                               hash[8], hash[9], hash[10], hash[11],
                               hash[12], hash[13], hash[14], hash[15])
        
        return UUID(uuidString: uuidString) ?? UUID()
    }
    
    private func fetchExerciseByDefaultId(_ defaultId: String) -> Exercise? {
        let uuid = generateUUID(from: defaultId)
        
        let request = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        
        do {
            let results = try database.context.fetch(request)
            return results.first
        } catch {
            print("DefaultExerciseService: Failed to fetch exercise: \(error)")
            return nil
        }
    }
}
