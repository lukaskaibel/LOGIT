//
//  Calendar+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 28.08.24.
//

import Foundation

extension Calendar {
    func isDate(
        _ date1: Date,
        equalTo date2: Date,
        toGranularity components: [Calendar.Component]
    ) -> Bool {
        components
            .map {
                Calendar.current.isDate(
                    date1,
                    equalTo: date2,
                    toGranularity: $0
                )
            }
            .reduce(true) { $0 && $1 }
    }
}
