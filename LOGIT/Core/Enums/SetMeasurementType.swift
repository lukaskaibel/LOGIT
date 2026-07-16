//
//  SetMeasurementType.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 16.07.26.
//

import Foundation

/// What a set entry measures. An exercise's `measurementType` is the default for its new sets;
/// individual sets can override it. The type is stored as a raw string both on `Exercise`
/// (`measurementTypeString`) and on every entry (`typeString`): the entry's stored type is the
/// truth for recorded history, so changing an exercise's type later never reinterprets old data.
enum SetMeasurementType: String, CaseIterable, Codable, Identifiable {
    case repsAndWeight
    case repsOnly
    case duration
    case weightAndDuration

    var id: String { rawValue }

    var usesRepetitions: Bool {
        self == .repsAndWeight || self == .repsOnly
    }

    var usesWeight: Bool {
        self == .repsAndWeight || self == .weightAndDuration
    }

    var usesDuration: Bool {
        self == .duration || self == .weightAndDuration
    }

    /// How many numeric input fields the recorder shows for one entry of this type — one per
    /// tracked value (a duration is one field, entered in seconds).
    var inputFieldCount: Int {
        switch self {
        case .repsAndWeight: return 2
        case .repsOnly: return 1
        case .duration: return 1
        case .weightAndDuration: return 2
        }
    }

    var title: String {
        NSLocalizedString("measurementType.\(rawValue)", comment: "")
    }
}
