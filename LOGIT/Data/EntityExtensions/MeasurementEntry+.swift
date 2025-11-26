//
//  MeasurementEntry+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 19.09.23.
//

import Foundation

extension MeasurementEntry {
    var type: MeasurementEntryType? {
        get {
            MeasurementEntryType(rawValue: type_ ?? "")
        }
        set {
            type_ = newValue?.rawValue
        }
    }

    var value: Int {
        get {
            switch type {
            case .bodyweight, .muscleMass: return convertWeightForDisplaying(value_)
            case .bodyFatPercentage, .percentage, .caloriesBurned: return Int(value_ / 1000)
            case .length: return Int(value_ / 10)
            case .none: return Int(value_)
            }
        }
        set {
            switch type {
            case .bodyweight, .muscleMass: value_ = convertWeightForStoring(Int64(newValue))
            case .bodyFatPercentage, .percentage, .caloriesBurned: value_ = Int64(newValue * 1000)
            case .length: value_ = Int64(newValue * 10)
            case .none: value_ = Int64(newValue)
            }
        }
    }
    
    var decimalValue: Double {
        get {
            switch type {
            case .bodyweight, .muscleMass: return convertWeightForDisplayingDecimal(value_)
            case .bodyFatPercentage, .percentage, .caloriesBurned: return Double(value_) / 1000.0
            case .length: return Double(value_) / 10.0
            case .none: return Double(value_)
            }
        }
        set {
            switch type {
            case .bodyweight, .muscleMass: value_ = convertWeightForStoring(newValue)
            case .bodyFatPercentage, .percentage, .caloriesBurned: value_ = Int64(newValue * 1000)
            case .length: value_ = Int64(newValue * 10)
            case .none: value_ = Int64(newValue)
            }
        }
    }
}
