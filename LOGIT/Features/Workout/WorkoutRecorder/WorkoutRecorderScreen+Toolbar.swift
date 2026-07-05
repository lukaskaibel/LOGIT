//
//  WorkoutRecorderScreen+Toolbar.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 14.06.23.
//

import SwiftUI

extension WorkoutRecorderScreen {
    var ToolbarItemsKeyboard: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            HStack {
                Spacer()
                if focusedIntegerFieldIndex != nil {
                    Button {
                        focusedIntegerFieldIndex = nil
                        // Defer so the keyboard's dismissal and the reorder sheet's
                        // presentation land in separate transactions — same
                        // entanglement the workout editor documents on its
                        // editDateTime button; here it hangs the presentation.
                        DispatchQueue.main.async {
                            isShowingReorderSheet = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .keyboardToolbarButtonStyle()
                    }
                    let previousIndex = previousIntegerFieldIndex()
                    let nextIndex = nextIntegerFieldIndex()
                    HStack(spacing: 0) {
                        Button {
                            focusedIntegerFieldIndex = previousIndex
                        } label: {
                            Image(systemName: "chevron.up")
                                .foregroundColor(
                                    previousIndex == nil ? Color.placeholder : .label
                                )
                                .keyboardToolbarButtonStyle()
                        }
                        .disabled(previousIndex == nil)
                        Button {
                            focusedIntegerFieldIndex = nextIndex
                        } label: {
                            Image(systemName: "chevron.down")
                                .foregroundColor(
                                    nextIndex == nil ? Color.placeholder : .label
                                )
                                .keyboardToolbarButtonStyle()
                        }
                        .disabled(nextIndex == nil)
                    }
                }
                Button {
                    if focusedIntegerFieldIndex == nil {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } else {
                        focusedIntegerFieldIndex = nil
                    }
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .keyboardToolbarButtonStyle()
                }
                if focusedIntegerFieldIndex != nil {
                    Spacer()
                }
            }
        }
    }
}
