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
    
    enum ImportError: LocalizedError {
        case invalidFileFormat
        case decodingFailed(Error)
        case exerciseMatchingFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidFileFormat:
                return NSLocalizedString("unsupportedFileType", comment: "")
            case .decodingFailed(let error):
                return String(
                    format: NSLocalizedString("failedToReadFile", comment: ""),
                    error.localizedDescription
                )
            case .exerciseMatchingFailed:
                return NSLocalizedString("failedToMatchExercises", comment: "")
            }
        }
    }
    
    // MARK: - Properties
    
    private let database: Database
    private let fuzzySearchService = FuzzySearchService.shared
    
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
        return exportToFile(dto, filename: sanitizeFilename(workout.name ?? NSLocalizedString("workout", comment: "")), extension: "logitworkout")
    }
    
    /// Exports a template to a shareable .logittemplate file
    /// - Parameter template: The template to export
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportTemplate(_ template: Template) -> URL? {
        let dto = TemplateDTO(from: template)
        return exportToFile(dto, filename: sanitizeFilename(template.resolvedName ?? NSLocalizedString("template", comment: "")), extension: "logittemplate")
    }
    
    /// Exports a workout as a template file
    /// - Parameter workout: The workout to export as template
    /// - Returns: URL to the temporary file, or nil if export failed
    func exportWorkoutAsTemplate(_ workout: Workout) -> URL? {
        // Create a TemplateDTO from the workout data
        let templateDTO = TemplateDTO(
            name: workout.name ?? NSLocalizedString("sharedWorkout", comment: ""),
            setGroups: workout.setGroups.map { workoutSetGroup in
                TemplateSetGroupDTO(
                    exercise: ExerciseDTO(from: workoutSetGroup.exercise),
                    sets: workoutSetGroup.sets.map { workoutSet in
                        // Convert WorkoutSet to TemplateSetDTO (preserving the performed entries)
                        let values = workoutSet.entryValues
                        let entries = values.enumerated().map { index, value in
                            SetEntryDTO(
                                from: value,
                                exerciseIndex: workoutSet is SuperSet ? index : 0
                            )
                        }
                        if workoutSet is SuperSet {
                            return TemplateSetDTO(
                                type: .superSet,
                                restDuration: workoutSet.restDurationSeconds,
                                repetitionsFirstExercise: Int(values.value(at: 0)?.repetitions ?? 0),
                                repetitionsSecondExercise: Int(values.value(at: 1)?.repetitions ?? 0),
                                weightFirstExercise: Int(values.value(at: 0)?.weight ?? 0),
                                weightSecondExercise: Int(values.value(at: 1)?.weight ?? 0),
                                entries: entries
                            )
                        } else if workoutSet is DropSet {
                            return TemplateSetDTO(
                                type: .dropSet,
                                restDuration: workoutSet.restDurationSeconds,
                                dropSetRepetitions: values.map { Int($0.repetitions) },
                                dropSetWeights: values.map { Int($0.weight) },
                                entries: entries
                            )
                        } else {
                            return TemplateSetDTO(
                                repetitions: Int(values.first?.repetitions ?? 0),
                                weight: Int(values.first?.weight ?? 0),
                                type: .standard,
                                restDuration: workoutSet.restDurationSeconds,
                                entries: entries
                            )
                        }
                    },
                    secondaryExercise: workoutSetGroup.secondaryExercise.map { ExerciseDTO(from: $0) },
                    setType: workoutSetGroup.setType.rawValue
                )
            },
            formatVersion: TemplateDTO.formatVersion,
            appStoreURL: "https://apps.apple.com/app/logit-track-your-workouts/id6444813640"
        )
        return exportToFile(templateDTO, filename: sanitizeFilename(workout.name ?? NSLocalizedString("workout", comment: "")), extension: "logittemplate")
    }
    
    // MARK: - Import Methods
    
    /// Imports a workout from a .logitworkout file
    /// Creates the workout and all necessary exercises, flagging new entities as temporary
    /// Safe to call from any thread: file reading and decoding run on the calling
    /// thread, entity creation on the context's queue.
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

        // The viewContext is main-queue-confined, but imports arrive on a
        // background queue (see LOGITApp.handleIncomingFile).
        return try database.context.performAndWait {
            try createWorkout(from: workoutDTO)
        }
    }
    
    /// Imports a template from a .logittemplate file
    /// Creates the template and all necessary exercises, flagging new entities as temporary
    /// Safe to call from any thread: file reading and decoding run on the calling
    /// thread, entity creation on the context's queue.
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

        // The viewContext is main-queue-confined, but imports arrive on a
        // background queue (see LOGITApp.handleIncomingFile).
        return try database.context.performAndWait {
            try createTemplate(from: templateDTO)
        }
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
        return sanitized.isEmpty ? NSLocalizedString("shared", comment: "") : sanitized
    }
    
    // MARK: - Private Import Helpers
    
    private func createWorkout(from dto: WorkoutDTO) throws -> Workout {
        let workout = database.newWorkout(
            name: dto.name ?? "",
            date: dto.date ?? Date(),
            setGroups: []
        )
        workout.endDate = dto.endDate ?? dto.date
        
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
                let workoutSet: WorkoutSet
                switch setDTO.type ?? .standard {
                case .standard:
                    workoutSet = database.newStandardSet(
                        repetitions: setDTO.repetitions ?? 0,
                        weight: setDTO.weight ?? 0,
                        restDuration: setDTO.restDuration ?? 0,
                        setGroup: setGroup
                    )
                case .superSet:
                    workoutSet = database.newSuperSet(
                        repetitionsFirstExercise: setDTO.repetitionsFirstExercise ?? 0,
                        repetitionsSecondExercise: setDTO.repetitionsSecondExercise ?? 0,
                        weightFirstExercise: setDTO.weightFirstExercise ?? 0,
                        weightSecondExercise: setDTO.weightSecondExercise ?? 0,
                        restDuration: setDTO.restDuration ?? 0,
                        setGroup: setGroup
                    )
                case .dropSet:
                    workoutSet = database.newDropSet(
                        repetitions: setDTO.dropSetRepetitions ?? [0],
                        weights: setDTO.dropSetWeights ?? [0],
                        restDuration: setDTO.restDuration ?? 0,
                        setGroup: setGroup
                    )
                }
                applyEntries(setDTO.entries, to: workoutSet)
            }
        }

        return workout
    }

    /// Replaces the legacy-derived entries with the file's version-2 entries (measurement
    /// types, durations). No-op for version-1 files, which carry no entries.
    private func applyEntries(_ entryDTOs: [SetEntryDTO]?, to workoutSet: WorkoutSet) {
        guard let entryDTOs, !entryDTOs.isEmpty else { return }
        workoutSet.removeAllEntries()
        for (index, entryDTO) in entryDTOs.enumerated() {
            workoutSet.insertEntry(
                from: SetEntryValues(
                    type: SetMeasurementType(rawValue: entryDTO.type ?? "") ?? .repsAndWeight,
                    order: Int64(index),
                    repetitions: Int64(entryDTO.repetitions ?? 0),
                    weight: Int64(entryDTO.weight ?? 0),
                    duration: Int64(entryDTO.duration ?? 0),
                    distance: Int64(entryDTO.distance ?? 0),
                    exercise: workoutSet.positionalExercise(
                        forOrder: Int64(entryDTO.exerciseIndex ?? index)
                    )
                )
            )
        }
    }

    private func applyEntries(_ entryDTOs: [SetEntryDTO]?, to templateSet: TemplateSet) {
        guard let entryDTOs, !entryDTOs.isEmpty else { return }
        templateSet.removeAllEntries()
        for (index, entryDTO) in entryDTOs.enumerated() {
            templateSet.insertEntry(
                from: SetEntryValues(
                    type: SetMeasurementType(rawValue: entryDTO.type ?? "") ?? .repsAndWeight,
                    order: Int64(index),
                    repetitions: Int64(entryDTO.repetitions ?? 0),
                    weight: Int64(entryDTO.weight ?? 0),
                    duration: Int64(entryDTO.duration ?? 0),
                    distance: Int64(entryDTO.distance ?? 0),
                    exercise: templateSet.positionalExercise(
                        forOrder: Int64(entryDTO.exerciseIndex ?? index)
                    )
                )
            )
        }
    }
    
    private func createTemplate(from dto: TemplateDTO) throws -> Template {
        let template = database.newTemplate(name: dto.name, setGroups: [])
        template.descriptionText = dto.description
        
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

                let templateSet: TemplateSet
                switch effectiveType {
                case .standard:
                    templateSet = database.newTemplateStandardSet(
                        repetitions: setDTO.repetitions ?? 0,
                        weight: setDTO.weight ?? 0,
                        restDuration: setDTO.restDuration ?? 0,
                        setGroup: setGroup
                    )
                case .superSet:
                    templateSet = database.newTemplateSuperSet(
                        repetitionsFirstExercise: setDTO.repetitionsFirstExercise ?? 0,
                        repetitionsSecondExercise: setDTO.repetitionsSecondExercise ?? 0,
                        weightFirstExercise: setDTO.weightFirstExercise ?? 0,
                        weightSecondExercise: setDTO.weightSecondExercise ?? 0,
                        restDuration: setDTO.restDuration ?? 0,
                        setGroup: setGroup
                    )
                case .dropSet:
                    templateSet = database.newTemplateDropSet(
                        repetitions: setDTO.dropSetRepetitions ?? [0],
                        weights: setDTO.dropSetWeights ?? [0],
                        restDuration: setDTO.restDuration ?? 0,
                        templateSetGroup: setGroup
                    )
                }
                applyEntries(setDTO.entries, to: templateSet)
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
            let exercise = database.newExercise(
                name: NSLocalizedString("unknownExercise", comment: ""),
                muscleGroup: dto.type,
                measurementType: SetMeasurementType(rawValue: dto.measurementType ?? "") ?? .repsAndWeight
            )
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
            let exercise = database.newExercise(
                name: name,
                muscleGroup: dto.type,
                measurementType: SetMeasurementType(rawValue: dto.measurementType ?? "") ?? .repsAndWeight
            )
            database.flagAsTemporary(exercise)
            return exercise
        } else {
            // For custom exercises, try fuzzy matching
            if let matchedExercise = findSimilarExercise(name: name, muscleGroup: dto.type) {
                return matchedExercise
            }
            // No close match found, create new exercise
            let exercise = database.newExercise(
                name: name,
                muscleGroup: dto.type,
                measurementType: SetMeasurementType(rawValue: dto.measurementType ?? "") ?? .repsAndWeight
            )
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
