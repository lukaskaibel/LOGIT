//
//  OnDeleteModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI

struct OnDeleteModifier: ViewModifier {
    let action: () -> Void

    @State var offset: CGSize = .zero
    @State var initialOffset: CGSize = .zero
    @State var contentWidth: CGFloat = 0.0
    @State var willDeleteIfReleased = false

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    ZStack {
                        Rectangle()
                            .foregroundColor(.red)
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .font(.title2.bold())
                            .layoutPriority(-1)
                    }
                    .frame(width: -offset.width)
                    .clipped()
                    .offset(x: geometry.size.width)
                    .onAppear {
                        contentWidth = geometry.size.width
                    }
                    .gesture(
                        TapGesture()
                            .onEnded {
                                delete()
                            }
                    )
                }
            )
            .offset(x: offset.width, y: 0)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width + initialOffset.width <= 0 {
                            self.offset.width = gesture.translation.width + initialOffset.width
                        }
                        if self.offset.width < -deletionDistance, !willDeleteIfReleased {
                            hapticFeedback()
                            willDeleteIfReleased.toggle()
                        } else if offset.width > -deletionDistance, willDeleteIfReleased {
                            hapticFeedback()
                            willDeleteIfReleased.toggle()
                        }
                    }
                    .onEnded { _ in
                        if offset.width < -deletionDistance {
                            delete()
                        } else if offset.width < -halfDeletionDistance {
                            offset.width = -tappableDeletionWidth
                            initialOffset.width = -tappableDeletionWidth
                        } else {
                            offset = .zero
                            initialOffset = .zero
                        }
                    }
            )
            .animation(.interactiveSpring())
    }

    private func delete() {
        offset.width = -contentWidth
        action()
    }

    private func hapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: Constants

    let deletionDistance = CGFloat(200)
    let halfDeletionDistance = CGFloat(50)
    let tappableDeletionWidth = CGFloat(100)
}

extension View {
    func onDelete(disabled: Bool = false, perform action: @escaping () -> Void) -> some View {
        Group {
            if disabled {
                self
            } else {
                self.modifier(OnDeleteModifier(action: action))
            }
        }
    }
}
