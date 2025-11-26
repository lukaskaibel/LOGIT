//
//  MeasurementEntryType.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.10.23.
//

import Foundation

enum MeasurementEntryType {
    case bodyweight
    case bodyFatPercentage
    case muscleMass
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
        case "bodyFatPercentage":
            self = .bodyFatPercentage
        case "muscleMass":
            self = .muscleMass
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
        case .bodyFatPercentage:
            return "bodyFatPercentage"
        case .muscleMass:
            return "muscleMass"
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
        case .bodyFatPercentage: return NSLocalizedString("bodyFatPercentage", comment: "")
        case .muscleMass: return NSLocalizedString("muscleMass", comment: "")
        case .percentage: return NSLocalizedString("percentage", comment: "")
        case .caloriesBurned: return NSLocalizedString("caloriesBurned", comment: "")
        case let .length(lengthType):
            return NSLocalizedString(lengthType.rawValue, comment: "")
        }
    }

    var unit: String {
        switch self {
        case .bodyweight, .muscleMass:
            return WeightUnit.used.rawValue
        case .bodyFatPercentage, .percentage:
            return "%"
        case .caloriesBurned:
            return "kCal"
        case .length:
            return "cm"
        }
    }

    var systemImage: String {
        switch self {
        case .bodyweight:
            return "scalemass"
        case .bodyFatPercentage:
            return "percent"
        case .muscleMass:
            return "figure.strengthtraining.traditional"
        case .percentage:
            return "percent"
        case .caloriesBurned:
            return "flame"
        case .length:
            return "ruler"
        }
    }
}

extension MeasurementEntryType: Equatable, Hashable {
    static func == (lhs: MeasurementEntryType, rhs: MeasurementEntryType) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum LengthMeasurementEntryType: String, CaseIterable, Hashable {
    case neck, shoulders, chest, bicepsLeft, bicepsRight, forearmLeft, forearmRight, waist, hips,
         thighLeft, thighRight, calfLeft, calfRight
}
