//
//  MeasurementEntryType.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.10.23.
//

import Foundation

enum MeasurementEntryType {
    case bodyweight
    case percentage
    case caloriesBurned
    case length(LengthMeasurementEntryType)

    init?(rawValue: String) {
        if rawValue.hasPrefix("length") {
            let lengthMeasurementTypeRaw = String(rawValue.dropFirst("length".count))
                .firstLetterLowercased
            if let lengthType = LengthMeasurementEntryType(rawValue: lengthMeasurementTypeRaw) {
                self = .length(lengthType)
                return
            }
        }
        switch rawValue {
        case "bodyweight":
            self = .bodyweight
        case "percentage":
            self = .percentage
        case "caloriesBurned":
            self = .caloriesBurned
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .bodyweight:
            return "bodyweight"
        case .percentage:
            return "percentage"
        case .caloriesBurned:
            return "caloriesBurned"
        case let .length(lengthType):
            return "length" + lengthType.rawValue.firstLetterUppercased
        }
    }

    var title: String {
        switch self {
        case .bodyweight: return NSLocalizedString("bodyweight", comment: "")
        case .percentage: return NSLocalizedString("percentage", comment: "")
        case .caloriesBurned: return NSLocalizedString("caloriesBurned", comment: "")
        case let .length(lengthType):
            return NSLocalizedString(lengthType.rawValue, comment: "")
        }
    }

    var unit: String {
        switch self {
        case .bodyweight:
            return WeightUnit.used.rawValue
        case .percentage:
            return "%"
        case .caloriesBurned:
            return "kCal"
        case .length:
            return "cm"
        }
    }
}

extension MeasurementEntryType: Equatable {
    static func == (lhs: MeasurementEntryType, rhs: MeasurementEntryType) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

enum LengthMeasurementEntryType: String, CaseIterable {
    case neck, shoulders, chest, bicepsLeft, bicepsRight, forearmLeft, forearmRight, waist, hips,
         thighLeft, thighRight, calfLeft, calfRight
}
