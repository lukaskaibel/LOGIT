//
//  MuscleFocusScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The target editor — "Set targets manually" in the focus picker. Two parts: the focus as it stands,
/// its name over the same pills the picker draws, and the eight muscle groups as a two-column grid,
/// each tile a weekly set target between a round minus and plus (`MuscleTargetControl`).
///
/// Targets are real numbers of sets per week, not shares and not priority levels: it is the unit
/// programs are written in, it needs no explaining, and unlike a percentage split one group's number
/// never has to move because another's did. Presets are chosen in the picker one level up; any change
/// here makes the focus "Custom", which the title says. Setting a group to 0 takes it out of the focus.
///
/// Commits on every change through the `MuscleFocusStore`, so Muscle Groups and the Summary's Balance
/// tile update live. Free — it's configuration, not analytics.
struct MuscleFocusScreen: View {
    @EnvironmentObject private var store: MuscleFocusStore

    private static let order = MuscleFocus.displayOrder

    /// The bar, the title and the tiles all sit at this inset, so they line up with each other and
    /// with the list's own cards. Not zero: a row's content is clipped to its bounds, and a bold
    /// rounded capital hard against the leading edge loses a hairline of its stem.
    private static let rowInsets = EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)

    private static let tileCornerRadius: CGFloat = 20

    var body: some View {
        List {
            focusSection
            targetSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.background)
        .contentMargins(.bottom, SCROLLVIEW_BOTTOM_PADDING, for: .scrollContent)
        .animation(.snappy(duration: 0.3), value: store.focus)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(NSLocalizedString("trainingFocus", comment: ""))
                    .font(.headline)
            }
        }
    }

    // MARK: - Focus

    /// The setting's value over the week it describes: the focus's name — a preset's, or "Custom" —
    /// above one pill per group, as tall as its target, and the week's total under them. The pills
    /// move with the controls below, which shows at a glance where the week's sets go.
    private var focusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.focus.matchingPreset?.title ?? NSLocalizedString("muscleFocusCustom", comment: ""))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.label)
                    .contentTransition(.opacity)
                MuscleFocusPillChart(focus: store.focus, scaleMax: max(store.focus.highestTarget, 1))
                Text(String(format: NSLocalizedString("muscleFocusWeeklyTotal", comment: ""), store.focus.weeklyTotal))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryLabel)
                    .monospacedDigit()
                    // A leading digit's glyph overhangs its frame, and at the row's edge it clips.
                    .padding(.leading, 2)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(Self.rowInsets)
            .listRowSeparator(.hidden)
        }
        .listSectionSpacing(.compact)
    }

    // MARK: - Targets

    /// The eight groups, two across. A grid rather than a column because each cell is a name and a
    /// number with its two buttons and nothing else — four rows of two put every group on screen at once,
    /// which is what makes the week legible as a whole.
    private var targetSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Self.order, id: \.self) { group in
                    targetTile(group)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(Self.rowInsets)
            .listRowSeparator(.hidden)
        } header: {
            Text(NSLocalizedString("setsPerWeekTitle", comment: ""))
        } footer: {
            Text(NSLocalizedString("muscleFocusTargetsFooter", comment: ""))
        }
    }

    /// One group: its name over its weekly target, with a round minus and plus either side of the
    /// number — the weekly-goal screen's own control, tinted in the muscle's colour. The unit lives
    /// once, in the section header, rather than beside eight numbers. A group at 0 gives up its colour
    /// on the name and the number — the tile saying it is out of the focus.
    private func targetTile(_ group: MuscleGroup) -> some View {
        let isExcluded = store.focus.isExcluded(group)
        return VStack(alignment: .leading, spacing: 12) {
            // Muscle names carry their colour themselves — bold, rounded, no identity dot.
            Text(group.description)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(isExcluded ? Color.secondaryLabel : group.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            MuscleTargetControl(group: group, spread: true)
                .accessibilityIdentifier("muscleTargetControl_\(group.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .background {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius, style: .continuous)
                .fill(Color.secondaryBackground)
        }
    }
}

// MARK: - Target control

/// A group's weekly set target as a number between a round minus and plus, on the focus editor's
/// tiles and in the Muscle Groups popover. Buttons wear the muscle's colour on a tinted disc, repeat while held, and give a
/// selection tick per step (held repeats included); each end greys out at its bound (0, or 1 for the last group with a target,
/// and `MuscleFocus.targetRange`'s top).
///
/// Chosen over a native `Stepper`: two capsule halves in system grey read as a form field dropped into
/// a tile, their `−`/`+` are small targets, and they carry no trace of which muscle they set.
///
/// One accessibility element, adjustable: VoiceOver reads "Legs, 10 sets per week" and swipes up or
/// down to change it.
struct MuscleTargetControl: View {
    let group: MuscleGroup
    /// Stretches across the available width — minus at the leading edge, the number centred, plus at
    /// the trailing edge — for a tile. Off keeps the three together, for the end of a row.
    var spread: Bool = false

    @EnvironmentObject private var store: MuscleFocusStore

    /// Counts every press of minus or plus, held repeats included — the trigger for the selection tick.
    /// Keyed to presses rather than to the value, so a preset changing eight targets at once doesn't
    /// tick eight controls.
    @State private var steps = 0

    private static let buttonSize: CGFloat = 36

    var body: some View {
        let target = store.focus.target(for: group)
        let lower = store.focus.minimumTarget(for: group)
        let upper = MuscleFocus.targetRange.upperBound
        return HStack(spacing: spread ? 0 : 12) {
            stepButton("minus", enabled: target > lower) { set(target - 1) }
            if spread { Spacer(minLength: 8) }
            Text("\(target)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(target == 0 ? Color.secondaryLabel : Color.label)
                .contentTransition(.numericText(value: Double(target)))
                .frame(minWidth: 40)
                .lineLimit(1)
            if spread { Spacer(minLength: 8) }
            stepButton("plus", enabled: target < upper) { set(target + 1) }
        }
        .frame(maxWidth: spread ? .infinity : nil)
        // The system's own selection feedback, kept prepared by SwiftUI. A throwaway
        // `UISelectionFeedbackGenerator` created, fired and released inside the action can drop the
        // tick or land it late.
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(group.description))
        .accessibilityValue(Text(String(format: NSLocalizedString("muscleFocusSetsPerWeekValue", comment: ""), target)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(target + 1)
            case .decrement: set(target - 1)
            @unknown default: break
            }
        }
    }

    private func set(_ value: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            store.setTarget(value, for: group)
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            steps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(group.color)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Circle().fill(group.color.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

private struct PreviewWrapperView: View {
    var body: some View {
        NavigationStack {
            MuscleFocusScreen()
        }
    }
}

struct MuscleFocusScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
