//
//  OnDeleteModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

/// Swipe-to-delete for a view that isn't in a `List`: the row is rendered twice inside a
/// ZStack — once invisibly, purely to lay out and measure it, and once inside a one-row `List`
/// that contributes nothing but the swipe action.
///
/// That `List` is a UIKit collection view and takes *every* point proposed to it, so it must be
/// pinned to the measured height or it deforms whatever contains it. The recorder proposes a
/// screenful of scroll slack to its cards (`minScrollContentHeight`), and an unpinned row spread
/// that slack between the sets — a card with two sets drew them a third of a screen apart.
/// Hence: measure with `onGeometryChange` (the preference-key version this used to do never
/// delivered a size, leaving the height nil — i.e. greedy — forever), and `fixedSize` the stack
/// so the row's height is the measured content's whatever the `List` reports.
struct OnDeleteModifier: ViewModifier {
    let action: () -> Void

    /// The row's own height. Nil until measured — the `List` stays unconstrained for that first
    /// frame, which `fixedSize` below keeps from mattering.
    @State private var contentHeight: CGFloat?

    func body(content: Content) -> some View {
        ZStack {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    contentHeight = newHeight
                }
                .suppressIntegerFieldFocus(true)
                .opacity(0.000001)
                .allowsHitTesting(false)
                .disabled(true)
                .accessibilityHidden(true)
            List {
                ForEach([0], id:\.self) { _ in
                    content
                        .buttonStyle(BorderlessButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button(role: .destructive) {
                                action()
                            } label: {
                                Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                            }
                        }
                }
            }
            .contentMargins(.top, 0)
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: contentHeight)
        }
        // The row is as tall as its content lays out, never as tall as it is offered.
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func onDeleteView(disabled: Bool = false, perform action: @escaping () -> Void) -> some View {
        Group {
            if disabled {
                self
            } else {
                self.modifier(OnDeleteModifier(action: action))
            }
        }
    }
}
