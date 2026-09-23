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
/// "Set targets manually" pushes the number editor, starting from the tile you're on. Its check saves
/// the targets and closes the sheet, so setting them up by hand ends where it's done; going back keeps
/// them here as a "Custom" tile, selected and waiting for the button like any other. Custom targets in
/// force get that tile too, first and selected, so reopening the sheet shows what's in force above
/// the alternatives: its button edits them, and choosing a preset instead asks first, since it
/// replaces numbers the user set by hand.
struct MuscleFocusPickerSheet: View {
    @EnvironmentObject private var store: MuscleFocusStore
    @Environment(\.dismiss) private var dismiss

    /// One tile's worth of choice: the user's own targets, or a preset.
    private enum Choice: Equatable {
        case custom
        case preset(MuscleFocusPreset)
    }

    /// The tile the user is on. Starts on what's in force — a preset's tile, or the custom one — and on
    /// nothing before any choice: there is no default focus, so nothing is pre-picked for the user.
    @State private var selection: Choice?
    @State private var hasLoadedSelection = false
    /// Targets set up in the editor and not saved yet — its back button leaves them here rather than
    /// dropping them.
    @State private var draft: MuscleFocus?
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

    /// What the custom tile shows — targets still being set up, else the custom ones in force. Nil
    /// hides the tile: without custom targets, "Set targets manually" is the way to them.
    private var customFocus: MuscleFocus? {
        draft ?? (hasCustomTargets ? store.focus : nil)
    }

    /// The custom tile holds targets that aren't in force yet, so its button saves them.
    private var hasUnsavedDraft: Bool {
        guard let draft else { return false }
        return !store.hasChosenFocus || draft != store.focus
    }

    private var goal: Int { store.workoutsPerWeekToSizeFor }

    /// One scale for every tile, so a taller pill means more sets wherever it stands.
    private var scaleMax: Int {
        let presetMax = MuscleFocusPreset.allCases.map { $0.focus(forWorkoutsPerWeek: goal).highestTarget }.max() ?? 1
        return max(presetMax, customFocus?.highestTarget ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                        .padding(.bottom, 10)
                    if let customFocus {
                        customTile(customFocus)
                    }
                    ForEach(MuscleFocusPreset.allCases) { preset in
                        presetTile(preset)
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
                MuscleFocusScreen(focus: Binding(
                    get: { draft ?? store.focus },
                    set: { draft = $0 }
                )) {
                    if let draft {
                        store.apply(focus: draft)
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !hasLoadedSelection else { return }
            hasLoadedSelection = true
            selection = inForceChoice
        }
        .onChange(of: isShowingEditor) { _, isShowing in
            if !isShowing {
                settleDraft()
            }
        }
    }

    /// The tile for what's in force, nil before any choice.
    private var inForceChoice: Choice? {
        guard store.hasChosenFocus else { return nil }
        return store.focus.matchingPreset.map(Choice.preset) ?? .custom
    }

    /// Back from the editor: targets left as they are in force need no saving, targets that came out
    /// as a preset's numbers are that preset, and anything else stays as the custom tile, selected.
    private func settleDraft() {
        guard let draft else { return }
        if !hasUnsavedDraft {
            self.draft = nil
            selection = inForceChoice
        } else if let preset = MuscleFocusPreset.allCases.first(where: { draft.hasSameTargets(as: $0.focus(forWorkoutsPerWeek: goal)) }) {
            self.draft = nil
            selection = .preset(preset)
        } else {
            selection = .custom
        }
    }

    /// Opens the editor on the tile you're on: the custom targets, a preset's numbers to adjust, or —
    /// with nothing picked — the week the app would measure against anyway.
    private func openEditor() {
        switch selection {
        case .preset(let preset):
            draft = preset.focus(forWorkoutsPerWeek: goal)
        case .custom, nil:
            draft = customFocus ?? store.focus
        }
        isShowingEditor = true
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

    private func presetTile(_ preset: MuscleFocusPreset) -> some View {
        tile(
            .preset(preset),
            title: preset.title,
            summary: preset.summary,
            focus: preset.focus(forWorkoutsPerWeek: goal),
            identifier: "muscleFocusPreset_\(preset.rawValue)"
        )
    }

    private func customTile(_ focus: MuscleFocus) -> some View {
        tile(
            .custom,
            title: NSLocalizedString("muscleFocusCustom", comment: ""),
            summary: NSLocalizedString("muscleFocusCustomSummary", comment: ""),
            focus: focus,
            identifier: "muscleFocusCustomTile"
        )
    }

    /// One choice: its name and what it raises, over its week as pills. The selected tile takes the
    /// accent as its fill, name and check — the way iOS marks a chosen option — rather than an
    /// outline, which reads as a focus ring.
    private func tile(_ choice: Choice, title: String, summary: String, focus: MuscleFocus, identifier: String) -> some View {
        let isSelected = selection == choice
        return Button {
            guard !isScrolling, Date.now.timeIntervalSince(lastScrolled) > 0.25 else { return }
            withAnimation(.snappy(duration: 0.2)) {
                selection = choice
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.label)
                        // Two lines reserved on every tile, so the pills line up down the sheet
                        // whichever description wraps.
                        Text(summary)
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
                MuscleFocusPillChart(focus: focus, scaleMax: scaleMax)
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
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(summary))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Actions

    /// The commit, pinned under the tiles. On a preset it takes that preset; on the custom tile it
    /// edits the targets in force, or saves ones still being set up. Before anything is picked there
    /// is nothing to commit, so only the manual way in shows — the tiles are the call to action. While
    /// the custom tile is on screen it is the manual way in, so the link doesn't repeat it.
    private var actions: some View {
        VStack(spacing: 4) {
            switch selection {
            case nil:
                manualButton
            case .preset(let preset):
                Button {
                    commit(preset)
                } label: {
                    Text(String(format: NSLocalizedString("muscleFocusUsePreset", comment: ""), preset.title))
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
                    presenting: preset
                ) { preset in
                    Button(String(format: NSLocalizedString("muscleFocusUsePreset", comment: ""), preset.title), role: .destructive) {
                        apply(preset)
                    }
                    Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
                } message: { _ in
                    Text(NSLocalizedString("muscleFocusReplaceCustomMessage", comment: ""))
                }
                if customFocus == nil {
                    manualButton
                }
            case .custom:
                if hasUnsavedDraft, let draft {
                    Button {
                        store.apply(focus: draft)
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("muscleFocusUseCustom", comment: ""))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("muscleFocusCommitButton")
                    Button {
                        openEditor()
                    } label: {
                        Text(NSLocalizedString("muscleFocusEditTargets", comment: ""))
                            .font(.subheadline.weight(.semibold))
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("muscleFocusManualButton")
                } else {
                    Button {
                        openEditor()
                    } label: {
                        Text(NSLocalizedString("muscleFocusEditTargets", comment: ""))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("muscleFocusCommitButton")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var manualButton: some View {
        Button {
            openEditor()
        } label: {
            Text(NSLocalizedString("muscleFocusSetManually", comment: ""))
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("muscleFocusManualButton")
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
