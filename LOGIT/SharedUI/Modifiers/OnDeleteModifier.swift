//
//  OnDeleteModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct OnDeleteModifier: ViewModifier {
    let action: () -> Void
    
    @State private var size: CGSize = .zero
    @State private var hasLoaded = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SizePreferenceKey.self, value: proxy.size)
                    }
                )
                .suppressIntegerFieldFocus(true)
                .onPreferenceChange(SizePreferenceKey.self) { newSize in
                    size = newSize
                }
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
            .frame(height: size == .zero ? nil : size.height)
        }
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
