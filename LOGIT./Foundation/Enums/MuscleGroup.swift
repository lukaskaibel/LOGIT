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
        case .chest: return Color(red: 156 / 255.0, green: 199 / 255.0, blue: 109 / 255.0) // Teal/Blue
        case .triceps: return Color(red: 18 / 255.0, green: 226 / 255.0, blue: 241 / 255.0) // Magenta
        case .shoulders: return Color(red: 252 / 255.0, green: 159 / 255.0, blue: 91 / 255.0) // Cyan
        case .biceps: return Color(red: 45 / 255.0, green: 255 / 255.0, blue: 223 / 255.0) // Navy Blue
        case .back: return Color(red: 77 / 255.0, green: 134 / 255.0, blue: 165 / 255.0) // Orange
        case .legs: return Color(red: 214 / 255.0, green: 11 / 255.0, blue: 45 / 255.0) // Red
        case .abdominals: return Color(red: 62 / 255.0, green: 81 / 255.0, blue: 122 / 255.0) // Bright Green (unchanged)
        case .cardio: return Color(red: 195 / 255.0, green: 196 / 255.0, blue: 233 / 255.0) // Grayish (unchanged)
        }
    }
}
