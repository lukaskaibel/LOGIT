//
//  DatabaseRollbackTests.swift
//  LOGITTests
//
//  Regression tests for the Cancel flows of the workout and template editors: the synchronous
//  rollback itself, and — from `discardEditorChanges` on — what has to happen when the rollback
//  cannot help because something already saved the shared context (creating an exercise from the
//  editor's tray does exactly that, and so does a Health sync or the recorder autosaving).
//

import XCTest

@testable import LOGIT

final class DatabaseRollbackTests: XCTestCase {
    private var database: Database!

    override func setUp() {
        super.setUp()
        // Unseeded throwaway store: these tests count the rows that are left, so the curated
        // preview dataset `isPreview: true` seeds would drown out what they create themselves.
        database = Database(inMemory: true)
        // The temporary flag list lives in UserDefaults, so it outlives each test's store. Cancel no
        // longer clears the whole list, so start every test from an empty one.
        UserDefaults.standard.removeObject(forKey: "temporaryObjectIds")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "temporaryObjectIds")
        database = nil
        super.tearDown()
    }

    func testDiscardUnsavedChanges_rollsBackTemplateNameSynchronously() {
        let template = database.newTemplate(name: "Original Name")
        database.save()
        drainContext()

        template.name = "Edited Name"
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(template.name, "Original Name", "Template name should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackTemplateSetGroupsSynchronously() {
        let exercise = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let template = database.newTemplate(name: "My Template")
        database.save()
        drainContext()

        XCTAssertEqual(template.setGroups.count, 0, "Precondition: template should start with no set groups")

        _ = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise, template: template)
        XCTAssertEqual(template.setGroups.count, 1, "Precondition: edit should be visible before rollback")
        XCTAssertTrue(database.context.hasChanges, "Precondition: adding a set group should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(template.setGroups.count, 0, "Template set groups should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackWorkoutNameSynchronously() {
        let workout = database.newWorkout(name: "Original Workout")
        database.save()
        drainContext()

        workout.name = "Edited Workout"
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(workout.name, "Original Workout", "Workout name should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackWorkoutSetGroupsSynchronously() {
        let exercise = database.newExercise(name: "Deadlift", muscleGroup: .back)
        let workout = database.newWorkout(name: "My Workout")
        database.save()
        drainContext()

        XCTAssertEqual(workout.setGroups.count, 0, "Precondition: workout should start with no set groups")

        _ = database.newWorkoutSetGroup(createFirstSetAutomatically: false, exercise: exercise, workout: workout)
        XCTAssertEqual(workout.setGroups.count, 1, "Precondition: edit should be visible before rollback")
        XCTAssertTrue(database.context.hasChanges, "Precondition: adding a set group should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(workout.setGroups.count, 0, "Workout set groups should revert immediately after rollback")
    }

    func testDiscardUnsavedChanges_rollsBackExerciseFieldsSynchronously() {
        let exercise = database.newExercise(name: "Original Exercise", muscleGroup: .chest)
        database.save()
        drainContext()

        exercise.name = "Edited Exercise"
        exercise.muscleGroup = .back
        XCTAssertTrue(database.context.hasChanges, "Precondition: editing should mark context dirty")

        database.discardUnsavedChanges()

        XCTAssertFalse(database.context.hasChanges, "Rollback should clear pending changes")
        XCTAssertEqual(exercise.name, "Original Exercise", "Exercise name should revert immediately after rollback")
        XCTAssertEqual(exercise.muscleGroup, .chest, "Exercise muscle group should revert immediately after rollback")
    }

    // MARK: - When a save beat the rollback to it

    /// History → + → create an exercise from the tray → Cancel. `ExerciseEditScreen` saves so the
    /// new exercise outlives its sheet, and that save commits the half-built workout too, which
    /// leaves the rollback nothing to undo. Cancel has to delete the workout for real.
    func testDiscardEditorChanges_deletesNewWorkoutThatWasSavedByANestedEditor() {
        let workout = database.newWorkout(name: "")
        _ = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true,
            exercise: database.newExercise(name: "Brand New Lift", muscleGroup: .chest),
            workout: workout
        )
        // Stands in for the exercise editor's save: it commits everything pending, workout included.
        database.context.performAndWait { try? database.context.save() }
        XCTAssertFalse(database.context.hasChanges, "Precondition: the nested save left nothing pending")

        database.discardEditorChanges(to: workout, wasAddedInEditor: true, setGroupsAddedInEditor: [])
        drainContext()

        XCTAssertTrue(workout.isDeleted || workout.managedObjectContext == nil,
                      "A cancelled new workout must not survive a save that beat the rollback")
        let remaining = database.fetch(Workout.self) as? [Workout] ?? []
        XCTAssertTrue(remaining.isEmpty, "Cancelled workout was written to history anyway")
    }

    /// The exercise the user created along the way is theirs — it belongs to the library, not to the
    /// workout, so cancelling the workout must not take it back.
    func testDiscardEditorChanges_keepsAnExerciseCreatedWhileBuildingTheWorkout() {
        let exercise = database.newExercise(name: "Brand New Lift", muscleGroup: .chest)
        let workout = database.newWorkout(name: "")
        _ = database.newWorkoutSetGroup(createFirstSetAutomatically: true, exercise: exercise, workout: workout)
        database.context.performAndWait { try? database.context.save() }

        database.discardEditorChanges(to: workout, wasAddedInEditor: true, setGroupsAddedInEditor: [])
        drainContext()

        XCTAssertFalse(exercise.isDeleted, "The new exercise belongs to the library, not to the cancelled workout")
        let exercises = database.fetch(Exercise.self) as? [Exercise] ?? []
        XCTAssertTrue(exercises.contains(exercise), "The new exercise should still be in the library")
    }

    /// Editing an existing workout: only the set groups added in this session go back, and the
    /// workout itself — a real entry in the user's history — is never touched.
    func testDiscardEditorChanges_removesOnlySetGroupsAddedWhileEditingAnExistingWorkout() {
        let benchpress = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let deadlift = database.newExercise(name: "Deadlift", muscleGroup: .back)
        let workout = database.newWorkout(name: "Leg Day")
        _ = database.newWorkoutSetGroup(createFirstSetAutomatically: true, exercise: benchpress, workout: workout)
        database.save()
        drainContext()

        let orderOnOpen = workout.setGroups.compactMap { $0.id }
        XCTAssertEqual(orderOnOpen.count, 1, "Precondition: the workout starts with one set group")

        let addedID = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true, exercise: deadlift, workout: workout
        ).id!
        database.context.performAndWait { try? database.context.save() }
        XCTAssertEqual(workout.setGroups.count, 2, "Precondition: the nested save committed the added set group")

        database.discardEditorChanges(
            to: workout, wasAddedInEditor: false, setGroupsAddedInEditor: [addedID]
        )
        drainContext()

        XCTAssertFalse(workout.isDeleted, "An existing workout must survive its editor's Cancel")
        XCTAssertEqual(workout.setGroups.compactMap { $0.id }, orderOnOpen,
                       "Cancel should leave exactly the set groups the editor opened with")
    }

    /// A set group that arrives some other way while the editor is open — through iCloud from
    /// another device, say — is not the editor's to take back. Cancel used to delete everything that
    /// wasn't there on open, which took such a group, and its sets, with it.
    func testDiscardEditorChanges_keepsASetGroupTheEditorDidNotAdd() {
        let benchpress = database.newExercise(name: "Benchpress", muscleGroup: .chest)
        let deadlift = database.newExercise(name: "Deadlift", muscleGroup: .back)
        let squat = database.newExercise(name: "Squat", muscleGroup: .legs)
        let workout = database.newWorkout(name: "Leg Day")
        _ = database.newWorkoutSetGroup(createFirstSetAutomatically: true, exercise: benchpress, workout: workout)
        database.save()
        drainContext()

        // Read up front: a deleted object's attributes read as nil.
        let addedID = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true, exercise: deadlift, workout: workout
        ).id!
        // Stands in for a group synced in from another device while the editor is open.
        let syncedID = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true, exercise: squat, workout: workout
        ).id!
        database.context.performAndWait { try? database.context.save() }

        database.discardEditorChanges(
            to: workout, wasAddedInEditor: false, setGroupsAddedInEditor: [addedID]
        )
        drainContext()

        let remaining = Set(workout.setGroups.compactMap { $0.id })
        XCTAssertFalse(remaining.contains(addedID), "The group this editor added should go")
        XCTAssertTrue(remaining.contains(syncedID), "A group the editor didn't add must stay")
        XCTAssertEqual(remaining.count, 2)
    }

    /// The same for templates — cancelling a new one must not leave an untitled template behind.
    /// A template built in the editor is flagged temporary the moment it is created, which is how
    /// Cancel finds it again once a save has put it out of the rollback's reach.
    func testDiscardEditorChanges_deletesNewTemplateThatWasSavedByANestedEditor() {
        let template = database.newTemplate(name: "")
        database.flagAsTemporary(template)
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: database.newExercise(name: "Brand New Lift", muscleGroup: .chest),
            template: template
        )
        database.context.performAndWait { try? database.context.save() }

        database.discardEditorChanges(to: template, wasAddedInEditor: true, setGroupsAddedInEditor: [])
        drainContext()

        let remaining = database.fetch(Template.self) as? [Template] ?? []
        XCTAssertTrue(remaining.isEmpty, "Cancelled template was written to the library anyway")
    }

    /// An import flags the exercises it brought in as temporary alongside the template, so
    /// cancelling has to take those with it rather than leaving them in the user's library.
    func testDiscardEditorChanges_removesTemporaryExercisesAlongWithACancelledTemplate() {
        let importedExercise = database.newExercise(name: "Imported Lift", muscleGroup: .chest)
        let template = database.newTemplate(name: "")
        database.flagAsTemporary(template)
        database.flagAsTemporary(importedExercise)
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: importedExercise,
            template: template
        )
        database.context.performAndWait { try? database.context.save() }

        database.discardEditorChanges(to: template, wasAddedInEditor: true, setGroupsAddedInEditor: [])
        drainContext()

        let exercises = database.fetch(Exercise.self) as? [Exercise] ?? []
        XCTAssertFalse(
            exercises.contains(importedExercise),
            "An imported exercise must not outlive the template it came in with"
        )
    }

    /// The temporary flag list is shared. A workout started from a scanned template keeps that
    /// template and the exercises the scan invented flagged until the workout ends — so cancelling
    /// an unrelated new template (built while that workout is minimized) must take only its own
    /// rows, never the running workout's.
    func testDiscardEditorChanges_cancellingANewTemplateSparesARunningWorkoutsTemporaryObjects() {
        let scannedExercise = database.newExercise(name: "Scanned Lift", muscleGroup: .back)
        let scannedTemplate = database.newTemplate(name: "Scanned")
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: scannedExercise,
            template: scannedTemplate
        )
        let runningWorkout = database.newWorkout(name: "Scanned")
        _ = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true,
            exercise: scannedExercise,
            workout: runningWorkout
        )
        database.context.performAndWait { try? database.context.save() }
        database.flagAsTemporary(scannedExercise)
        database.flagAsTemporary(scannedTemplate)

        let newTemplate = database.newTemplate(name: "")
        database.flagAsTemporary(newTemplate)
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: database.newExercise(name: "Brand New Lift", muscleGroup: .chest),
            template: newTemplate
        )
        database.context.performAndWait { try? database.context.save() }

        database.discardEditorChanges(to: newTemplate, wasAddedInEditor: true, setGroupOrderOnOpen: [])
        drainContext()

        let templates = database.fetch(Template.self) as? [Template] ?? []
        let exercises = database.fetch(Exercise.self) as? [Exercise] ?? []
        XCTAssertFalse(templates.contains(newTemplate), "The cancelled template should be gone")
        XCTAssertTrue(templates.contains(scannedTemplate), "Cancel deleted the running workout's scanned template")
        XCTAssertTrue(exercises.contains(scannedExercise), "Cancel deleted the running workout's scanned exercise")
        XCTAssertTrue(
            database.isTemporaryObject(scannedExercise),
            "The running workout's exercise should stay flagged for the recorder to settle"
        )
        XCTAssertEqual(runningWorkout.setGroups.first?.exercise, scannedExercise)
    }

    /// An imported exercise the user also picked into another template belongs to that template
    /// now, so cancelling the import must leave it in the library.
    func testDiscardEditorChanges_keepsATemporaryExerciseAnotherTemplateUses() {
        let importedExercise = database.newExercise(name: "Imported Lift", muscleGroup: .chest)
        let otherTemplate = database.newTemplate(name: "Push")
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: importedExercise,
            template: otherTemplate
        )
        let template = database.newTemplate(name: "")
        _ = database.newTemplateSetGroup(
            createFirstSetAutomatically: true,
            exercise: importedExercise,
            template: template
        )
        database.context.performAndWait { try? database.context.save() }
        database.flagAsTemporary(template)
        database.flagAsTemporary(importedExercise)

        database.discardEditorChanges(to: template, wasAddedInEditor: true, setGroupOrderOnOpen: [])
        drainContext()

        let exercises = database.fetch(Exercise.self) as? [Exercise] ?? []
        XCTAssertTrue(exercises.contains(importedExercise), "Another template still trains this exercise")
        XCTAssertEqual(otherTemplate.setGroups.first?.exercise, importedExercise)
    }

    /// Nothing saved in between: the rollback alone still does the whole job, and Cancel must not
    /// go looking for rows to delete afterwards.
    func testDiscardEditorChanges_leavesUnsavedNewWorkoutToTheRollback() {
        let workout = database.newWorkout(name: "")
        _ = database.newWorkoutSetGroup(
            createFirstSetAutomatically: true,
            exercise: database.newExercise(name: "Benchpress", muscleGroup: .chest),
            workout: workout
        )

        database.discardEditorChanges(to: workout, wasAddedInEditor: true, setGroupsAddedInEditor: [])
        drainContext()

        let remaining = database.fetch(Workout.self) as? [Workout] ?? []
        XCTAssertTrue(remaining.isEmpty, "The rollback alone should have taken the workout back")
    }

    // MARK: - Helpers

    /// `delete` and `save` hop through the context's queue, so a test that asserts right after them
    /// can read the state from before. This waits for that queue to come back around.
    private func drainContext() {
        let drained = expectation(description: "context queue drained")
        database.context.perform { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }
}
