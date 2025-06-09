//
//  String+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.09.23.
//

import Foundation

extension String {
    var firstLetterLowercased: String {
        guard !isEmpty else { return self }
        return first!.lowercased() + dropFirst()
    }

    var firstLetterUppercased: String {
        return
            replacingOccurrences(of: "(?<=.)([A-Z])", with: " $1", options: .regularExpression)
                .capitalized
                .replacingOccurrences(of: " ", with: "")
    }
}
