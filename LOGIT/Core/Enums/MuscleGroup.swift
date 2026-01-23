//
//  MuscleGroup.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 18.04.22.
//

import SwiftUI

public enum MuscleGroup: String, Decodable, Identifiable, CaseIterable, Comparable, Equatable {
    case chest, triceps, shoulders, biceps, back, legs, abdominals, cardio

    public var id: String { rawValue }

    var description: String {
        NSLocalizedString(rawValue, comment: "")
    }

    public static func < (lhs: MuscleGroup, rhs: MuscleGroup) -> Bool {
        return lhs.rawValue > rhs.rawValue
    }

//    var color: Color {
//        switch self {
//        case .chest: return .green
//        case .triceps: return .yellow
//        case .shoulders: return .orange
//        case .biceps: return .mint
//        case .back: return .blue
//        case .legs: return .pink
//        case .abdominals: return .brown
//        case .cardio: return .gray
//        }
//    }

//    var color: Color {
//        switch self {
//        case .chest: return Color(red: 227 / 255.0, green: 227 / 255.0, blue: 227 / 255.0)
//        case .triceps: return Color(red: 198 / 255.0, green: 198 / 255.0, blue: 198 / 255.0)
//        case .shoulders: return Color(red: 170 / 255.0, green: 170 / 255.0, blue: 170 / 255.0)
//        case .biceps: return Color(red: 142 / 255.0, green: 142 / 255.0, blue: 142 / 255.0)
//        case .back: return Color(red: 113 / 255.0, green: 113 / 255.0, blue: 113 / 255.0)
//        case .legs: return Color(red: 85 / 255.0, green: 85 / 255.0, blue: 85 / 255.0)
//        case .abdominals: return Color(red: 57 / 255.0, green: 57 / 255.0, blue: 57 / 255.0)
//        case .cardio: return Color(red: 28 / 255.0, green: 28 / 255.0, blue: 28 / 255.0)
//        }
//    }

    var color: Color {
        switch self {
        case .chest: return Color(red: 160 / 255.0, green: 210 / 255.0, blue: 120 / 255.0) // Sage green
        case .triceps: return Color(red: 100 / 255.0, green: 200 / 255.0, blue: 255 / 255.0) // Sky blue
        case .shoulders: return Color(red: 255 / 255.0, green: 170 / 255.0, blue: 100 / 255.0) // Warm peach
        case .biceps: return Color(red: 64 / 255.0, green: 224 / 255.0, blue: 208 / 255.0) // Turquoise
        case .back: return Color(red: 90 / 255.0, green: 150 / 255.0, blue: 200 / 255.0) // Steel blue
        case .legs: return Color(red: 255 / 255.0, green: 112 / 255.0, blue: 100 / 255.0) // Coral
        case .abdominals: return Color(red: 140 / 255.0, green: 120 / 255.0, blue: 200 / 255.0) // Soft violet
        case .cardio: return Color(red: 180 / 255.0, green: 160 / 255.0, blue: 220 / 255.0) // Lavender
        }
    }
}
