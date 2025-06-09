//
//  WidgetType.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.10.23.
//

import Foundation

enum WidgetType {
    case personalBest, bestWeightPerDay, bestRepetitionsPerDay, volumePerDay, exerciseSetsPerWeek
    case measurement(MeasurementEntryType)
    case currentWeekTargetPerWeek, muscleGroupsInLastTen, setsPerWeek, workoutsPerMonth, homeScreenVolumePerDay

    init?(rawValue: String) {
        if rawValue.hasPrefix("measurement") {
            let measurementValue = String(rawValue.dropFirst("measurement".count))
                .firstLetterLowercased
            if let measurementType = MeasurementEntryType(rawValue: measurementValue) {
                self = .measurement(measurementType)
                return
            }
        }
        switch rawValue {
        case "personalBest":
            self = .personalBest
        case "bestWeightPerDay":
            self = .bestWeightPerDay
        case "bestRepetitionsPerDay":
            self = .bestRepetitionsPerDay
        case "volumePerDay":
            self = .volumePerDay
        case "exerciseSetsPerWeek":
            self = .exerciseSetsPerWeek
        case "currentWeekTargetPerWeek":
            self = .currentWeekTargetPerWeek
        case "muscleGroupsInLastTen":
            self = .muscleGroupsInLastTen
        case "setsPerWeek":
            self = .setsPerWeek
        case "workoutsPerMonth":
            self = .workoutsPerMonth
        case "homeScreenVolumePerDay":
            self = .homeScreenVolumePerDay
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .personalBest:
            return "personalBest"
        case .bestWeightPerDay:
            return "bestWeightPerDay"
        case .bestRepetitionsPerDay:
            return "bestRepetitionsPerDay"
        case .volumePerDay:
            return "volumePerDay"
        case .exerciseSetsPerWeek:
            return "exerciseSetsPerWeek"
        case .currentWeekTargetPerWeek:
            return "currentWeekTargetPerWeek"
        case .muscleGroupsInLastTen:
            return "muscleGroupsInLastTen"
        case .setsPerWeek:
            return "setsPerWeek"
        case .workoutsPerMonth:
            return "workoutsPerMonth"
        case .homeScreenVolumePerDay:
            return "homeScreenVolumePerDay"
        case let .measurement(measurementType):
            return "measurement" + measurementType.rawValue.firstLetterUppercased
        }
    }

    var title: String {
        switch self {
        case .personalBest: return NSLocalizedString("personalBest", comment: "")
        case .bestWeightPerDay: return NSLocalizedString("maximumWeight", comment: "")
        case .bestRepetitionsPerDay: return NSLocalizedString("maximumRepetitions", comment: "")
        case .volumePerDay: return NSLocalizedString("volume", comment: "")
        case .exerciseSetsPerWeek: return NSLocalizedString("sets", comment: "")
        case .currentWeekTargetPerWeek: return NSLocalizedString("workoutGoal", comment: "")
        case .muscleGroupsInLastTen: return NSLocalizedString("muscleGroupSplit", comment: "")
        case .setsPerWeek: return NSLocalizedString("overallSets", comment: "")
        case .workoutsPerMonth: return NSLocalizedString("workouts", comment: "")
        case .homeScreenVolumePerDay: return NSLocalizedString("overallVolume", comment: "")
        case let .measurement(measurement):
            return measurement.title
        }
    }

    var unit: String {
        switch self {
        case .personalBest: return NSLocalizedString("allTime", comment: "")
        case .bestWeightPerDay: return WeightUnit.used.rawValue.uppercased() + " " + NSLocalizedString("perDay", comment: "")
        case .bestRepetitionsPerDay: return NSLocalizedString("PerDay", comment: "")
        case .volumePerDay: return WeightUnit.used.rawValue.uppercased() + " " + NSLocalizedString("perDay", comment: "")
        case .exerciseSetsPerWeek: return NSLocalizedString("PerWeek", comment: "")
        case .currentWeekTargetPerWeek: return NSLocalizedString("PerWeek", comment: "")
        case .muscleGroupsInLastTen: return NSLocalizedString("lastTenWorkouts", comment: "")
        case .setsPerWeek: return NSLocalizedString("PerWeek", comment: "")
        case .workoutsPerMonth: return NSLocalizedString("PerMonth", comment: "")
        case .homeScreenVolumePerDay: return WeightUnit.used.rawValue.uppercased() + " " + NSLocalizedString("perDay", comment: "")
        case let .measurement(measurement):
            return measurement.unit.uppercased() + " " + NSLocalizedString("perDay", comment: "")
        }
    }
}

extension WidgetType: Equatable {
    static func == (lhs: WidgetType, rhs: WidgetType) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}
