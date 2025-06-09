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
            .cornerRadius(20)
    }
}

struct SecondaryTileModifier: ViewModifier {
    var backgroundColor: Color = .tertiaryBackground

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .cornerRadius(15)
    }
}

extension View {
    func tileStyle(backgroundColor: Color = .secondaryBackground) -> some View {
        modifier(TileModifier(backgroundColor: backgroundColor))
    }

    func secondaryTileStyle(backgroundColor: Color = .tertiaryBackground) -> some View {
        modifier(SecondaryTileModifier(backgroundColor: backgroundColor))
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
