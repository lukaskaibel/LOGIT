//
//  TitleUnitView.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 19.11.22.
//

import SwiftUI

struct TitleUnitView: View {
    // MARK: - Paramters

    let title: String
    let value: String
    let unit: String

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundColor(.label)
            UnitView(
                value: value,
                unit: unit
            )
        }
        .frame(minWidth: 80, alignment: .leading)
    }
}

struct TitleUnitView_Previews: PreviewProvider {
    static var previews: some View {
        TitleUnitView(title: "Chest", value: "15", unit: "%")
            .foregroundColor(.green)
    }
}
