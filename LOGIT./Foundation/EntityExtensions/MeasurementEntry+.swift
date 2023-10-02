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
            case .bodyweight: return convertWeightForDisplaying(value_)
            case .percentage, .calories: return Int(value_ / 1000)
            case .length: return Int(value_ / 10)
            case .none: return Int(value_)
            }
        }
        set {
            switch type {
            case .bodyweight: value_ = convertWeightForStoring(Int64(newValue))
            case .percentage, .calories: value_ = Int64(newValue * 1000)
            case .length: value_ = Int64(newValue * 10)
            case .none: value_ = Int64(newValue)
            }
        }
    }

}
