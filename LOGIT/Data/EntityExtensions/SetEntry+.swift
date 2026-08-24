//
//  SetEntry+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import Foundation

/// Rounds a fine-grained value (milliseconds, millimeters) to the whole coarse unit (seconds,
/// meters) kept in the pre-v11 mirror attribute. Integer arithmetic, so no Double rounding
/// surprises on the values that matter — 12_500 ms mirrors as 13 s, 12_499 as 12 s.
internal func roundedToThousands(_ value: Int64) -> Int64 {
    value < 0 ? -((-value + 500) / 1000) : (value + 500) / 1000
}

extension SetEntry {
    static func == (lhs: SetEntry, rhs: SetEntry) -> Bool {
        lhs.objectID == rhs.objectID
    }

    /// The measurement this entry records. Entries always store their type explicitly at
    /// creation; the reps-and-weight fallback only covers data that predates the type field,
    /// which by definition recorded reps and weight.
    var type: SetMeasurementType {
        get { SetMeasurementType(rawValue: typeString ?? "") ?? .repsAndWeight }
        set { typeString = newValue.rawValue }
    }

    /// The recorded duration in **milliseconds** — the unit every reader works in since model
    /// v11, so a sprint can be logged as 12.34 s rather than rounded to a whole second.
    ///
    /// `durationMillis` is the truth when present. Rows written before v11 — and rows still
    /// arriving through CloudKit from devices on older app versions, which happens for as long
    /// as those installs live — carry only the whole-second `duration`, and read as seconds
    /// × 1000. That fallback is why no migration sweep is needed: an unconverted row reads
    /// identically to a converted one.
    ///
    /// Writing keeps both in step. The millisecond value is the real one; `duration` is
    /// mirrored as rounded whole seconds so older versions keep showing a sensible number.
    /// The mirror is lossy by design (12.34 s reads as 12 s over there, and anything under
    /// half a second reads as the empty placeholder) — CloudKit's schema is additive-only, so
    /// the seconds attribute can never be removed, only left behind.
    var durationMs: Int64 {
        get { durationMillis?.int64Value ?? duration * 1000 }
        set {
            durationMillis = NSNumber(value: newValue)
            duration = roundedToThousands(newValue)
        }
    }

    /// The recorded distance in **millimeters**, on exactly the same v11 terms as `durationMs`:
    /// `distanceMillimeters` when present, else the legacy whole-meter `distance` × 1000, and
    /// writes mirror rounded whole meters back for older versions.
    ///
    /// Millimeters rather than centimeters because the display unit is the user's, not ours:
    /// centimeter storage cannot round-trip two-decimal yard entries (0.06 yd stores as 5 cm
    /// and redisplays as 0.05 yd), while millimeters carry m and yd at two decimals and km and
    /// mi at three.
    var distanceMm: Int64 {
        get { distanceMillimeters?.int64Value ?? distance * 1000 }
        set {
            distanceMillimeters = NSNumber(value: newValue)
            distance = roundedToThousands(newValue)
        }
    }

    /// True when any field the entry's type tracks holds a value. All-zero fields are the
    /// "planned but not performed" placeholder state (the legacy 0-means-empty convention).
    var hasValue: Bool {
        (type.usesRepetitions && repetitions > 0)
            || (type.usesWeight && weight > 0)
            || (type.usesDuration && durationMs > 0)
            || (type.usesDistance && distanceMm > 0)
    }

    /// True when the entry's primary performance field is filled — repetitions for rep-based
    /// types, the duration or distance for time/distance-based ones (either counts, so logging
    /// only the distance of a run still marks the set performed). This is the "set was
    /// performed" signal the recorder's rest timer and the Live Activity react to.
    var hasPerformanceValue: Bool {
        if type.usesRepetitions { return repetitions > 0 }
        if type.usesDuration && durationMs > 0 { return true }
        if type.usesDistance && distanceMm > 0 { return true }
        return false
    }

    func clearValues() {
        repetitions = 0
        weight = 0
        durationMs = 0
        distanceMm = 0
    }
}
