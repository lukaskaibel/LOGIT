//
//  MuscleTargetSplitStore.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Combine
import Foundation

/// Persists the user's `MuscleTargetSplit` as JSON in `UserDefaults` (mirrors the pinned-exercise
/// tile pattern — no Core Data, since CloudKit is additive-only). An `ObservableObject` so the
/// target-split editor's edits live-update the Muscle Groups overview and the Summary Muscle Balance
/// tile that read off it. Injected from `LOGITApp`/`PreviewEnvironmentObjects`.
final class MuscleTargetSplitStore: ObservableObject {
    private static let storageKey = "muscleTargetSplit"

    private let defaults: UserDefaults

    /// The current target split. Published so every consumer re-renders when the editor commits a
    /// change.
    @Published private(set) var split: MuscleTargetSplit

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        split = Self.load(from: defaults) ?? .default
    }

    // MARK: - Reads

    func target(for muscleGroup: MuscleGroup) -> Int {
        split.percentage(for: muscleGroup)
    }

    // MARK: - Mutations

    func setTarget(_ value: Int, for muscleGroup: MuscleGroup) {
        var updated = split
        updated.setPercentage(value, for: muscleGroup)
        split = updated
        persist()
    }

    func apply(preset: MuscleTargetPreset) {
        split = preset.split
        persist()
    }

    func resetToDefault() {
        split = .default
        persist()
    }

    // MARK: - Disk

    private func persist() {
        guard let data = try? JSONEncoder().encode(split) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> MuscleTargetSplit? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MuscleTargetSplit.self, from: data)
    }
}
