//
//  WeightConverting.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 02.10.23.
//

import Foundation

private let KG_TO_GRAMS: Int = 1000
private let LBS_TO_GRAMS: Int = 454

public func convertWeightForStoring(_ value: Int64) -> Int64 {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return value * Int64(KG_TO_GRAMS)
    case .lbs: return value * Int64(LBS_TO_GRAMS)
    }
}

public func convertWeightForDisplaying(_ value: Int64) -> Int {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return Int(round(Float(value) / Float(KG_TO_GRAMS)))
    case .lbs: return Int(round(Float(value) / Float(LBS_TO_GRAMS)))
    }
}

public func convertWeightForDisplaying(_ value: Int) -> Int {
    let unit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "weightUnit")!)!
    switch unit {
    case .kg: return Int(round(Float(value) / Float(KG_TO_GRAMS)))
    case .lbs: return Int(round(Float(value) / Float(LBS_TO_GRAMS)))
    }
}
