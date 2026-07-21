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
    case distance
    case distanceAndDuration
    case weightAndDistance

    var id: String { rawValue }

    var usesRepetitions: Bool {
        self == .repsAndWeight || self == .repsOnly
    }

    var usesWeight: Bool {
        self == .repsAndWeight || self == .weightAndDuration || self == .weightAndDistance
    }

    var usesDuration: Bool {
        self == .duration || self == .weightAndDuration || self == .distanceAndDuration
    }

    var usesDistance: Bool {
        self == .distance || self == .distanceAndDuration || self == .weightAndDistance
    }

    /// How the distance field is entered and displayed. One unit can't serve both distance
    /// scales: cardio efforts are kilometer-scale (a 5 km treadmill run), gym-floor efforts are
    /// meter-scale (a 40 m farmer's walk) — 0.04 km would be unusable. The cardio pair uses the
    /// long unit (km/mi, decimal entry); the carry pair and the bare distance type use the short
    /// one (m/yd, whole numbers) — bare distance serves shuttle runs and crawls, while km-scale
    /// efforts always fit distance+duration, where the time field can simply stay empty.
    enum DistanceStyle {
        case long
        case short
    }

    /// Nil for types without a distance field.
    var distanceStyle: DistanceStyle? {
        switch self {
        case .distanceAndDuration: return .long
        case .distance, .weightAndDistance: return .short
        case .repsAndWeight, .repsOnly, .duration, .weightAndDuration: return nil
        }
    }

    /// How many numeric input fields the recorder shows for one entry of this type — one per
    /// tracked value (a duration is one field, entered in seconds).
    var inputFieldCount: Int {
        switch self {
        case .repsAndWeight: return 2
        case .repsOnly: return 1
        case .duration: return 1
        case .weightAndDuration: return 2
        case .distance: return 1
        case .distanceAndDuration: return 2
        case .weightAndDistance: return 2
        }
    }

    var title: String {
        NSLocalizedString("measurementType.\(rawValue)", comment: "")
    }
}
