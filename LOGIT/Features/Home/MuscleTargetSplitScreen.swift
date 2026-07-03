//
//  MuscleTargetSplitScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The target-split editor (`muscle-group-screens.html` screen 3): preset chips, a per-group stepper
/// list, a live Total row, the threshold note, and a reset. Binds the `MuscleTargetSplitStore` and
/// commits on every change, so the overview and the Summary tile update live. Free — it's
/// configuration, not analytics.
struct MuscleTargetSplitScreen: View {
    @EnvironmentObject private var store: MuscleTargetSplitStore

    /// Descending by the balanced default, matching the editor mockup's row order.
    private let order: [MuscleGroup] = [.legs, .back, .chest, .shoulders, .biceps, .triceps, .abdominals, .cardio]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("targetSplitIntro", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                presetChips
                rows
                totalRow
                thresholdNote
                resetButton
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("targetSplit", comment: ""))
                    .font(.headline)
            }
        }
    }

    private var presetChips: some View {
        HStack(spacing: 8) {
            ForEach(MuscleTargetPreset.allCases) { preset in
                let isOn = store.split.matchingPreset == preset
                Button {
                    withAnimation { store.apply(preset: preset) }
                } label: {
                    Text(preset.title)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondaryBackground)))
                        .foregroundStyle(isOn ? Color.black : Color.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element) { index, group in
                row(group)
                if index < order.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .tileStyle()
    }

    private func row(_ group: MuscleGroup) -> some View {
        HStack(spacing: 11) {
            // Muscle names carry their colour themselves — bold, rounded, no identity dot.
            Text(group.description)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(group.color)
            Spacer()
            stepper(group)
        }
        .padding(.vertical, 10)
    }

    private func stepper(_ group: MuscleGroup) -> some View {
        let value = store.target(for: group)
        return HStack(spacing: 0) {
            Button {
                store.setTarget(value - 1, for: group)
            } label: {
                Image(systemName: "minus").frame(width: 34, height: 32)
            }
            Text("\(value)%")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .frame(width: 46)
            Button {
                store.setTarget(value + 1, for: group)
            } label: {
                Image(systemName: "plus").frame(width: 34, height: 32)
            }
        }
        .foregroundStyle(Color.label)
        .background(Capsule().fill(Color.fill))
        .buttonStyle(.plain)
    }

    private var totalRow: some View {
        HStack {
            Text(NSLocalizedString("total", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.split.total)%")
                .font(.headline)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(store.split.total == 100 ? Color.accentColor : Color.label)
                .contentTransition(.numericText())
                .animation(.snappy, value: store.split.total)
        }
        .padding(.horizontal, 4)
    }

    private var thresholdNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
            Text(String(format: NSLocalizedString("targetSplitThresholdNote", comment: ""), MuscleTargetSplit.behindThreshold))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var resetButton: some View {
        Button {
            withAnimation { store.resetToDefault() }
        } label: {
            Text(NSLocalizedString("resetToDefaults", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }
}

private struct PreviewWrapperView: View {
    var body: some View {
        NavigationStack {
            MuscleTargetSplitScreen()
        }
    }
}

struct MuscleTargetSplitScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
