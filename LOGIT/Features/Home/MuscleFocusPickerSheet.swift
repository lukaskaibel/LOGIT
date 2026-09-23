//
//  MuscleFocusPickerSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.09.26.
//

import SwiftUI

// MARK: - Picker

/// "What do you want to focus on?" — the one place a training focus is chosen. Five body areas as
/// tiles, each with a line on what it raises and its week drawn as one pill per muscle group, then a
/// button that commits the tile you're on.
///
/// Opened from the Balance tile before any focus is chosen (the tile asks for one instead of
/// recommending anything) and from the Muscle Groups toolbar after. Tapping a tile only selects it,
/// so the weeks can be compared before anything changes; the button is the commit. The numbers are
/// sized for the user's weekly workout goal as it stands, and the lead says which goal that is.
///
/// "Set targets manually" pushes the number editor for anyone who wants their own split. With custom
/// targets in force no tile is selected and the button edits them instead; choosing a preset then
/// asks first, since it replaces numbers the user set by hand.
struct MuscleFocusPickerSheet: View {
    @EnvironmentObject private var store: MuscleFocusStore
    @Environment(\.dismiss) private var dismiss

    /// The tile the user is on. Starts on the preset in force, and on nothing before any choice or
    /// for custom targets: there is no default focus, so nothing is pre-picked for the user.
    @State private var selection: MuscleFocusPreset?
    @State private var hasLoadedSelection = false
    @State private var isShowingEditor = false
    @State private var isConfirmingReplace = false
    /// Whether the list is moving, and when it last was. A drag that starts on a tile carries the tile
    /// along under the finger, and inside a sheet the lift can still land as a tap on it — which
    /// selected whatever tile the scroll began on. Taps while the list moves, or right after, are
    /// ignored.
    @State private var isScrolling = false
    @State private var lastScrolled = Date.distantPast

    /// Custom targets are in force: no preset describes them, and a preset would replace them.
    private var hasCustomTargets: Bool {
        store.hasChosenFocus && store.focus.matchingPreset == nil
    }

    private var goal: Int { store.workoutsPerWeekToSizeFor }

    /// One scale for every tile, so a taller pill means more sets wherever it stands.
    private var scaleMax: Int {
        MuscleFocusPreset.allCases.map { $0.focus(forWorkoutsPerWeek: goal).highestTarget }.max() ?? 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                        .padding(.bottom, 10)
                    ForEach(MuscleFocusPreset.allCases) { preset in
                        tile(preset)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { oldPhase, newPhase in
                // `.tracking` is a finger resting on the list — every plain tap passes through it —
                // so only real movement counts.
                let moving: (ScrollPhase) -> Bool = { [.interacting, .decelerating, .animating].contains($0) }
                isScrolling = moving(newPhase)
                if moving(oldPhase) || moving(newPhase) {
                    lastScrolled = .now
                }
            }
            .safeAreaBar(edge: .bottom) {
                actions
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("muscleFocusPickerClose")
                }
            }
            .navigationDestination(isPresented: $isShowingEditor) {
                MuscleFocusScreen()
            }
        }
        .onAppear {
            guard !hasLoadedSelection else { return }
            hasLoadedSelection = true
            selection = store.hasChosenFocus ? store.focus.matchingPreset : nil
        }
        // The editor commits as it goes; coming back from it, the tiles say what it left behind.
        .onChange(of: store.focus) { _, focus in
            selection = focus.matchingPreset
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("muscleFocusPickerTitle", comment: ""))
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(lead)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    /// Which week the numbers below were sized for — the user's goal, or the base week without one.
    private var lead: String {
        guard let workoutGoal = store.workoutGoal else {
            return String(format: NSLocalizedString("muscleFocusPickerLeadNoGoal", comment: ""), MuscleFocus.baseWorkoutsPerWeek)
        }
        if workoutGoal == 1 {
            return NSLocalizedString("muscleFocusPickerLeadOne", comment: "")
        }
        return String(format: NSLocalizedString("muscleFocusPickerLead", comment: ""), workoutGoal)
    }

    // MARK: - Tiles

    /// One area: its name and what it raises, over its week as pills. The selected tile takes the
    /// accent as its fill, name and check — the way iOS marks a chosen option — rather than an
    /// outline, which reads as a focus ring.
    private func tile(_ preset: MuscleFocusPreset) -> some View {
        let isSelected = selection == preset
        return Button {
            guard !isScrolling, Date.now.timeIntervalSince(lastScrolled) > 0.25 else { return }
            withAnimation(.snappy(duration: 0.2)) {
                selection = preset
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.label)
                        // Two lines reserved on every tile, so the pills line up down the sheet
                        // whichever description wraps.
                        Text(preset.summary)
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? Color.accentColor.opacity(0.8) : Color.secondaryLabel)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Color.background)
                    }
                    .frame(width: 22, height: 22)
                    .opacity(isSelected ? 1 : 0)
                }
                MuscleFocusPillChart(focus: preset.focus(forWorkoutsPerWeek: goal), scaleMax: scaleMax)
            }
            .padding(CELL_PADDING)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondaryBackground)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(preset.title))
        .accessibilityHint(Text(preset.summary))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("muscleFocusPreset_\(preset.rawValue)")
    }

    // MARK: - Actions

    /// The commit, pinned under the tiles. On a preset it takes that preset; on custom targets it
    /// opens them instead, and the manual link would only repeat it. Before anything is picked there
    /// is nothing to commit, so only the manual way in shows — the tiles are the call to action.
    private var actions: some View {
        VStack(spacing: 4) {
            if !hasCustomTargets, selection == nil {
                Button {
                    isShowingEditor = true
                } label: {
                    Text(NSLocalizedString("muscleFocusSetManually", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("muscleFocusManualButton")
            } else if let selection {
                Button {
                    commit(selection)
                } label: {
                    Text(String(format: NSLocalizedString("muscleFocusUsePreset", comment: ""), selection.title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("muscleFocusCommitButton")
                // On the button, so on iOS 26 the dialog points at what asked for it.
                .confirmationDialog(
                    NSLocalizedString("muscleFocusReplaceCustomTitle", comment: ""),
                    isPresented: $isConfirmingReplace,
                    titleVisibility: .visible,
                    presenting: selection
                ) { preset in
                    Button(String(format: NSLocalizedString("muscleFocusUsePreset", comment: ""), preset.title), role: .destructive) {
                        apply(preset)
                    }
                    Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
                } message: { _ in
                    Text(NSLocalizedString("muscleFocusReplaceCustomMessage", comment: ""))
                }
                Button {
                    isShowingEditor = true
                } label: {
                    Text(NSLocalizedString("muscleFocusSetManually", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("muscleFocusManualButton")
            } else {
                Button {
                    isShowingEditor = true
                } label: {
                    Text(NSLocalizedString("muscleFocusEditTargets", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("muscleFocusCommitButton")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func commit(_ preset: MuscleFocusPreset) {
        if hasCustomTargets {
            isConfirmingReplace = true
        } else {
            apply(preset)
        }
    }

    private func apply(_ preset: MuscleFocusPreset) {
        store.apply(preset: preset)
        dismiss()
    }
}

// MARK: - Pills

/// A focus's week as one pill per muscle group, in `MuscleFocus.displayOrder`: each pill as tall as
/// the group's weekly target, the number inside it, the group's letters beneath. The shape the balance
/// charts draw, standing for targets instead of progress, so the picker previews what Muscle Groups
/// will measure.
///
/// Heights are on the scale the caller passes, so charts meant to be compared share one. A pill never
/// gets shorter than it is wide — a small target is a circle with its number, not a sliver — and a
/// group with no target keeps its place as an empty ring, so the eight columns never shift.
struct MuscleFocusPillChart: View {
    let focus: MuscleFocus
    /// The target the full height stands for.
    let scaleMax: Int
    var height: CGFloat = 64
    var pillWidth: CGFloat = 22

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(MuscleFocus.displayOrder, id: \.self) { group in
                VStack(spacing: 6) {
                    pill(group)
                        .frame(height: height, alignment: .bottom)
                    Text(group.abbreviation)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(focus.isExcluded(group) ? Color.secondaryLabel : group.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.snappy(duration: 0.25), value: focus)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func pill(_ group: MuscleGroup) -> some View {
        let target = focus.target(for: group)
        let pillHeight = target == 0
            ? pillWidth
            : max(pillWidth, height * CGFloat(target) / CGFloat(max(scaleMax, 1)))
        return ZStack(alignment: .bottom) {
            if target == 0 {
                Capsule(style: .continuous)
                    .strokeBorder(Color.label.opacity(0.16), lineWidth: 1.5)
            } else {
                Capsule(style: .continuous)
                    .fill(group.color)
            }
            // Centred in the pill's bottom circle: the middle of a circle, the foot of a tall pill.
            Text("\(target)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(target == 0 ? Color.secondaryLabel : Color.black.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: pillWidth, height: pillWidth)
                .contentTransition(.numericText(value: Double(target)))
        }
        .frame(width: pillWidth, height: pillHeight)
    }

    private var accessibilityLabel: Text {
        Text(
            MuscleFocus.displayOrder
                .map { group in
                    group.description + ", "
                        + String(format: NSLocalizedString("muscleFocusSetsPerWeekValue", comment: ""), focus.target(for: group))
                }
                .joined(separator: "; ")
        )
    }
}

// MARK: - Names

/// The recommendation's groups by name — "Legs & Back" — each in its own colour, the joiner in
/// secondary grey so two colours don't run together into one word.
struct MuscleFocusNames: View {
    let groups: [MuscleGroup]

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, group) in groups.enumerated() {
            if index > 0 {
                var joiner = AttributedString(NSLocalizedString("muscleFocusNamesJoiner", comment: ""))
                joiner.foregroundColor = Color.secondaryLabel
                result += joiner
            }
            var name = AttributedString(group.description)
            name.foregroundColor = group.color
            result += name
        }
        return result
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MuscleFocusPickerSheet()
        }
        .previewEnvironmentObjects()
}
