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
