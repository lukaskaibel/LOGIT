//
//  TemplateSetGroupDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateSetGroupDTO: Decodable {
    let exercise: ExerciseDTO
    let sets: [TemplateSetDTO]
}
