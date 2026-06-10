//
//  WorkoutSet+.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.05.22.
//

import Foundation

public extension WorkoutSet {
    enum Attribute: String {
        case repetitions, weight
    }

    static func == (lhs: WorkoutSet, rhs: WorkoutSet) -> Bool {
        return lhs.objectID == rhs.objectID
    }

    /// Rest duration in seconds after completing this set. 0 means no rest defined.
    var restDurationSeconds: Int {
        get { Int(restDuration) }
        set { restDuration = Int64(newValue) }
    }

    var exercise: Exercise? {
        setGroup?.exercise
    }

    var workout: Workout? {
        setGroup?.workout
    }

    var previousSetInSetGroup: WorkoutSet? {
        setGroup?.sets.value(at: (setGroup?.sets.firstIndex(of: self) ?? 0) - 1)
    }

    internal func isTraining(_ muscleGroup: MuscleGroup) -> Bool {
        setGroup?.exercise?.muscleGroup == muscleGroup
            || setGroup?.secondaryExercise?.muscleGroup == muscleGroup
    }

    internal func maximum(_ attribute: WorkoutSet.Attribute, for exercise: Exercise) -> Int {
        if let standardSet = self as? StandardSet, standardSet.exercise == exercise {
            return Int(attribute == .repetitions ? standardSet.repetitions : standardSet.weight)
        }
        if let dropSet = self as? DropSet, dropSet.exercise == exercise {
            return Int(
                (attribute == .repetitions ? dropSet.repetitions : dropSet.weights)?.max() ?? 0
            )
        }
        if let superSet = self as? SuperSet {
            var maxValue = 0
            if superSet.exercise == exercise {
                maxValue = Int(
                    attribute == .repetitions
                        ? superSet.repetitionsFirstExercise : superSet.weightFirstExercise
                )
            } else if superSet.secondaryExercise == exercise {
                maxValue = max(maxValue, Int(
                    attribute == .repetitions
                        ? superSet.repetitionsSecondExercise : superSet.weightSecondExercise
                ))
            }
            return maxValue
        }
        return 0
    }

    /// Best estimated one-rep max achievable from this set's entries for the given exercise,
    /// in the same unit as `weight` (grams). Returns 0 when there is no usable weight ×
    /// repetitions entry — e.g. a pure bodyweight set or an empty set. The estimate itself
    /// comes from the shared `OneRepMax.estimated(weight:repetitions:)`.
    internal func estimatedOneRepMax(for exercise: Exercise) -> Int {
        estimatedOneRepMaxEntry(for: exercise).oneRepMax
    }

    /// The best e1RM for `exercise` together with the weight and repetitions that produced
    /// it. Mirrors the per-set-type handling of `maximum(_:for:)`. For drop sets the single
    /// drop with the highest estimate wins; for super sets the matching exercise's entry.
    internal func estimatedOneRepMaxEntry(
        for exercise: Exercise
    ) -> (oneRepMax: Int, weight: Int64, repetitions: Int64) {
        if let standardSet = self as? StandardSet, standardSet.exercise == exercise {
            return (
                OneRepMax.estimated(weight: standardSet.weight, repetitions: standardSet.repetitions),
                standardSet.weight,
                standardSet.repetitions
            )
        }
        if let dropSet = self as? DropSet, dropSet.exercise == exercise {
            var best = (oneRepMax: 0, weight: Int64(0), repetitions: Int64(0))
            for (weight, repetitions) in zip(dropSet.weights ?? [], dropSet.repetitions ?? []) {
                let oneRepMax = OneRepMax.estimated(weight: weight, repetitions: repetitions)
                if oneRepMax > best.oneRepMax {
                    best = (oneRepMax, weight, repetitions)
                }
            }
            return best
        }
        if let superSet = self as? SuperSet {
            if superSet.exercise == exercise {
                return (
                    OneRepMax.estimated(weight: superSet.weightFirstExercise, repetitions: superSet.repetitionsFirstExercise),
                    superSet.weightFirstExercise,
                    superSet.repetitionsFirstExercise
                )
            } else if superSet.secondaryExercise == exercise {
                return (
                    OneRepMax.estimated(weight: superSet.weightSecondExercise, repetitions: superSet.repetitionsSecondExercise),
                    superSet.weightSecondExercise,
                    superSet.repetitionsSecondExercise
                )
            }
        }
        return (0, 0, 0)
    }

    /// The weight × repetitions entry with the highest *weight* for `exercise`, together with the
    /// repetitions performed at that weight. Mirrors the per-set-type handling of `maximum(_:for:)`:
    /// for drop sets the heaviest drop wins (with its own reps); for super sets the matching
    /// exercise's entry. The `weight` returned equals `maximum(.weight, for:)`. Returns (0, 0) when
    /// the exercise isn't part of this set.
    internal func maxWeightEntry(for exercise: Exercise) -> (weight: Int64, repetitions: Int64) {
        if let standardSet = self as? StandardSet, standardSet.exercise == exercise {
            return (standardSet.weight, standardSet.repetitions)
        }
        if let dropSet = self as? DropSet, dropSet.exercise == exercise {
            var best = (weight: Int64(0), repetitions: Int64(0))
            for (weight, repetitions) in zip(dropSet.weights ?? [], dropSet.repetitions ?? []) {
                if weight > best.weight {
                    best = (weight, repetitions)
                }
            }
            return best
        }
        if let superSet = self as? SuperSet {
            if superSet.exercise == exercise {
                return (superSet.weightFirstExercise, superSet.repetitionsFirstExercise)
            } else if superSet.secondaryExercise == exercise {
                return (superSet.weightSecondExercise, superSet.repetitionsSecondExercise)
            }
        }
        return (0, 0)
    }

    /// The weight × repetitions entry with the highest *repetitions* for `exercise`, together with
    /// the weight used for those repetitions. Counterpart to `maxWeightEntry(for:)`; the
    /// `repetitions` returned equals `maximum(.repetitions, for:)`. Returns (0, 0) when the
    /// exercise isn't part of this set.
    internal func maxRepetitionsEntry(for exercise: Exercise) -> (repetitions: Int64, weight: Int64) {
        if let standardSet = self as? StandardSet, standardSet.exercise == exercise {
            return (standardSet.repetitions, standardSet.weight)
        }
        if let dropSet = self as? DropSet, dropSet.exercise == exercise {
            var best = (repetitions: Int64(0), weight: Int64(0))
            for (weight, repetitions) in zip(dropSet.weights ?? [], dropSet.repetitions ?? []) {
                if repetitions > best.repetitions {
                    best = (repetitions, weight)
                }
            }
            return best
        }
        if let superSet = self as? SuperSet {
            if superSet.exercise == exercise {
                return (superSet.repetitionsFirstExercise, superSet.weightFirstExercise)
            } else if superSet.secondaryExercise == exercise {
                return (superSet.repetitionsSecondExercise, superSet.weightSecondExercise)
            }
        }
        return (0, 0)
    }

    var isSuperSet: Bool { (self as? SuperSet) != nil }
    var isDropSet: Bool { (self as? DropSet) != nil }

    func match(_ templateSet: TemplateSet) {
        if let standardSet = self as? StandardSet,
           let templateStandardSet = templateSet as? TemplateStandardSet
        {
            standardSet.repetitions = templateStandardSet.repetitions
            standardSet.weight = templateStandardSet.weight
        } else if let dropSet = self as? DropSet,
                  let templateDropSet = templateSet as? TemplateDropSet
        {
            dropSet.repetitions = templateDropSet.repetitions
            dropSet.weights = templateDropSet.weights
        } else if let superSet = self as? SuperSet,
                  let templateSuperSet = templateSet as? TemplateSuperSet
        {
            superSet.repetitionsFirstExercise = templateSuperSet.repetitionsFirstExercise
            superSet.repetitionsSecondExercise = templateSuperSet.repetitionsSecondExercise
            superSet.weightFirstExercise = templateSuperSet.weightFirstExercise
            superSet.weightSecondExercise = templateSuperSet.weightSecondExercise
        }
        restDuration = templateSet.restDuration
    }

    func match(_ workoutSet: WorkoutSet) {
        if let standardSet = self as? StandardSet,
           let workoutStandardSet = workoutSet as? StandardSet
        {
            standardSet.repetitions = workoutStandardSet.repetitions
            standardSet.weight = workoutStandardSet.weight
        } else if let dropSet = self as? DropSet, let workoutDropSet = workoutSet as? DropSet {
            dropSet.repetitions = workoutDropSet.repetitions
            dropSet.weights = workoutDropSet.weights
        } else if let superSet = self as? SuperSet, let workoutSuperSet = workoutSet as? SuperSet {
            superSet.repetitionsFirstExercise = workoutSuperSet.repetitionsFirstExercise
            superSet.repetitionsSecondExercise = workoutSuperSet.repetitionsSecondExercise
            superSet.weightFirstExercise = workoutSuperSet.weightFirstExercise
            superSet.weightSecondExercise = workoutSuperSet.weightSecondExercise
        }
        restDuration = workoutSet.restDuration
    }

    // MARK: Methods to override for subclass

    @objc var hasEntry: Bool {
        fatalError("WorkoutSet+: hasEntry must be implemented in subclass of WorkoutSet")
    }

    /// True when the set has recorded repetitions, regardless of weight entry.
    @objc var hasRepetitionEntry: Bool {
        fatalError("WorkoutSet+: hasRepetitionEntry must be implemented in subclass of WorkoutSet")
    }

    @objc func clearEntries() {
        fatalError("WorkoutSet+: clearEntries must be implemented in subclass of WorkoutSet")
    }
}
