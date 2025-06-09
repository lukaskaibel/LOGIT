//
//  TemplateDTO.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 05.10.23.
//

import Foundation

struct TemplateDTO: Decodable {
    let name: String
    let setGroups: [TemplateSetGroupDTO]
}
