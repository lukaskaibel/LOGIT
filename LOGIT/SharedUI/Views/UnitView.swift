//
//  UnitView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.12.21.
//

import SwiftUI

enum UnitViewConfiguration {
    case normal, large, small, extraSmall
}

struct UnitView: View {
    let value: String
    let unit: String
    var configuration: UnitViewConfiguration = .normal
    var unitColor: Color?
    /// Units render uppercased ("KG", "RPS") — the app-wide convention, applied here so call sites
    /// can't drift. Pass nil for phrase-like units ("of 4") that must keep their casing.
    var unitTextCase: Text.Case? = .uppercase

    private var valueFont: Font {
        switch configuration {
        case .large: .title
        case .normal: .title3
        case .small: .subheadline
        case .extraSmall: .footnote
        }
    }

    private var unitFont: Font {
        switch configuration {
        case .large: .body
        case .normal: .subheadline
        case .small, .extraSmall: .caption2
        }
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(value)
                .font(valueFont)
                .fontWeight(.bold)
                .fontDesign(.rounded)
            unitText
                .font(unitFont)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
        }
    }

    @ViewBuilder
    private var unitText: some View {
        if let unitColor {
            Text(unit)
                .textCase(unitTextCase)
                .foregroundStyle(unitColor)
        } else {
            Text(unit)
                .textCase(unitTextCase)
        }
    }
}

struct UnitView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            UnitView(value: "12", unit: "rps", configuration: .extraSmall)
            UnitView(value: "12", unit: "rps", configuration: .small)
            UnitView(value: "12", unit: "rps")
            UnitView(value: "12", unit: "rps", configuration: .large)
        }
    }
}
