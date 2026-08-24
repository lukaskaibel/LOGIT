//
//  TemplateSetEntry+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import Foundation

extension TemplateSetEntry {
    static func == (lhs: TemplateSetEntry, rhs: TemplateSetEntry) -> Bool {
        lhs.objectID == rhs.objectID
    }

    /// The measurement this entry records. See `SetEntry.type` for the fallback rationale.
    var type: SetMeasurementType {
        get { SetMeasurementType(rawValue: typeString ?? "") ?? .repsAndWeight }
        set { typeString = newValue.rawValue }
    }

    /// Planned duration in **milliseconds** — the template mirror of `SetEntry.durationMs`,
    /// including its pre-v11 whole-second fallback and write-through. See there for why the
    /// legacy attribute stays.
    var durationMs: Int64 {
        get { durationMillis?.int64Value ?? duration * 1000 }
        set {
            durationMillis = NSNumber(value: newValue)
            duration = roundedToThousands(newValue)
        }
    }

    /// Planned distance in **millimeters** — the template mirror of `SetEntry.distanceMm`.
    var distanceMm: Int64 {
        get { distanceMillimeters?.int64Value ?? distance * 1000 }
        set {
            distanceMillimeters = NSNumber(value: newValue)
            distance = roundedToThousands(newValue)
        }
    }

    /// True when any field the entry's type tracks holds a value.
    var hasValue: Bool {
        (type.usesRepetitions && repetitions > 0)
            || (type.usesWeight && weight > 0)
            || (type.usesDuration && durationMs > 0)
    }

    func clearValues() {
        repetitions = 0
        weight = 0
        durationMs = 0
    }
}
