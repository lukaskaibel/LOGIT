//
//  TileStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 27.07.23.
//

import SwiftUI

struct TileModifier: ViewModifier {
    var backgroundColor: Color = .secondaryBackground

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(30)
    }
}

struct SecondaryTileModifier: ViewModifier {
    var backgroundColor: Color = .tertiaryBackground
    /// Recesses the tile with the same inner shadow the workout set cells carry. Off by default
    /// because this style is also worn by the set-entry fields (`IntegerField`/`DecimalField`),
    /// whose near-transparent background would render the shadow as a dark ring around the number.
    var insetShadow: Bool = false

    private let cornerRadius: CGFloat = 25

    func body(content: Content) -> some View {
        content
            .background {
                if insetShadow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.shadow(.inner(color: .black.opacity(0.4), radius: 5)))
                        .foregroundStyle(backgroundColor)
                } else {
                    backgroundColor
                }
            }
            .cornerRadius(cornerRadius)
    }
}

struct TileSparklineChartModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartPlotStyle { plotArea in
                plotArea
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
            }
            .frame(width: 120, height: 70)
            .tileSparklineFadeMask()
    }
}

extension View {
    func tileStyle(backgroundColor: Color = .secondaryBackground) -> some View {
        modifier(TileModifier(backgroundColor: backgroundColor))
    }

    func secondaryTileStyle(backgroundColor: Color = .tertiaryBackground, insetShadow: Bool = false) -> some View {
        modifier(SecondaryTileModifier(backgroundColor: backgroundColor, insetShadow: insetShadow))
    }

    func tileSparklineChartStyle() -> some View {
        modifier(TileSparklineChartModifier())
    }
}

struct TileStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Hello World")
                .padding()
                .tileStyle()
            Text("Hello World")
                .padding()
                .secondaryTileStyle()
                .padding()
                .tileStyle()
        }
    }
}
