//
//  MuscleTargetSplit.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

/// The user's target distribution of training across the 8 muscle groups, as whole-percent values
/// summing to 100. Persisted as `[String: Int]` keyed by the muscle-group raw value (see the custom
/// `Codable`) so it stays serializable without a Core Data migration — CloudKit is additive-only, so
/// every new bit of persistence in the redesign is `@AppStorage` JSON. See `MuscleTargetSplitStore`.
struct MuscleTargetSplit: Codable, Equatable {
    /// Whole-percent target for each muscle group. Groups absent from the dictionary read as 0.
    private var percentages: [MuscleGroup: Int]

    init(percentages: [MuscleGroup: Int]) {
        self.percentages = percentages
    }

    /// A muscle group's whole-percent target (0 when absent).
    func percentage(for muscleGroup: MuscleGroup) -> Int {
        percentages[muscleGroup] ?? 0
    }

    /// Sets a group's whole-percent target, clamped to a sensible 0…100. The editor keeps the total
    /// honest; this just guards the per-group value.
    mutating func setPercentage(_ value: Int, for muscleGroup: MuscleGroup) {
        percentages[muscleGroup] = min(max(value, 0), 100)
    }

    /// Sum across all 8 groups — 100 for a valid split. The editor's live Total row shows this and
    /// tints green at 100.
    var total: Int {
        MuscleGroup.allCases.reduce(0) { $0 + percentage(for: $1) }
    }

    /// The preset this split matches exactly, else `nil` ("Custom") — drives which preset chip is
    /// highlighted in the editor.
    var matchingPreset: MuscleTargetPreset? {
        MuscleTargetPreset.allCases.first { $0.split == self }
    }

    /// Compared across all 8 groups so an absent group and an explicit 0 read as equal — keeps
    /// `matchingPreset` robust regardless of how a split was constructed.
    static func == (lhs: MuscleTargetSplit, rhs: MuscleTargetSplit) -> Bool {
        MuscleGroup.allCases.allSatisfy { lhs.percentage(for: $0) == rhs.percentage(for: $0) }
    }

    // MARK: - Codable

    /// Stored on disk as `[String: Int]` keyed by the muscle-group raw value, mapped back to the enum
    /// at the boundary — an enum-keyed dictionary isn't `Codable` to a JSON object on its own.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: Int].self)
        percentages = raw.reduce(into: [:]) { result, pair in
            if let group = MuscleGroup(rawValue: pair.key) {
                result[group] = pair.value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let raw = Dictionary(uniqueKeysWithValues: percentages.map { ($0.key.rawValue, $0.value) })
        try container.encode(raw)
    }

    // MARK: - Defaults

    /// How many percentage points under target a group must fall before it's flagged "behind" — the
    /// editor's threshold note and `MuscleBalanceCalculator`'s `isBehind` both read this.
    static let behindThreshold = 5

    /// The app's default target split — the balanced preset.
    static var `default`: MuscleTargetSplit { MuscleTargetPreset.balanced.split }
}

// MARK: - Presets

/// Named starting points for the target split — the editor's preset chips. Each preset's `split` sums
/// to exactly 100.
enum MuscleTargetPreset: String, CaseIterable, Identifiable {
    case balanced, upperFocus, pushPullLegs

    var id: String { rawValue }

    /// Localized chip title (e.g. "Balanced"). Keys live alongside the editor's strings.
    var title: String { NSLocalizedString("muscleTargetPreset_\(rawValue)", comment: "") }

    var split: MuscleTargetSplit {
        switch self {
        case .balanced:
            return MuscleTargetSplit(percentages: [
                .legs: 20, .back: 18, .chest: 16, .shoulders: 13,
                .biceps: 9, .triceps: 9, .abdominals: 9, .cardio: 6,
            ])
        case .upperFocus:
            return MuscleTargetSplit(percentages: [
                .chest: 18, .back: 18, .shoulders: 16, .biceps: 13,
                .triceps: 13, .legs: 12, .abdominals: 6, .cardio: 4,
            ])
        case .pushPullLegs:
            return MuscleTargetSplit(percentages: [
                .legs: 22, .back: 16, .chest: 16, .shoulders: 14,
                .triceps: 11, .biceps: 11, .abdominals: 6, .cardio: 4,
            ])
        }
    }
}
