//
//  DistanceUnit.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.07.26.
//

import Foundation

/// The user's distance unit system, chosen in Settings like `WeightUnit`. Each system carries
/// two display units matching the two `SetMeasurementType.DistanceStyle` scales: the long unit
/// for kilometer-scale cardio (km/mi) and the short unit for meter-scale carries (m/yd).
enum DistanceUnit: String, Codable, Identifiable {
    case km, mi

    static var used: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "")
            ?? .defaultFromLocale
    }

    /// Returns the appropriate distance unit based on user's locale.
    /// Returns .mi for US measurement system, .km for metric.
    static var defaultFromLocale: DistanceUnit {
        Locale.current.measurementSystem == .us ? .mi : .km
    }

    /// The meter-scale sibling unit (m/yd), used wherever `DistanceStyle.short` applies.
    var shortUnit: String {
        switch self {
        case .km: return NSLocalizedString("meters.short", comment: "")
        case .mi: return NSLocalizedString("yards.short", comment: "")
        }
    }

    var id: String {
        rawValue
    }
}
