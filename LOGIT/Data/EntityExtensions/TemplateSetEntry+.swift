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

    /// True when any field the entry's type tracks holds a value.
    var hasValue: Bool {
        (type.usesRepetitions && repetitions > 0)
            || (type.usesWeight && weight > 0)
            || (type.usesDuration && duration > 0)
    }

    func clearValues() {
        repetitions = 0
        weight = 0
        duration = 0
    }
}
