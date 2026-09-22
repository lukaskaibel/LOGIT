//
//  MuscleFocus.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Foundation

// MARK: - Focus

/// The user's training focus: how many sets each muscle group should get per week. Zero means the
/// group isn't part of the focus — it leaves the balance and has no target to be read against.
///
/// Absolute weekly sets rather than a share of all sets, for two reasons. A share is zero-sum: adding
/// an arm day lowered the legs share and flipped legs to "below target" without the legs training
/// changing at all. And weekly sets per muscle is the unit programs are actually written in, so a
/// target like "legs 10" needs no explaining and "3 more sets" is something you can do this week.
///
/// A focus remembers the weekly workout goal its targets were sized for. The two are coupled only at
/// the moment of choosing — a preset is sized for the goal in force then — and a later change of goal
/// never moves the targets by itself. The Muscle Groups screen offers to rescale them instead, and a
/// "not now" is remembered (`keptForWorkoutsPerWeek`) so the offer stays away until the goal moves
/// again.
///
/// Persisted as JSON in `UserDefaults` (see `MuscleFocusStore`) — CloudKit is additive-only, so this
/// setting stays out of Core Data.
struct MuscleFocus: Codable, Equatable {
    /// Weekly set target per group. Groups missing from the dictionary read as 0.
    private var targets: [MuscleGroup: Int]
    /// The weekly workout goal the targets were sized for.
    private(set) var workoutsPerWeek: Int
    /// A weekly goal the user was offered a rescale for and declined. The offer doesn't come back
    /// while the goal stays there.
    private(set) var keptForWorkoutsPerWeek: Int?

    /// What a single group's control allows. Forty weekly sets for one muscle is well past anything a
    /// program would prescribe, so the cap only stops a runaway press.
    static let targetRange = 0 ... 40

    /// The week every preset's base numbers describe, the week a user without a weekly goal is sized
    /// for, and the week a focus saved before targets followed the goal is read as sized for.
    static let baseWorkoutsPerWeek = 3

    init(targets: [MuscleGroup: Int], workoutsPerWeek: Int = MuscleFocus.baseWorkoutsPerWeek) {
        self.targets = targets.mapValues { Self.clamped($0) }
        self.workoutsPerWeek = max(workoutsPerWeek, 1)
        keptForWorkoutsPerWeek = nil
    }

    // MARK: Reads

    /// The group's weekly set target — 0 when it isn't part of the focus.
    func target(for muscleGroup: MuscleGroup) -> Int {
        targets[muscleGroup] ?? 0
    }

    func isExcluded(_ muscleGroup: MuscleGroup) -> Bool {
        target(for: muscleGroup) == 0
    }

    /// The groups with a target, in canonical order.
    var includedGroups: [MuscleGroup] {
        MuscleGroup.allCases.filter { target(for: $0) > 0 }
    }

    /// Every group's target added up — the week the focus describes.
    var weeklyTotal: Int {
        MuscleGroup.allCases.reduce(0) { $0 + target(for: $1) }
    }

    /// The highest single target — what a chart of this focus scales its tallest bar to.
    var highestTarget: Int {
        MuscleGroup.allCases.map { target(for: $0) }.max() ?? 0
    }

    /// The preset whose targets these are exactly, at the goal they were sized for — else `nil`
    /// ("Custom").
    var matchingPreset: MuscleFocusPreset? {
        MuscleFocusPreset.allCases.first { hasSameTargets(as: $0.focus(forWorkoutsPerWeek: workoutsPerWeek)) }
    }

    /// The same number for every group, whatever the two were sized for.
    func hasSameTargets(as other: MuscleFocus) -> Bool {
        MuscleGroup.allCases.allSatisfy { target(for: $0) == other.target(for: $0) }
    }

    /// The lowest target a group's control may reach: 0, unless it is the only group left with a
    /// target — a focus on nothing isn't a focus.
    func minimumTarget(for muscleGroup: MuscleGroup) -> Int {
        includedGroups == [muscleGroup] ? 1 : Self.targetRange.lowerBound
    }

    /// Whether a weekly goal of `goal` should bring up the offer to rescale: a real goal, not the one
    /// the targets were sized for, and not one the user already kept them for.
    func suggestsResize(forWorkoutsPerWeek goal: Int?) -> Bool {
        guard let goal, goal > 0 else { return false }
        return goal != workoutsPerWeek && goal != keptForWorkoutsPerWeek
    }

    /// These targets for a different weekly goal. A preset is derived afresh at the new goal, so it
    /// stays exactly that preset; anything else scales group by group, keeping every group it had and
    /// adding none it didn't.
    func resized(forWorkoutsPerWeek goal: Int) -> MuscleFocus {
        if let preset = matchingPreset {
            return preset.focus(forWorkoutsPerWeek: goal)
        }
        let scaledTargets = MuscleGroup.allCases.reduce(into: [MuscleGroup: Int]()) { result, group in
            result[group] = Self.scaled(target(for: group), from: workoutsPerWeek, to: goal)
        }
        return MuscleFocus(targets: scaledTargets, workoutsPerWeek: goal)
    }

    /// A weekly target sized for `from` workouts, resized for `to`: proportional and rounded, never
    /// below one set for a group that has a target, and zero stays zero.
    static func scaled(_ target: Int, from: Int, to: Int) -> Int {
        guard target > 0 else { return 0 }
        let value = (Double(target) * Double(max(to, 1)) / Double(max(from, 1))).rounded()
        return clamped(max(Int(value), 1))
    }

    // MARK: Mutations

    /// Sets a group's weekly target, clamped to `targetRange` and refused below 1 for the last group
    /// with a target.
    mutating func setTarget(_ value: Int, for muscleGroup: MuscleGroup) {
        targets[muscleGroup] = max(Self.clamped(value), minimumTarget(for: muscleGroup))
    }

    /// Records that the user saw these targets against a weekly goal of `goal` and kept them.
    mutating func keep(forWorkoutsPerWeek goal: Int) {
        keptForWorkoutsPerWeek = goal
    }

    // MARK: Equatable

    /// Targets compared across all 8 groups, so a missing entry and an explicit 0 read as equal.
    static func == (lhs: MuscleFocus, rhs: MuscleFocus) -> Bool {
        lhs.hasSameTargets(as: rhs)
            && lhs.workoutsPerWeek == rhs.workoutsPerWeek
            && lhs.keptForWorkoutsPerWeek == rhs.keptForWorkoutsPerWeek
    }

    // MARK: Codable

    /// On disk: `{"targets": {"legs": 10, …}, "workoutsPerWeek": 3, "keptForWorkoutsPerWeek": 4}`,
    /// keyed by the muscle-group raw values.
    ///
    /// Also reads the two older shapes. Targets without `workoutsPerWeek` were saved before targets
    /// followed the weekly goal: they are read as sized for the base week, and an untouched copy of
    /// one of that era's presets becomes its successor, so a Full Body user stays Full Body rather
    /// than waking up as Custom. And `{"priorities": {"legs": 3, …}, "excluded": ["cardio"]}` from the
    /// priority editor maps High / Medium / Low to 10 / 6 / 3 weekly sets and an excluded group to 0.
    private enum CodingKeys: String, CodingKey {
        case targets, workoutsPerWeek, keptForWorkoutsPerWeek, priorities, excluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keptForWorkoutsPerWeek = try container.decodeIfPresent(Int.self, forKey: .keptForWorkoutsPerWeek)
        if let raw = try container.decodeIfPresent([String: Int].self, forKey: .targets) {
            let decoded = Self.groupKeyed(raw).mapValues { Self.clamped($0) }
            if let workoutsPerWeek = try container.decodeIfPresent(Int.self, forKey: .workoutsPerWeek) {
                targets = decoded
                self.workoutsPerWeek = max(workoutsPerWeek, 1)
            } else {
                targets = Self.successorOfRetiredPreset(decoded) ?? decoded
                workoutsPerWeek = Self.baseWorkoutsPerWeek
            }
            return
        }
        workoutsPerWeek = Self.baseWorkoutsPerWeek
        let rawPriorities = try container.decode([String: Int].self, forKey: .priorities)
        let excluded = Set((try container.decodeIfPresent([String].self, forKey: .excluded) ?? [])
            .compactMap(MuscleGroup.init(rawValue:)))
        let levels = Self.groupKeyed(rawPriorities)
        targets = MuscleGroup.allCases.reduce(into: [:]) { result, group in
            guard !excluded.contains(group) else {
                result[group] = 0
                return
            }
            switch levels[group] ?? 2 {
            case 3: result[group] = 10
            case 1: result[group] = 3
            default: result[group] = 6
            }
        }
        if includedGroups.isEmpty {
            self = .default
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let raw = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0.rawValue, target(for: $0)) })
        try container.encode(raw, forKey: .targets)
        try container.encode(workoutsPerWeek, forKey: .workoutsPerWeek)
        try container.encodeIfPresent(keptForWorkoutsPerWeek, forKey: .keptForWorkoutsPerWeek)
    }

    private static func groupKeyed(_ raw: [String: Int]) -> [MuscleGroup: Int] {
        raw.reduce(into: [:]) { result, pair in
            if let group = MuscleGroup(rawValue: pair.key) {
                result[group] = pair.value
            }
        }
    }

    private static func clamped(_ value: Int) -> Int {
        min(max(value, targetRange.lowerBound), targetRange.upperBound)
    }

    // MARK: Defaults

    /// The order every focus surface lists the groups in — the editor's grid, the picker's pills —
    /// descending by the default focus, so a group sits in the same place on each.
    static let displayOrder: [MuscleGroup] = [.legs, .back, .chest, .shoulders, .biceps, .triceps, .abdominals, .cardio]

    /// The app's default focus, for the base week. `MuscleFocusStore` sizes it to the user's goal.
    static var `default`: MuscleFocus { MuscleFocusPreset.fullBody.focus(forWorkoutsPerWeek: baseWorkoutsPerWeek) }

    // MARK: Retired presets

    /// The presets before the picker (#164–#186), each paired with its successor. Every one targeted
    /// cardio, which the strength presets no longer do: a lifter who never logs cardio would otherwise
    /// see it recommended for good.
    private static let retiredPresets: [([MuscleGroup: Int], MuscleFocusPreset)] = [
        ([.legs: 10, .back: 10, .chest: 10, .shoulders: 8, .biceps: 6, .triceps: 6, .abdominals: 4, .cardio: 2], .fullBody),
        ([.legs: 4, .back: 12, .chest: 12, .shoulders: 10, .biceps: 8, .triceps: 8, .abdominals: 4, .cardio: 2], .upperBody),
        ([.legs: 16, .back: 8, .chest: 4, .shoulders: 4, .biceps: 3, .triceps: 3, .abdominals: 6, .cardio: 2], .lowerBody),
        ([.legs: 10, .back: 6, .chest: 3, .shoulders: 3, .biceps: 2, .triceps: 2, .abdominals: 6, .cardio: 6], .cardio),
    ]

    private static func successorOfRetiredPreset(_ targets: [MuscleGroup: Int]) -> [MuscleGroup: Int]? {
        retiredPresets
            .first { retired, _ in MuscleGroup.allCases.allSatisfy { (retired[$0] ?? 0) == (targets[$0] ?? 0) } }
            .map { _, successor in successor.baseTargets }
    }

    // MARK: Legacy percent split

    /// Reads a split saved by the original percent editor (`[group: percent]`, summing to 100). Its
    /// three exact presets map to their successors; anything else is scaled onto the default focus's
    /// weekly total, keeping at least one set for any group that had a share at all.
    init(legacyPercentages percentages: [MuscleGroup: Int]) {
        func matches(_ preset: [MuscleGroup: Int]) -> Bool {
            MuscleGroup.allCases.allSatisfy { (percentages[$0] ?? 0) == (preset[$0] ?? 0) }
        }
        if matches(Self.legacyBalanced) || matches(Self.legacyPushPullLegs) {
            self = .default
            return
        }
        if matches(Self.legacyUpperFocus) {
            self = MuscleFocusPreset.upperBody.focus(forWorkoutsPerWeek: Self.baseWorkoutsPerWeek)
            return
        }
        let total = percentages.values.reduce(0, +)
        guard total > 0 else {
            self = .default
            return
        }
        let budget = Double(MuscleFocus.default.weeklyTotal)
        self.init(targets: MuscleGroup.allCases.reduce(into: [:]) { result, group in
            let percent = percentages[group] ?? 0
            result[group] = percent > 0 ? max(Int((Double(percent) / Double(total) * budget).rounded()), 1) : 0
        })
    }

    private static let legacyBalanced: [MuscleGroup: Int] = [
        .legs: 20, .back: 18, .chest: 16, .shoulders: 13, .biceps: 9, .triceps: 9, .abdominals: 9, .cardio: 6,
    ]
    private static let legacyUpperFocus: [MuscleGroup: Int] = [
        .chest: 18, .back: 18, .shoulders: 16, .biceps: 13, .triceps: 13, .legs: 12, .abdominals: 6, .cardio: 4,
    ]
    private static let legacyPushPullLegs: [MuscleGroup: Int] = [
        .legs: 22, .back: 16, .chest: 16, .shoulders: 14, .triceps: 11, .biceps: 11, .abdominals: 6, .cardio: 4,
    ]
}

// MARK: - Presets

/// What the user wants to focus on, as a body area — never a goal like strength or endurance, because
/// the only lever the balance has is how many sets each group gets, and a goal it can't measure would
/// be a promise it can't keep.
///
/// Each preset raises its area and keeps the rest at maintenance, roughly half the raised groups and
/// never zero, so the balance can still catch a region dropped entirely. Back sits at or above chest
/// throughout, the pull-over-push bias coaches program by default. Cardio is only targeted where it
/// is the point: a lifter who never logs cardio in LOGIT would otherwise see it recommended for good.
///
/// The numbers are for a three-workout week and scale with the user's weekly goal when a preset is
/// chosen (`focus(forWorkoutsPerWeek:)`). Any change to a single target makes the focus "Custom".
enum MuscleFocusPreset: String, CaseIterable, Identifiable {
    case fullBody, upperBody, lowerBody, armsAndShoulders, cardio

    var id: String { rawValue }

    /// Localized name ("Upper Body").
    var title: String { NSLocalizedString("muscleFocusPreset_\(rawValue)", comment: "") }

    /// One line on what the preset raises and what it keeps at maintenance — the picker tile's text.
    var summary: String { NSLocalizedString("muscleFocusPresetSummary_\(rawValue)", comment: "") }

    /// Weekly sets per group for a week of `MuscleFocus.baseWorkoutsPerWeek` workouts.
    var baseTargets: [MuscleGroup: Int] {
        switch self {
        case .fullBody:
            return [.legs: 10, .back: 10, .chest: 8, .shoulders: 6, .biceps: 4, .triceps: 4, .abdominals: 4, .cardio: 0]
        case .upperBody:
            return [.legs: 4, .back: 12, .chest: 10, .shoulders: 10, .biceps: 8, .triceps: 8, .abdominals: 4, .cardio: 0]
        case .lowerBody:
            return [.legs: 16, .back: 8, .chest: 6, .shoulders: 4, .biceps: 3, .triceps: 3, .abdominals: 6, .cardio: 0]
        case .armsAndShoulders:
            return [.legs: 6, .back: 8, .chest: 6, .shoulders: 10, .biceps: 10, .triceps: 10, .abdominals: 4, .cardio: 0]
        case .cardio:
            return [.legs: 8, .back: 6, .chest: 4, .shoulders: 4, .biceps: 2, .triceps: 2, .abdominals: 6, .cardio: 4]
        }
    }

    /// The preset sized for a week of `goal` workouts.
    func focus(forWorkoutsPerWeek goal: Int) -> MuscleFocus {
        MuscleFocus(
            targets: baseTargets.mapValues {
                MuscleFocus.scaled($0, from: MuscleFocus.baseWorkoutsPerWeek, to: goal)
            },
            workoutsPerWeek: goal
        )
    }
}
