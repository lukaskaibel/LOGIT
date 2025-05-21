//
//  WorkoutRecorderView+Toolbar.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 14.06.23.
//

import SwiftUI

extension WorkoutRecorderScreen {

    internal var ToolbarItemsKeyboard: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            HStack {
                Spacer()
                if focusedIntegerFieldIndex != nil {
                    if let workoutSet = selectedWorkoutSet {
                        if let templateSet = workoutRecorder.templateSet(for: workoutSet), templateSet.hasEntry {
                            Button {
                                workoutRecorder.toggleSetCompleted(for: workoutSet)
                            } label: {
                                Image(systemName: "\(workoutSet.hasEntry ? "xmark" : "checkmark")")
                                    .keyboardToolbarButtonStyle()
                            }
                        } else {
                            Button {
                                workoutRecorder.toggleCopyPrevious(for: workoutSet)
                            } label: {
                                Image(systemName: "\(workoutSet.hasEntry ? "xmark" : "plus.square.on.square")")
                                    .foregroundColor(
                                        !(workoutSet.previousSetInSetGroup?.hasEntry ?? false)
                                            && !workoutSet.hasEntry
                                            ? Color.placeholder : .primary
                                    )
                                    .keyboardToolbarButtonStyle()
                            }
                            .disabled(
                                !(workoutSet.previousSetInSetGroup?.hasEntry ?? false)
                                    && !workoutSet.hasEntry
                            )
                        }
                    }
                    HStack(spacing: 0) {
                        Button {
                            focusedIntegerFieldIndex = previousIntegerFieldIndex()
                        } label: {
                            Image(systemName: "chevron.up")
                                .foregroundColor(
                                    previousIntegerFieldIndex() == nil ? Color.placeholder : .label
                                )
                                .keyboardToolbarButtonStyle()
                        }
                        .disabled(previousIntegerFieldIndex() == nil)
                        Button {
                            focusedIntegerFieldIndex = nextIntegerFieldIndex()
                        } label: {
                            Image(systemName: "chevron.down")
                                .foregroundColor(
                                    nextIntegerFieldIndex() == nil ? Color.placeholder : .label
                                )
                                .keyboardToolbarButtonStyle()
                        }
                        .disabled(nextIntegerFieldIndex() == nil)
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
