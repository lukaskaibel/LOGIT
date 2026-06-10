//
//  OneRepMaxCalculating.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 07.06.26.
//

import Foundation

/// The single source of truth for estimated one-rep max (e1RM) calculations.
///
/// Every screen, tile, badge and personal-best check routes through here, so any change to how
/// estimates are produced — the formula and the reliable rep range — belongs in this one place
/// rather than being duplicated at each call site.
enum OneRepMax {
    /// Above this many repetitions the estimate is no longer reported.
    ///
    /// Rep-max prediction equations are accurate at low reps and lose accuracy as reps climb:
    /// the research consensus is that they are reliable up to roughly 10–12 reps and become
    /// unreliable at 15+ (the estimate is extrapolated from endurance rather than strength). We
    /// take 12 as the practical upper bound — it keeps standard hypertrophy training in range
    /// while excluding the rep counts where the number stops meaning anything.
    static let maxReliableRepetitions: Int64 = 12

    /// Estimates a one-rep max from a single weight × repetitions effort, in the same unit as
    /// `weight` (the app stores weight in grams).
    ///
    /// Uses the Epley formula — `weight × (1 + reps / 30)` — which is the most widely used 1RM
    /// estimate in strength training. Returns 0 (no estimate) for efforts outside the range where
    /// the formula is trustworthy: zero weight/reps, or sets above `maxReliableRepetitions`.
    ///
    /// - Parameters:
    ///   - weight: The weight lifted, in grams.
    ///   - repetitions: The number of repetitions performed at that weight.
    /// - Returns: The estimated one-rep max in grams, or 0 when there is no usable effort or the
    ///   set exceeds the reliable rep range. Callers treat 0 as "no e1RM" — e.g. bodyweight sets,
    ///   empty sets, or high-rep sets.
    static func estimated(weight: Int64, repetitions: Int64) -> Int {
        guard weight > 0, repetitions > 0, repetitions <= maxReliableRepetitions else { return 0 }
        return Int((Double(weight) * (1.0 + Double(repetitions) / 30.0)).rounded())
    }
}
