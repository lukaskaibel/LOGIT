//
//  DataArchiveService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.08.26.
//

import CoreData
import Foundation
import OSLog

/// A complete, plain-JSON copy of everything the user has logged — the one copy of their training
/// history that does not live in CloudKit.
///
/// Every other copy is a mirror of the same iCloud records: a bad sync, a cascade, or an iCloud
/// sign-out (which makes Core Data purge the local store outright) takes all of them at once. This
/// file is the thing that survives that. It is therefore written to be read *without* the app:
/// plain JSON, no proprietary container, ids and units spelled out, so it can be inspected in a
/// text editor and its rows put back by hand if it ever comes to that.
///
/// Two rules make it a backup rather than a snapshot of what the UI happens to show:
/// - **Ids are preserved.** Sharing DTOs deliberately drop them and re-match exercises by name;
///   an archive keeps them so a restore can be exact and idempotent.
/// - **It exports the relationship, not just the ordered list.** Ordered to-manys are mirrored in
///   hand-maintained `[UUID]` lists, and a list that has drifted hides members from the entire app
///   (see `Database+RelationshipRepair`). The archive writes the ordered members first, then
///   appends anything the relationship holds that the list forgot — a backup must never inherit a
///   display bug.
struct LOGITArchive: Codable {
    /// Bumped to 2 when durations became milliseconds and distances millimeters, so an
    /// archive read months from now is never ambiguous about which unit its numbers are in.
    static let currentFormatVersion = 2

    let formatVersion: Int
    let exportedAt: Date
    let appVersion: String
    /// Spelled out so the file is self-describing years from now, in any editor.
    let units: String

    let exercises: [ArchivedExercise]
    let workouts: [ArchivedWorkout]
    let templates: [ArchivedTemplate]
    let measurements: [ArchivedMeasurement]
}

struct ArchivedExercise: Codable {
    let id: UUID?
    let name: String?
    let muscleGroup: String?
    let measurementType: String
    let distanceStyle: String?
    /// "faster" on exercises whose clock improves downward; absent otherwise. Optional so archives
    /// written before time goals existed still decode.
    let durationGoal: String?
    let isDefaultExercise: Bool
}

struct ArchivedWorkout: Codable {
    let id: UUID?
    let name: String?
    let date: Date?
    let endDate: Date?
    let templateId: UUID?
    /// The session note and effort rating. Optional, so an archive written before they existed
    /// still decodes — and unlike a shared workout, a personal archive keeps them: this file is
    /// the user's own backup, not something handed to another person.
    let note: String?
    let effortScore: Int?
    let setGroups: [ArchivedSetGroup]
}

struct ArchivedSetGroup: Codable {
    let id: UUID?
    /// Primary exercise first, then the super set's second — the group's own exercise order.
    let exerciseIds: [UUID]
    let setType: String
    let note: String?
    let sets: [ArchivedSet]
}

struct ArchivedSet: Codable {
    let id: UUID?
    let restDuration: Int
    let entries: [ArchivedEntry]
}

/// One performed entry. Since model v8 these are the truth for what was logged; legacy-shaped sets
/// are exported through the same derivation the app reads them with, so an unswept set archives
/// identically to its backfilled self.
struct ArchivedEntry: Codable {
    let order: Int
    let measurementType: String
    let repetitions: Int
    let weight: Int
    /// Milliseconds, and millimeters — see the archive's `units`.
    let duration: Int
    let distance: Int
    let exerciseId: UUID?
}

struct ArchivedTemplate: Codable {
    let id: UUID?
    let name: String?
    let descriptionText: String?
    let creationDate: Date?
    let setGroups: [ArchivedSetGroup]
}

struct ArchivedMeasurement: Codable {
    let id: UUID?
    let type: String?
    let value: Int
    let date: Date?
}

final class DataArchiveService {

    /// What the export contains, for the confirmation the user sees before sharing.
    struct Summary: Equatable {
        let workouts: Int
        let exercises: Int
        let templates: Int
        let measurements: Int
        let sets: Int
    }

    private let database: Database

    init(database: Database) {
        self.database = database
    }

    // MARK: - Export

    /// Builds the archive and writes it to a dated file in the temporary directory, ready to hand
    /// to the share sheet. Reads happen on the context's queue — every relationship traversal here
    /// can fire a fault.
    func exportArchive() throws -> (url: URL, summary: Summary) {
        var archive: LOGITArchive!
        var summary: Summary!
        database.context.performAndWait {
            archive = makeArchive()
            summary = Summary(
                workouts: archive.workouts.count,
                exercises: archive.exercises.count,
                templates: archive.templates.count,
                measurements: archive.measurements.count,
                sets: archive.workouts.reduce(0) { $0 + $1.setGroups.reduce(0) { $0 + $1.sets.count } }
            )
        }

        let encoder = JSONEncoder()
        // Readable in a text editor, and stable line-by-line so two exports can be diffed.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.filename(for: archive.exportedAt))
        try data.write(to: url, options: .atomic)
        os_log(
            "DataArchiveService: Exported %d workouts, %d exercises (%d bytes)",
            type: .info, summary.workouts, summary.exercises, data.count
        )
        return (url, summary)
    }

    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "LOGIT-Backup-\(formatter.string(from: date)).json"
    }

    // MARK: - Archive Building

    /// Must run on the context's queue.
    private func makeArchive() -> LOGITArchive {
        let exercises = (database.fetch(Exercise.self) as? [Exercise]) ?? []
        let workouts = (database.fetch(Workout.self) as? [Workout]) ?? []
        let templates = (database.fetch(Template.self) as? [Template]) ?? []
        let measurements = (database.fetch(MeasurementEntry.self) as? [MeasurementEntry]) ?? []

        return LOGITArchive(
            formatVersion: LOGITArchive.currentFormatVersion,
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            units: "weights in grams, distances in millimeters, durations in milliseconds, dates in ISO 8601",
            exercises: exercises.map { exercise in
                ArchivedExercise(
                    id: exercise.id,
                    name: exercise.name,
                    muscleGroup: exercise.muscleGroup?.rawValue,
                    measurementType: exercise.measurementType.rawValue,
                    distanceStyle: exercise.distanceStyleOverride?.rawValue,
                    durationGoal: exercise.durationGoalString,
                    isDefaultExercise: exercise.isDefaultExercise
                )
            },
            workouts: workouts
                .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                .map { workout in
                    ArchivedWorkout(
                        id: workout.id,
                        name: workout.name,
                        date: workout.date,
                        endDate: workout.endDate,
                        templateId: workout.template?.id,
                        note: workout.note,
                        effortScore: workout.effortScore,
                        setGroups: completeMembers(
                            ordered: workout.setGroups, relationship: workout.setGroups_
                        )
                        .map(archived(setGroup:))
                    )
                },
            templates: templates.map { template in
                ArchivedTemplate(
                    id: template.id,
                    name: template.name,
                    descriptionText: template.descriptionText,
                    creationDate: template.creationDate,
                    setGroups: completeMembers(
                        ordered: template.setGroups, relationship: template.setGroups_
                    )
                    .map(archived(templateSetGroup:))
                )
            },
            measurements: measurements.map { entry in
                ArchivedMeasurement(
                    id: entry.id,
                    type: entry.type?.rawValue,
                    value: entry.value,
                    date: entry.date
                )
            }
        )
    }

    private func archived(setGroup: WorkoutSetGroup) -> ArchivedSetGroup {
        ArchivedSetGroup(
            id: setGroup.id,
            exerciseIds: exerciseIds(
                ordered: [setGroup.exercise, setGroup.secondaryExercise],
                relationship: setGroup.exercises_
            ),
            setType: setGroup.setType.rawValue,
            note: setGroup.note,
            sets: completeMembers(ordered: setGroup.sets, relationship: setGroup.sets_)
                .map { workoutSet in
                    ArchivedSet(
                        id: workoutSet.id,
                        restDuration: workoutSet.restDurationSeconds,
                        entries: workoutSet.entryValues.map(archived(entryValues:))
                    )
                }
        )
    }

    private func archived(templateSetGroup: TemplateSetGroup) -> ArchivedSetGroup {
        ArchivedSetGroup(
            id: templateSetGroup.id,
            exerciseIds: exerciseIds(
                ordered: [templateSetGroup.exercise, templateSetGroup.secondaryExercise],
                relationship: templateSetGroup.exercises_
            ),
            setType: templateSetGroup.setType.rawValue,
            note: nil,
            sets: completeMembers(
                ordered: templateSetGroup.sets, relationship: templateSetGroup.sets_
            )
            .map { templateSet in
                ArchivedSet(
                    id: templateSet.id,
                    restDuration: templateSet.restDurationSeconds,
                    entries: templateSet.entryValues.map(archived(entryValues:))
                )
            }
        )
    }

    private func archived(entryValues values: SetEntryValues) -> ArchivedEntry {
        ArchivedEntry(
            order: Int(values.order),
            measurementType: values.type.rawValue,
            repetitions: Int(values.repetitions),
            weight: Int(values.weight),
            duration: Int(values.durationMs),
            distance: Int(values.distanceMm),
            exerciseId: values.exercise?.id
        )
    }

    // MARK: - Completeness

    /// The ordered members, followed by anything the relationship holds that the order list
    /// forgot. See the type's note: the archive must not inherit an order-list drift.
    private func completeMembers<Member: UUIDOrderable>(
        ordered: [Member], relationship: NSSet?
    ) -> [Member] {
        let all = (relationship?.allObjects as? [Member]) ?? []
        guard all.count > ordered.count else { return ordered }
        let listed = Set(ordered.compactMap { $0.id })
        let missing = all
            .filter { member in member.id.map { !listed.contains($0) } ?? true }
            .sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        return ordered + missing
    }

    private func exerciseIds(ordered: [Exercise?], relationship: NSSet?) -> [UUID] {
        completeMembers(ordered: ordered.compactMap { $0 }, relationship: relationship)
            .compactMap { $0.id }
    }
}
