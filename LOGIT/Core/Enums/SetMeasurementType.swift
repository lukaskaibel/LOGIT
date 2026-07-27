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

    /// The scale a distance field is entered and displayed in. One scale can't serve every
    /// exercise: cardio efforts are kilometer-scale (a 5 km treadmill run), gym-floor efforts
    /// are meter-scale (a 40 m farmer's walk) — 0.04 km would be unusable. Values are always
    /// STORED in meters; the style only decides the display/entry unit: `.long` is km/mi with
    /// decimal entry, `.short` whole m/yd. Each measurement type carries a sensible default
    /// (`distanceStyle` below) and the user can override it per exercise
    /// (`Exercise.distanceStyle`) — resolve through `distanceStyle(for:)`, never the raw default.
    enum DistanceStyle: String, CaseIterable {
        case long
        case short
    }

    /// The type's *default* scale — nil for types without a distance field. Display and entry
    /// sites must use `distanceStyle(for:)`, which lets the exercise's own choice win.
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

/// One value a set entry can record. The exercise editor lets the user compose a measurement
/// type by toggling these instead of decoding combined names like "Weight & Distance".
enum SetTrackedField: CaseIterable {
    case repetitions, weight, duration, distance
}

extension SetMeasurementType {
    /// The fields this type records, derived from the `uses*` flags so the two views of the
    /// same fact can't drift apart.
    var trackedFields: Set<SetTrackedField> {
        var fields = Set<SetTrackedField>()
        if usesRepetitions { fields.insert(.repetitions) }
        if usesWeight { fields.insert(.weight) }
        if usesDuration { fields.insert(.duration) }
        if usesDistance { fields.insert(.distance) }
        return fields
    }

    /// The type recording exactly `trackedFields`, or nil while a selection is incomplete —
    /// weight on its own or nothing at all names no type.
    init?(trackedFields: Set<SetTrackedField>) {
        guard let match = Self.allCases.first(where: { $0.trackedFields == trackedFields })
        else { return nil }
        self = match
    }

    /// Whether `trackedFields` could still grow into a valid type — the exercise editor keeps
    /// a field tappable only while adding it leaves at least one type reachable.
    static func isSubsetOfAnyType(_ trackedFields: Set<SetTrackedField>) -> Bool {
        allCases.contains { trackedFields.isSubset(of: $0.trackedFields) }
    }
}
