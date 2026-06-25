//
//  View+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.09.23.
//

import SwiftUI

/*
 extension View {

     @ViewBuilder
     public func navigationDestination<D, C>(
         item: Binding<D?>,
         @ViewBuilder destination: @escaping (D) -> C
     ) -> some View where D: Hashable, C: View {
         let isPresented = Binding(
             get: { item.wrappedValue != nil },
             set: { item.wrappedValue = $0 ? item.wrappedValue : nil }
         )
         if let item = item.wrappedValue {
             self
                 .navigationDestination(isPresented: isPresented, destination: { destination(item) })
         } else {
             self
         }
     }

 }
 */

extension View {
    /// Fills the view's content with a single `ShapeStyle` resolved across the *whole* view's bounds,
    /// so a gradient reads as one continuous sweep over a multi-part view — a `UnitView`'s value+unit,
    /// a pill's icon+label — instead of SwiftUI restarting the gradient inside each child `Text`/
    /// `Image`. Implemented by masking one full-bounds fill with the content's shape.
    ///
    /// For a flat `Color` it matches `.foregroundStyle`. Note it paints the entire content with the
    /// one style, overriding any per-child color override — use it only where the whole content is
    /// meant to share the single style.
    func continuousForegroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        overlay { Rectangle().fill(style).mask { self } }
    }
}
