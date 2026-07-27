//
//  DefaultExerciseService.swift
//  LOGIT
//
//  Created by GitHub Copilot
//

import Foundation
import CoreData
import Combine

struct DefaultExerciseData: Codable {
    let version: Int
    let exercises: [DefaultExercise]
}

struct DefaultExercise: Codable {
    let id: String
    let nameKey: String
    let muscleGroup: String
    /// `SetMeasurementType` raw value for exercises that aren't tracked as reps + weight
    /// (planks, cardio, loaded carries). Absent = reps + weight.
    let measurementType: String?
    let instructions: [String]?
    let localizedInstructions: [String: [String]]?

    func instructions(for localeIdentifier: String) -> [String]? {
        let normalizedLocale = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let languageCode = normalizedLocale.split(separator: "-").first.map(String.init)
        let candidates = [
            normalizedLocale,
            languageCode,
            "en"
        ].compactMap { $0 }

        for candidate in candidates {
            if let localized = localizedInstructions?[candidate] {
                return localized
            }
        }

        return instructions
    }
}

class DefaultExerciseService: ObservableObject {
    private let database: Database
    private let defaults: UserDefaults
    private let lastLoadedVersionKey = "lastLoadedDefaultExercisesVersion"
    private let lastLoadedLocaleKey = "lastLoadedDefaultExercisesLocale"

    /// Measurement types that *older library versions* shipped for these exercises. Loading a
    /// library update stores an explicit type, which makes the nil-check below blind to later
    /// library re-types — so an unused exercise still carrying one of these provably (or as good
    /// as: the user never recorded with it) got its type from the library, and a newer library
    /// may re-type it. Library v7 moved the cardio machines from duration to distance+duration
    /// and the carries from weight+duration to weight+distance.
    private static let supersededLibraryTypes: [String: [SetMeasurementType]] = [
        // v6 duration -> v7 distanceAndDuration
        "default_076": [.duration],  // running
        "default_077": [.duration],  // cycling
        "default_078": [.duration],  // rowing
        "default_080": [.duration],  // elliptical
        "default_082": [.duration],  // swimming
        "default_165": [.duration],  // sprints
        "default_167": [.duration],  // assault bike
        "default_168": [.duration],  // rowing machine
        "default_169": [.duration],  // ski erg
        // v6 weightAndDuration -> v7 weightAndDistance
        "default_170": [.weightAndDuration],  // farmers walk
        "default_192": [.weightAndDuration],  // sled push
        "default_193": [.weightAndDuration],  // sled pull
    ]

    init(database: Database, defaults: UserDefaults = .standard) {
        self.database = database
        self.defaults = defaults
    }
    
    func loadDefaultExercisesIfNeeded() {
        guard let url = Bundle.main.url(forResource: "default_exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let exerciseData = try? JSONDecoder().decode(DefaultExerciseData.self, from: data) else {
            print("DefaultExerciseService: Failed to load default exercises JSON")
            return
        }
        
        let lastLoadedVersion = defaults.integer(forKey: lastLoadedVersionKey)
        let preferredLocale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let lastLoadedLocale = defaults.string(forKey: lastLoadedLocaleKey)
        
        if exerciseData.version > lastLoadedVersion || preferredLocale != lastLoadedLocale {
            createOrUpdateDefaultExercises(exerciseData.exercises, localeIdentifier: preferredLocale)
            defaults.set(exerciseData.version, forKey: lastLoadedVersionKey)
            defaults.set(preferredLocale, forKey: lastLoadedLocaleKey)
            database.save()
            print("DefaultExerciseService: Loaded default exercises version \(exerciseData.version)")
        }
    }
    
    private func createOrUpdateDefaultExercises(_ exercises: [DefaultExercise], localeIdentifier: String) {
        for exerciseData in exercises {
            let instructions = exerciseData.instructions(for: localeIdentifier)
            let libraryMeasurementType =
                SetMeasurementType(rawValue: exerciseData.measurementType ?? "") ?? .repsAndWeight

            if let existingExercise = fetchExerciseByDefaultId(exerciseData.id) {
                existingExercise.name = exerciseData.nameKey
                if let muscleGroup = MuscleGroup(rawValue: exerciseData.muscleGroup) {
                    existingExercise.muscleGroup = muscleGroup
                }
                existingExercise.instructions = instructions
                // Adopt the library's measurement type only while the user has never recorded
                // anything with the exercise — an established logging habit is never changed
                // underneath them — and the stored type is either absent or one an older
                // library version shipped itself (a differing value means the user chose it in
                // the editor, which always stores explicitly).
                let storedType = SetMeasurementType(
                    rawValue: existingExercise.measurementTypeString ?? ""
                )
                let libraryShippedStored = storedType.map {
                    Self.supersededLibraryTypes[exerciseData.id]?.contains($0) ?? false
                } ?? false
                if existingExercise.measurementTypeString == nil || libraryShippedStored,
                   existingExercise.setGroups.isEmpty,
                   existingExercise.templateSetGroups.isEmpty {
                    existingExercise.measurementType = libraryMeasurementType
                }
            } else {
                let exercise = Exercise(context: database.context)
                exercise.id = generateUUID(from: exerciseData.id)
                exercise.name = exerciseData.nameKey
                if let muscleGroup = MuscleGroup(rawValue: exerciseData.muscleGroup) {
                    exercise.muscleGroup = muscleGroup
                }
                exercise.instructions = instructions
                exercise.measurementType = libraryMeasurementType
            }
        }
    }
    
    private func generateUUID(from defaultId: String) -> UUID {
        DeterministicUUID.make(namespace: "com.logit.defaultexercise", id: defaultId)
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
