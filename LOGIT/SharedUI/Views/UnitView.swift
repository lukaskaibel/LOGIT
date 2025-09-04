//
//  UnitView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.12.21.
//

import SwiftUI

enum UnitViewConfiguration {
    case normal, large, small
}

struct UnitView: View {
    let value: String
    let unit: String
    var configuration: UnitViewConfiguration = .normal
    var unitColor: Color = .secondaryLabel

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(configuration == .large ? .title : configuration == .small ? .subheadline : .title3)
                .fontWeight(.bold)
                .fontDesign(.rounded)
            Text(unit.uppercased())
                .foregroundStyle(unitColor)
                .font(configuration == .large ? .body : configuration == .small ? .caption2 : .subheadline)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
        }
    }
}

struct UnitView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            UnitView(value: "12", unit: "rps", configuration: .small)
            UnitView(value: "12", unit: "rps")
            UnitView(value: "12", unit: "rps", configuration: .large)
        }
    }
}
