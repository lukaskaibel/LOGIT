//
//  RestDurationEditorSheet.swift
//  LOGIT
//
//  Created by Codex on 22.03.26.
//

import SwiftUI

struct RestDurationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Local source of truth so the displayed time re-renders immediately on every tap. The sheet
    /// doesn't observe the underlying set, so a manual `Binding` into it persisted writes but never
    /// invalidated this view — the number and preset highlight stayed stale. We mirror the value
    /// here and write it back to the set via `applyRest` whenever it changes.
    @State private var restDurationSeconds: Int
    private let applyRest: (Int) -> Void

    private let exerciseName: String?
    private let themeColor: Color

    private let presets = [30, 45, 60, 90, 120, 180]
    private let quickAdjustments = [-15, -5, 5, 15]

    init(workoutSet: WorkoutSet) {
        _restDurationSeconds = State(initialValue: workoutSet.restDurationSeconds)
        applyRest = { workoutSet.restDurationSeconds = $0 }
        exerciseName = workoutSet.exercise?.displayName
        themeColor = workoutSet.exercise?.muscleGroup?.color ?? .accentColor
    }

    init(templateSet: TemplateSet) {
        _restDurationSeconds = State(initialValue: templateSet.restDurationSeconds)
        applyRest = { templateSet.restDurationSeconds = $0 }
        exerciseName = templateSet.exercise?.displayName
        themeColor = templateSet.exercise?.muscleGroup?.color ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("editRest", comment: ""))
                        .font(.title2.weight(.bold))

                    if let exerciseName {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.strengthtraining.traditional")
                            Text(exerciseName)
                                .lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeColor)
                    }
                }

                Spacer()

                Button(NSLocalizedString("done", comment: "")) {
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(themeColor)
            }

            VStack(spacing: 10) {
                Text(restTimeString(seconds: restDurationSeconds))
                    .font(.system(size: 56, weight: .regular).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(themeColor)
                    .contentTransition(.numericText())

                Text(NSLocalizedString("restBetweenSets", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                ForEach(quickAdjustments, id: \.self) { adjustment in
                    Button {
                        adjustRestDuration(by: adjustment)
                    } label: {
                        Text(adjustmentLabel(for: adjustment))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(adjustment < 0 ? .secondary : themeColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                adjustment < 0
                                    ? Color.fill
                                    : themeColor.secondaryTranslucentBackground
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(presets, id: \.self) { seconds in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        restDurationSeconds = seconds
                        // Picking a preset is a complete choice — dismiss so the user doesn't
                        // also have to tap Done. The brief delay lets the selection highlight and
                        // the value update register before the sheet closes.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            dismiss()
                        }
                    } label: {
                        Text(restTimeString(seconds: seconds))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(
                                restDurationSeconds == seconds
                                    ? themeColor
                                    : .secondary
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                restDurationSeconds == seconds
                                    ? themeColor.secondaryTranslucentBackground
                                    : Color.fill
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeOut(duration: 0.2)) {
                    restDurationSeconds = 0
                }
                // Removing the rest is also a complete choice — dismiss once the value has
                // animated to zero, matching the preset buttons.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    dismiss()
                }
            } label: {
                Label(NSLocalizedString("remove", comment: ""), systemImage: "xmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.fill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .onChange(of: restDurationSeconds) { _, newValue in
            applyRest(newValue)
        }
    }

    private func adjustRestDuration(by adjustment: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        restDurationSeconds = max(0, restDurationSeconds + adjustment)
    }

    private func adjustmentLabel(for adjustment: Int) -> String {
        let sign = adjustment > 0 ? "+" : ""
        return "\(sign)\(adjustment)s"
    }
}
