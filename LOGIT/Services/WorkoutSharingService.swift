//
//  WorkoutSharingService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.02.26.
//

import Foundation
import os
import UniformTypeIdentifiers

/// Service for exporting and importing workouts and templates
/// Handles file creation, exercise matching, and Core Data entity creation
final class WorkoutSharingService {
    
    // MARK: - Types
    
    enum ShareType {
        case workout
        case template
    }
    
    enum ImportError: LocalizedError {
        case invalidFileFormat
        case decodingFailed(Error)
        case exerciseMatchingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidFileFormat:
                return "The file format is not supported."
            case .decodingFailed(let error):
                return "Failed to read the file: \(error.localizedDescription)"
            case .exerciseMatchingFailed:
                return "Failed to match exercises."
            }
        }
    }
    
    // MARK: - Properties
    
    private let database: Database
    private let fuzzySearchService = FuzzySearchService.shared
    
    /// Threshold for fuzzy matching custom exercises (0.0 = exact, 1.0 = match anything)
    /// Using a strict threshold to only match very similar exercises
    private let fuzzyMatchThreshold: Double = 0.3
    
    // MARK: - Init
    
    init(database: Database) {
        self.database = database
    }
    
    // MARK: - Export Methods
    
    /// Exports a workout to a shareable .logitworkout file
    /// - Parameter workout: The workout to export
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportWorkout(_ workout: Workout) -> URL? {
        let dto = WorkoutDTO(from: workout)
        return exportToFile(dto, filename: sanitizeFilename(workout.name ?? "Workout"), extension: "logitworkout")
    }
    
    /// Exports a template to a shareable .logittemplate file
    /// - Parameter template: The template to export
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportTemplate(_ template: Template) -> URL? {
        let dto = TemplateDTO(from: template)
        return exportToFile(dto, filename: sanitizeFilename(template.name ?? "Template"), extension: "logittemplate")
    }
    
    /// Exports a workout as a template file
    /// - Parameter workout: The workout to export as template
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportWorkoutAsTemplate(_ workout: Workout) -> URL? {
        // Create a TemplateDTO from the workout data
        let templateDTO = TemplateDTO(
            name: workout.name ?? "Shared Workout",
            setGroups: workout.setGroups.map { workoutSetGroup in
                TemplateSetGroupDTO(
                    exercise: ExerciseDTO(from: workoutSetGroup.exercise),
                    sets: workoutSetGroup.sets.map { workoutSet in
                        // Convert WorkoutSet to TemplateSetDTO (preserving reps and weight)
                        if let superSet = workoutSet as? SuperSet {
                            return TemplateSetDTO(
                                type: .superSet,
                                repetitionsFirstExercise: Int(superSet.repetitionsFirstExercise),
                                repetitionsSecondExercise: Int(superSet.repetitionsSecondExercise),
                                weightFirstExercise: Int(superSet.weightFirstExercise),
                                weightSecondExercise: Int(superSet.weightSecondExercise)
                            )
                        } else if let dropSet = workoutSet as? DropSet {
                            return TemplateSetDTO(
                                type: .dropSet,
                                dropSetRepetitions: dropSet.repetitions?.map { Int($0) },
                                dropSetWeights: dropSet.weights?.map { Int($0) }
                            )
                        } else if let standardSet = workoutSet as? StandardSet {
                            return TemplateSetDTO(repetitions: Int(standardSet.repetitions), weight: Int(standardSet.weight), type: .standard)
                        } else {
                            return TemplateSetDTO(repetitions: 0, weight: 0, type: .standard)
                        }
                    },
                    secondaryExercise: workoutSetGroup.secondaryExercise.map { ExerciseDTO(from: $0) },
                    setType: workoutSetGroup.setType.rawValue
                )
            },
            formatVersion: TemplateDTO.formatVersion,
            appStoreURL: "https://apps.apple.com/app/logit-track-your-workouts/id6444813640"
        )
        return exportToFile(templateDTO, filename: sanitizeFilename(workout.name ?? "Workout"), extension: "logittemplate")
    }
    
    // MARK: - Import Methods
    
    /// Imports a workout from a .logitworkout file
    /// Creates the workout and all necessary exercises, flagging new entities as temporary
    /// - Parameter url: URL to the .logitworkout file
    /// - Returns: The imported Workout, or throws an error
    func importWorkout(from url: URL) throws -> Workout {
        guard url.pathExtension.lowercased() == "logitworkout" else {
            throw ImportError.invalidFileFormat
        }
        
        let data: Data
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } else {
            data = try Data(contentsOf: url)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let workoutDTO: WorkoutDTO
        do {
            workoutDTO = try decoder.decode(WorkoutDTO.self, from: data)
        } catch {
            throw ImportError.decodingFailed(error)
        }
        
        return try createWorkout(from: workoutDTO)
    }
    
    /// Imports a template from a .logittemplate file
    /// Creates the template and all necessary exercises, flagging new entities as temporary
    /// - Parameter url: URL to the .logittemplate file
    /// - Returns: The imported Template, or throws an error
    func importTemplate(from url: URL) throws -> Template {
        guard url.pathExtension.lowercased() == "logittemplate" else {
            throw ImportError.invalidFileFormat
        }
        
        let data: Data
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } else {
            data = try Data(contentsOf: url)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let templateDTO: TemplateDTO
        do {
            templateDTO = try decoder.decode(TemplateDTO.self, from: data)
        } catch {
            throw ImportError.decodingFailed(error)
        }
        
        return try createTemplate(from: templateDTO)
    }
    
    // MARK: - Private Export Helpers
    
    private func exportToFile<T: Encodable>(_ object: T, filename: String, extension ext: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(object) else {
            os_log("WorkoutSharingService: Failed to encode object", type: .error)
            return nil
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("\(filename).\(ext)")
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            os_log("WorkoutSharingService: Failed to write file: %@", type: .error, error.localizedDescription)
            return nil
        }
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        return sanitized.isEmpty ? "Shared" : sanitized
    }
    
    // MARK: - Private Import Helpers
    
    private func createWorkout(from dto: WorkoutDTO) throws -> Workout {
        let workout = database.newWorkout(
            name: dto.name ?? "",
            date: dto.date ?? Date(),
            setGroups: []
        )
        workout.endDate = dto.endDate ?? Date()
        
        // Flag workout as temporary until user confirms
        database.flagAsTemporary(workout)
        
        // Create set groups
        for setGroupDTO in dto.setGroups {
            let exercise = try findOrCreateExercise(from: setGroupDTO.exercise)
            let secondaryExercise = try setGroupDTO.secondaryExercise.map { try findOrCreateExercise(from: $0) }
            
            let setGroup = database.newWorkoutSetGroup(
                sets: [],
                createFirstSetAutomatically: false,
                exercise: exercise,
                workout: workout
            )
            
            if let secondary = secondaryExercise {
                setGroup.secondaryExercise = secondary
            }
            
            // Create sets
            for setDTO in setGroupDTO.sets {
                switch setDTO.type ?? .standard {
                case .standard:
                    database.newStandardSet(
                        repetitions: setDTO.repetitions ?? 0,
                        weight: setDTO.weight ?? 0,
                        setGroup: setGroup
                    )
                case .superSet:
                    database.newSuperSet(
                        repetitionsFirstExercise: setDTO.repetitionsFirstExercise ?? 0,
                        repetitionsSecondExercise: setDTO.repetitionsSecondExercise ?? 0,
                        weightFirstExercise: setDTO.weightFirstExercise ?? 0,
                        weightSecondExercise: setDTO.weightSecondExercise ?? 0,
                        setGroup: setGroup
                    )
                case .dropSet:
                    database.newDropSet(
                        repetitions: setDTO.dropSetRepetitions ?? [0],
                        weights: setDTO.dropSetWeights ?? [0],
                        setGroup: setGroup
                    )
                }
            }
        }
        
        return workout
    }
    
    private func createTemplate(from dto: TemplateDTO) throws -> Template {
        let template = database.newTemplate(name: dto.name, setGroups: [])
        
        // Flag template as temporary until user confirms
        database.flagAsTemporary(template)
        
        // Create set groups
        for setGroupDTO in dto.setGroups {
            let exercise = try findOrCreateExercise(from: setGroupDTO.exercise)
            let secondaryExercise = try setGroupDTO.secondaryExercise.map { try findOrCreateExercise(from: $0) }
            
            let setGroup = database.newTemplateSetGroup(
                createFirstSetAutomatically: false,
                exercise: exercise,
                template: template
            )
            
            if let secondary = secondaryExercise {
                setGroup.secondaryExercise = secondary
            }
            
            // Create sets
            for setDTO in setGroupDTO.sets {
                let effectiveType = setDTO.type ?? .standard
                
                switch effectiveType {
                case .standard:
                    database.newTemplateStandardSet(
                        repetitions: setDTO.repetitions ?? 0,
                        weight: setDTO.weight ?? 0,
                        setGroup: setGroup
                    )
                case .superSet:
                    database.newTemplateSuperSet(
                        repetitionsFirstExercise: setDTO.repetitionsFirstExercise ?? 0,
                        repetitionsSecondExercise: setDTO.repetitionsSecondExercise ?? 0,
                        weightFirstExercise: setDTO.weightFirstExercise ?? 0,
                        weightSecondExercise: setDTO.weightSecondExercise ?? 0,
                        setGroup: setGroup
                    )
                case .dropSet:
                    database.newTemplateDropSet(
                        repetitions: setDTO.dropSetRepetitions ?? [0],
                        weights: setDTO.dropSetWeights ?? [0],
                        templateSetGroup: setGroup
                    )
                }
            }
        }
        
        return template
    }
    
    /// Finds an existing exercise or creates a new one based on the ExerciseDTO
    /// - For default exercises: matches by exact name (localization key)
    /// - For custom exercises: uses fuzzy search, creates new if no close match
    private func findOrCreateExercise(from dto: ExerciseDTO) throws -> Exercise {
        guard let name = dto.name, !name.isEmpty else {
            // Create a new exercise with unknown name
            let exercise = database.newExercise(name: "Unknown", muscleGroup: dto.type)
            database.flagAsTemporary(exercise)
            return exercise
        }
        
        // Check if it's a default exercise (name starts with "_default.")
        let isDefault = dto.isDefaultExercise ?? name.hasPrefix("_default.")
        
        if isDefault {
            // For default exercises, find exact match by name (localization key)
            if let existingExercise = findExerciseByName(name) {
                return existingExercise
            }
            // If not found, the user might not have this default exercise yet
            // This shouldn't happen normally, but create as custom fallback
            let exercise = database.newExercise(name: name, muscleGroup: dto.type)
            database.flagAsTemporary(exercise)
            return exercise
        } else {
            // For custom exercises, try fuzzy matching
            if let matchedExercise = findSimilarExercise(name: name, muscleGroup: dto.type) {
                return matchedExercise
            }
            // No close match found, create new exercise
            let exercise = database.newExercise(name: name, muscleGroup: dto.type)
            database.flagAsTemporary(exercise)
            return exercise
        }
    }
    
    private func findExerciseByName(_ name: String) -> Exercise? {
        let fetchRequest = Exercise.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        fetchRequest.fetchLimit = 1
        
        do {
            let results = try database.context.fetch(fetchRequest)
            return results.first
        } catch {
            os_log("WorkoutSharingService: Failed to fetch exercise: %@", type: .error, error.localizedDescription)
            return nil
        }
    }
    
    private func findSimilarExercise(name: String, muscleGroup: MuscleGroup?) -> Exercise? {
        // Fetch all custom exercises (not default ones)
        let fetchRequest = Exercise.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "NOT (name BEGINSWITH %@)", "_default.")
        
        do {
            let allExercises = try database.context.fetch(fetchRequest)
            
            // Use fuzzy search to find similar exercises
            let matches = fuzzySearchService.searchExercises(name, in: allExercises)
            
            // Check if the top match is close enough
            // FuzzySearchService returns results sorted by relevance
            if let topMatch = matches.first {
                // Additional check: prefer same muscle group
                if muscleGroup != nil && topMatch.muscleGroup == muscleGroup {
                    return topMatch
                }
                // If muscle groups don't match but name is very similar, still use it
                // This is handled by the fuzzy search threshold
                return topMatch
            }
            
            return nil
        } catch {
            os_log("WorkoutSharingService: Failed to fetch exercises for matching: %@", type: .error, error.localizedDescription)
            return nil
        }
    }
}

// MARK: - UTType Extensions

extension UTType {
    static let logitWorkout = UTType(exportedAs: "com.logit.workout")
    static let logitTemplate = UTType(exportedAs: "com.logit.template")
}
