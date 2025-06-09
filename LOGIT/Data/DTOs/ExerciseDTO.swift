//
//  ExerciseDTO.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 04.10.23.
//

import Foundation

struct ExerciseDTO: Decodable {
    let name: String?
    // Had to use 'type' instead of 'muscleGroup', because ChatGPT would always make up new muscle groups
    let type: MuscleGroup?
}
