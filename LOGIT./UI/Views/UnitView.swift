//
//  UnitView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.12.21.
//

import SwiftUI

enum UnitViewConfiguration {
    case normal, large
}

struct UnitView: View {

    let value: String
    let unit: String
    var configuration: UnitViewConfiguration = .normal

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(value)
                .font(configuration == .large ? .title : .title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)
            Text(unit.uppercased())
                .font(configuration == .large ? .body : .subheadline)
                .fontWeight(.bold)
                .fontDesign(.rounded)
        }
    }

}

struct UnitView_Previews: PreviewProvider {
    static var previews: some View {
        UnitView(value: "12", unit: "rps")
    }
}
