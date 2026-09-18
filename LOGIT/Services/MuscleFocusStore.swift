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
/// additive-only). An `ObservableObject` so the focus editor's steppers live-update the Muscle Groups
/// overview and the Summary Balance tile that read off it. Injected from
/// `LOGITApp`/`PreviewEnvironmentObjects`.
final class MuscleFocusStore: ObservableObject {
    static let storageKey = "muscleFocus"
    /// Where the original percent editor kept its split. Read once, when there is no focus yet, so an
    /// existing user's targets carry over; never written again.
    static let legacyStorageKey = "muscleTargetSplit"

    private let defaults: UserDefaults

    /// The current focus. Published so every consumer re-renders on each change.
    @Published private(set) var focus: MuscleFocus

    /// Whether the user has ever set a focus themselves, as opposed to running on the default. Drives
    /// the Summary's one-time focus tip and the "Default" caption on Muscle Groups. A split carried
    /// over from the old percent editor counts: someone who tuned percentages has made that choice.
    ///
    /// Kept in memory once known rather than re-read from disk, because a scenario launch pins reads
    /// of the storage key for the whole session and a re-read would never see the write.
    @Published private(set) var hasChosenFocus: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.load(from: defaults)
        let migrated = stored == nil ? Self.migrateLegacySplit(from: defaults) : nil
        focus = stored ?? migrated ?? .default
        hasChosenFocus = stored != nil || migrated != nil
    }

    // MARK: - Mutations

    func apply(preset: MuscleFocusPreset) {
        var updated = focus
        updated.apply(preset)
        commit(updated)
    }

    /// Sets a group's weekly set target (0 leaves the group out of the focus).
    func setTarget(_ value: Int, for muscleGroup: MuscleGroup) {
        var updated = focus
        updated.setTarget(value, for: muscleGroup)
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

    // MARK: - Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(focus) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> MuscleFocus? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MuscleFocus.self, from: data)
    }

    private static func migrateLegacySplit(from defaults: UserDefaults) -> MuscleFocus? {
        guard let data = defaults.data(forKey: legacyStorageKey),
              let raw = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return nil }
        let percentages = raw.reduce(into: [MuscleGroup: Int]()) { result, pair in
            if let group = MuscleGroup(rawValue: pair.key) {
                result[group] = pair.value
            }
        }
        return MuscleFocus(legacyPercentages: percentages)
    }
}
