//
//  SetEntry+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import Foundation

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

    /// True when any field the entry's type tracks holds a value. All-zero fields are the
    /// "planned but not performed" placeholder state (the legacy 0-means-empty convention).
    var hasValue: Bool {
        (type.usesRepetitions && repetitions > 0)
            || (type.usesWeight && weight > 0)
            || (type.usesDuration && duration > 0)
    }

    /// True when the entry's primary performance field is filled — repetitions for rep-based
    /// types, the duration for time-based ones. This is the "set was performed" signal the
    /// recorder's rest timer and the Live Activity react to.
    var hasPerformanceValue: Bool {
        if type.usesRepetitions { return repetitions > 0 }
        if type.usesDuration { return duration > 0 }
        return false
    }

    func clearValues() {
        repetitions = 0
        weight = 0
        duration = 0
    }
}
