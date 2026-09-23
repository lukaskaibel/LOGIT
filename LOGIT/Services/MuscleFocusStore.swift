//
//  MuscleFocusStore.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Combine
import Foundation

/// Persists the user's `MuscleFocus` — a weekly set target per muscle group — as JSON in
/// `UserDefaults` (mirrors the pinned-exercise tile pattern — no Core Data, since CloudKit is
/// additive-only). An `ObservableObject` so the focus picker, the target editor and the popover on
/// Muscle Groups live-update every surface that reads the balance. Injected from
/// `LOGITApp`/`PreviewEnvironmentObjects`.
///
/// It also watches the weekly workout goal, because targets are sized for one. Until the user chooses
/// a focus, the default follows the goal on its own — a new user is always measured against a week
/// they can actually train. Once chosen, the targets stay put when the goal changes, and
/// `suggestedResizeGoal` says when the Muscle Groups screen should offer to rescale them.
final class MuscleFocusStore: ObservableObject {
    static let storageKey = "muscleFocus"
    /// Where the original percent editor kept its split. Read once, when there is no focus yet, so an
    /// existing user's targets carry over; never written again.
    static let legacyStorageKey = "muscleTargetSplit"
    /// The weekly workout goal's own key — `@AppStorage("workoutPerWeekTarget")` on the goal screens,
    /// where -1 means none is set.
    static let workoutGoalKey = "workoutPerWeekTarget"

    private let defaults: UserDefaults
    private var goalObservation: AnyCancellable?

    /// The current focus. Published so every consumer re-renders on each change.
    @Published private(set) var focus: MuscleFocus

    /// Whether the user has ever set a focus themselves, as opposed to running on the default. Until
    /// they have, the Balance tile asks for one instead of recommending anything, and Muscle Groups
    /// leads with the same request. A split carried over from the old percent editor counts: someone
    /// who tuned percentages has made that choice.
    ///
    /// Kept in memory once known rather than re-read from disk, because a scenario launch pins reads
    /// of the storage key for the whole session and a re-read would never see the write.
    @Published private(set) var hasChosenFocus: Bool

    /// The user's weekly workout goal, nil while none is set.
    @Published private(set) var workoutGoal: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let goal = Self.readWorkoutGoal(from: defaults)
        let stored = Self.load(from: defaults)
        let migrated = stored == nil ? Self.migrateLegacySplit(from: defaults, sizedFor: goal) : nil
        workoutGoal = goal
        focus = stored ?? migrated
            ?? MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: goal ?? MuscleFocus.baseWorkoutsPerWeek)
        hasChosenFocus = stored != nil || migrated != nil
        // `@AppStorage` writes post this in-process, whichever screen changed the goal. Hopped to the
        // main queue because it is posted on the writing thread and this object publishes to views.
        goalObservation = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadWorkoutGoal() }
    }

    // MARK: - Reads

    /// The week to size a preset for right now: the user's weekly goal, or the base week while none
    /// is set.
    var workoutsPerWeekToSizeFor: Int {
        workoutGoal ?? MuscleFocus.baseWorkoutsPerWeek
    }

    /// The weekly goal the Muscle Groups screen should offer to rescale the targets to — nil when
    /// there is nothing to offer: no focus chosen yet (the default already follows the goal), no goal,
    /// the goal the targets were sized for, or one the user already kept them for.
    var suggestedResizeGoal: Int? {
        guard hasChosenFocus, focus.suggestsResize(forWorkoutsPerWeek: workoutGoal) else { return nil }
        return workoutGoal
    }

    /// What choosing `preset` would put in force — and so what the picker's tile for it shows, so the
    /// tile and the commit can't disagree.
    ///
    /// **The preset already in force is the targets in force**, whatever goal they were sized for;
    /// every other preset is sized for the goal as it stands. `matchingPreset` recognises Full Body
    /// sized for 3 as Full Body under a goal of 5, which is what lets "Not Now" keep it. Drawn and
    /// re-applied at the current goal instead, its tile was checked but showed goal-5 numbers, and
    /// confirming it silently did the rescale the user had just declined. Rescaling stays where it is
    /// offered: `resizeToWorkoutGoal`, the Muscle Groups card's "Update Targets".
    func focusOnChoosing(_ preset: MuscleFocusPreset) -> MuscleFocus {
        if hasChosenFocus, focus.matchingPreset == preset {
            return focus
        }
        return preset.focus(forWorkoutsPerWeek: workoutsPerWeekToSizeFor)
    }

    // MARK: - Mutations

    /// Takes over a preset — sized for the current weekly goal, or, when it is the preset already in
    /// force, kept as it is (see `focusOnChoosing`). Confirming it is still a choice and still commits.
    func apply(preset: MuscleFocusPreset) {
        commit(focusOnChoosing(preset))
    }

    /// Takes over targets set in the editor as a whole.
    func apply(focus updated: MuscleFocus) {
        commit(updated)
    }

    /// Sets a group's weekly set target (0 leaves the group out of the focus).
    func setTarget(_ value: Int, for muscleGroup: MuscleGroup) {
        var updated = focus
        updated.setTarget(value, for: muscleGroup)
        commit(updated)
    }

    /// Rescales every target to the current weekly goal — the offer's "Update Targets".
    func resizeToWorkoutGoal() {
        guard let goal = workoutGoal else { return }
        commit(focus.resized(forWorkoutsPerWeek: goal))
    }

    /// Keeps the targets as they are for the current weekly goal — the offer's "Not Now". It comes
    /// back only if the goal changes again.
    func keepTargetsForWorkoutGoal() {
        guard let goal = workoutGoal else { return }
        var updated = focus
        updated.keep(forWorkoutsPerWeek: goal)
        commit(updated)
    }

    /// Every mutation is a choice, even one that changes nothing: picking Full Body while running on
    /// the Full Body default is the user settling on it, and it is persisted so the next launch
    /// remembers that rather than asking again.
    private func commit(_ updated: MuscleFocus) {
        if updated != focus {
            focus = updated
        }
        hasChosenFocus = true
        persist()
    }

    /// Re-reads the weekly goal. Until a focus is chosen, the default is re-sized to it.
    func reloadWorkoutGoal() {
        let goal = Self.readWorkoutGoal(from: defaults)
        guard goal != workoutGoal else { return }
        workoutGoal = goal
        if !hasChosenFocus {
            focus = MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: workoutsPerWeekToSizeFor)
        }
    }

    // MARK: - Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(focus) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func readWorkoutGoal(from defaults: UserDefaults) -> Int? {
        let value = defaults.integer(forKey: workoutGoalKey)
        return value > 0 ? value : nil
    }

    private static func load(from defaults: UserDefaults) -> MuscleFocus? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MuscleFocus.self, from: data)
    }

    /// The split from the percent editor as weekly targets, sized for the weekly goal the user has
    /// now. A share says nothing about how many workouts it was meant for; read as sized for the base
    /// week, a user with a goal of 5 came out of the update a third short of every target and was
    /// offered to "update" them for a goal of 3 they never set.
    private static func migrateLegacySplit(from defaults: UserDefaults, sizedFor goal: Int?) -> MuscleFocus? {
        guard let data = defaults.data(forKey: legacyStorageKey),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return nil }
        let percentages = raw.reduce(into: [MuscleGroup: Int]()) { result, pair in
            if let group = MuscleGroup(rawValue: pair.key) {
                result[group] = pair.value
            }
        }
        let focus = MuscleFocus(legacyPercentages: percentages)
        guard let goal, goal != focus.workoutsPerWeek else { return focus }
        return focus.resized(forWorkoutsPerWeek: goal)
    }
}
