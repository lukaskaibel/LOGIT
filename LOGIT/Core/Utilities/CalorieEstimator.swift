//
//  CalorieEstimator.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.07.26.
//

import CoreData
import Foundation

/// Estimates a workout's active energy from data the user actually logged.
///
/// Two steps:
/// 1. **Working time** — every set entry contributes seconds from the best field it has:
///    logged durations directly, repetitions at a controlled-rep pace, distances at a
///    conservative carry pace. Nothing requires fields a set's measurement type doesn't track.
/// 2. **Density → intensity** — the share of the workout spent working interpolates the
///    session MET across the published range for resistance training (3.0–6.0 METs,
///    anchored so a typical gym session lands on the Compendium of Physical Activities'
///    3.5). Active energy is net of resting burn — the same definition as Apple Health's
///    Active Calories, so the in-app number and the synced number are the same number.
///
/// Guardrails, because a number that feels random is worse than no number:
/// - billable duration is capped (per-set rest allowance + session overhead), so a recorder
///   left running for hours bills like the workout it plausibly was;
/// - the MET is clamped to the published strength-training range;
/// - without a logged body weight there is no estimate at all — never a population default;
/// - results round to 5 kcal and the estimator is fully deterministic.
enum CalorieEstimator {
    /// UserDefaults key for the user-facing opt-out (Settings › Workout). Governs both the
    /// detail-screen row and whether synced Health workouts carry an energy sample.
    static let enabledKey = "calorieEstimatesEnabled"

    // MARK: - Tuning Constants

    /// Seconds of work one controlled repetition takes.
    static let secondsPerRepetition: Double = 3.5
    /// Pace assumed for distance entries without a logged duration (carries), plus a cap so a
    /// long run logged as distance-only can't dominate the working time.
    static let distanceMetersPerSecond: Double = 1.0
    static let maxSecondsPerDistanceEntry: Double = 180
    /// Billable rest allowance: per performed set, plus fixed session overhead (warmup, setup).
    static let maxRestSecondsPerSet: Double = 240
    static let sessionOverheadSeconds: Double = 600
    /// Session MET = 2.4 + 6.3 × working share, clamped to the published range for
    /// resistance training. A typical session (~17% working time) lands on 3.5.
    static let sessionMETRange: ClosedRange<Double> = 3.0...6.0
    /// Estimates below this aren't worth showing.
    static let minimumKilocalories = 5

    /// A computed estimate plus the inputs it was computed from — the explainer sheet shows
    /// exactly these, so what the user sees is what the math used.
    struct Estimate: Equatable {
        let activeKilocalories: Int
        let workingSeconds: Int
        let billableSeconds: Int
        let sessionMET: Double
        let bodyWeightKilograms: Double
        let bodyWeightDate: Date?
    }

    // MARK: - Workout-Level Estimate

    /// The estimate for a workout, or `nil` when it can't be honest: no duration, nothing
    /// performed, or no logged body weight. Must run on the workout's context queue.
    static func estimate(for workout: Workout) -> Estimate? {
        guard let start = workout.date, let end = workout.endDate, end > start,
              let context = workout.managedObjectContext,
              let bodyWeight = bodyWeight(nearestTo: start, in: context)
        else { return nil }

        let performedSets = workout.sets.map { workingSeconds(for: $0.entryValues) }
            .filter { $0 > 0 }
        return estimate(
            workingSeconds: performedSets.reduce(0, +),
            performedSetCount: performedSets.count,
            wallClockSeconds: end.timeIntervalSince(start),
            bodyWeightKilograms: bodyWeight.kilograms,
            bodyWeightDate: bodyWeight.date
        )
    }

    // MARK: - Pure Math

    /// One set's working seconds, summed over its entries (drop sets and supersets have one
    /// entry per drop/exercise, so they fall out naturally). A logged duration is the truth;
    /// repetitions and distances are converted at conservative paces.
    static func workingSeconds(for entryValues: [SetEntryValues]) -> Double {
        entryValues.reduce(0) { total, values in
            guard values.hasPerformanceValue else { return total }
            if values.type.usesDuration && values.duration > 0 {
                return total + Double(values.duration)
            }
            if values.type.usesRepetitions && values.repetitions > 0 {
                return total + Double(values.repetitions) * secondsPerRepetition
            }
            if values.type.usesDistance && values.distance > 0 {
                return total + min(
                    Double(values.distance) / distanceMetersPerSecond,
                    maxSecondsPerDistanceEntry
                )
            }
            return total
        }
    }

    static func estimate(
        workingSeconds: Double,
        performedSetCount: Int,
        wallClockSeconds: Double,
        bodyWeightKilograms: Double,
        bodyWeightDate: Date? = nil
    ) -> Estimate? {
        guard workingSeconds > 0, wallClockSeconds > 0, bodyWeightKilograms > 0 else { return nil }

        // A forgotten recorder can't inflate the bill: rest beyond the per-set allowance
        // (plus overhead) isn't billable. Working time itself is always billable.
        let billableCap = workingSeconds
            + Double(performedSetCount) * maxRestSecondsPerSet
            + sessionOverheadSeconds
        let billableSeconds = min(wallClockSeconds, billableCap)

        let workingShare = min(workingSeconds / billableSeconds, 1)
        let sessionMET = min(
            max(2.4 + 6.3 * workingShare, sessionMETRange.lowerBound),
            sessionMETRange.upperBound
        )

        // (MET − 1) × kg × h — net of resting burn, matching Apple's Active Calories.
        let kilocalories = (sessionMET - 1) * bodyWeightKilograms * (billableSeconds / 3600)
        let rounded = Int((kilocalories / 5).rounded()) * 5
        guard rounded >= minimumKilocalories else { return nil }

        return Estimate(
            activeKilocalories: rounded,
            workingSeconds: Int(workingSeconds.rounded()),
            billableSeconds: Int(billableSeconds.rounded()),
            sessionMET: sessionMET,
            bodyWeightKilograms: bodyWeightKilograms,
            bodyWeightDate: bodyWeightDate
        )
    }

    // MARK: - Body Weight Lookup

    /// The logged body weight nearest to the given date (so backfilled history uses the weight
    /// the user had *then*), or `nil` when none was ever logged.
    static func bodyWeight(
        nearestTo date: Date, in context: NSManagedObjectContext
    ) -> (kilograms: Double, date: Date)? {
        let request: NSFetchRequest<MeasurementEntry> = MeasurementEntry.fetchRequest()
        let entries = (try? context.fetch(request)) ?? []
        return entries
            .compactMap { entry -> (kilograms: Double, date: Date)? in
                guard entry.type == .bodyweight, entry.value_ > 0, let entryDate = entry.date
                else { return nil }
                // Body weight is stored in grams regardless of the display unit.
                return (Double(entry.value_) / 1000, entryDate)
            }
            .min {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }
    }
}
