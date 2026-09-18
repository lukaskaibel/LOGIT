//
//  SummaryTrendSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI
import TipKit

// MARK: - Trend pair

/// The Summary's opening band: the Strength + Balance pair. It leads because both halves always
/// render and barely move window to window, which makes them a stable anchor for the screen.
///
/// Both tiles read the screen's selected `TrendWindow` — the same one the four stat tiles and the
/// pinned exercise tiles below them read. That is why neither carries a caption naming its period:
/// there is one timeframe on this screen and the picker above already names it.
struct SummaryTrendPair: View {
    let workouts: [Workout]
    /// The Summary's one timeframe — see `TrendWindow`.
    let window: TrendWindow

    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var focusStore: MuscleFocusStore
    @State private var strength: StrengthProgress = .empty

    private let focusTip = MuscleFocusTip()
    /// TipKit's own verdict — false once the tip was closed or acted on, on any launch.
    @State private var focusTipEligible = false

    /// The workouts inside the selected window — what Balance reports over.
    private var currentWindowWorkouts: [Workout] {
        workouts.filter { workout in
            guard !workout.isEmpty, let date = workout.date else { return false }
            return window.contains(date)
        }
    }

    /// The tip shows only when all three hold: TipKit hasn't retired it, the user never chose a focus,
    /// and there is a balance to be measured at all — before the first sets, "measured against what?"
    /// isn't a question anyone is asking yet.
    private var showsFocusTip: Bool {
        focusTipEligible && !focusStore.hasChosenFocus && !currentWindowWorkouts.isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            pair
            if showsFocusTip {
                // Inline, not a popover: a popover is presented over the screen and swallows the first
                // tap anywhere, which on a first launch is a tap the user meant for something else.
                // No arrow either — TipView centres it, which would point between the two tiles.
                // Qualified: the app has a `TipView` of its own.
                TipKit.TipView(focusTip)
                    .tipViewStyle(MuscleFocusTipStyle { action in
                        guard action.id == MuscleFocusTip.chooseFocusActionID else { return }
                        focusTip.invalidate(reason: .actionPerformed)
                        homeNavigationCoordinator.path.append(.muscleFocus)
                    })
                .tipBackground(Color.secondaryBackground)
                .tipCornerRadius(20)
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: showsFocusTip)
        .task {
            for await eligible in focusTip.shouldDisplayUpdates {
                focusTipEligible = eligible
            }
        }
        .onChange(of: focusStore.hasChosenFocus) { _, chosen in
            // Chosen anywhere — the editor, Muscle Groups, a muscle's page — retires the tip for good.
            if chosen { focusTip.invalidate(reason: .actionPerformed) }
        }
    }

    private var pair: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                homeNavigationCoordinator.path.append(.strength)
            } label: {
                StrengthTile(progress: strength)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            Button {
                homeNavigationCoordinator.path.append(.muscleGroupsOverview(nil))
            } label: {
                MuscleBalanceGoalTile(
                    workouts: currentWindowWorkouts,
                    weeks: window.weeksCovered(firstDataDate: workouts.compactMap(\.date).min())
                )
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
        }
        .frame(height: PAIRED_TILE_HEIGHT)
        .task(id: "\(window.rawValue)-\(workouts.count)") {
            strength = StrengthProgress.compute(workouts: workouts, window: window)
        }
    }
}

// MARK: - Focus tip

/// The one nudge toward setting a training focus: shown once, under the Balance tile, after the first
/// workout with sets, and only while the user is still on the default focus. Closing it or choosing a
/// focus retires it for good. There is no badge, dot or repeat — the default is a perfectly good focus,
/// so this is information rather than a to-do.
struct MuscleFocusTip: Tip {
    static let chooseFocusActionID = "chooseFocus"

    var title: Text {
        Text(NSLocalizedString("muscleFocusTipTitle", comment: ""))
    }

    var message: Text? {
        Text(String(format: NSLocalizedString("muscleFocusTipMessage", comment: ""), MuscleFocusPreset.fullBody.title))
    }

    var image: Image? {
        Image(systemName: "target")
    }

    var actions: [Action] {
        [Action(id: Self.chooseFocusActionID, title: NSLocalizedString("muscleFocusTipAction", comment: ""))]
    }
}

/// The tip drawn quietly: glyph, title, message, and the action as a text link. iOS 26's default
/// style draws actions as a full-width prominent capsule, which in the app's accent is a lime slab —
/// louder than the Start Workout button, and the loudest thing on a screen this tip exists to *not*
/// interrupt. A link says "you can", where a slab says "you must".
struct MuscleFocusTipStyle: TipViewStyle {
    /// Called for every action, after the action's own handler.
    let onAction: (Tips.Action) -> Void

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.image?
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                configuration.title?
                    .font(.headline)
                    .foregroundStyle(Color.label)
                configuration.message?
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions, id: \.id) { action in
                    Button {
                        action.handler()
                        onAction(action)
                    } label: {
                        action.label()
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondaryLabel)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.fill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(NSLocalizedString("dismiss", comment: "")))
        }
        .padding(CELL_PADDING)
    }
}

// MARK: - Highlights

/// The Highlights band: what just happened, as a carousel of the top few by priority, with "Show All"
/// leading to the full list.
///
/// It sits at the **bottom** of the Summary and stays on the recent window whatever the screen's
/// picker says — the two facts are the same decision. Highlights are *events* (a record, a milestone,
/// a crossing), not aggregates, and an event only counts as a highlight while it is recent: scoped to
/// a year the carousel would fill with records from ten months ago, which is accurate and no longer
/// "what just happened". Everything above it on the screen answers "how am I training"; this answers
/// "what did I just do", so it reads last and keeps its own clock. `ProgressHighlightsScreen` carries
/// the picker for a reader who does want to look further back.
///
/// The section renders nothing at all when there is nothing to show — which is the other reason it
/// can't lead the screen.
struct SummaryHighlightsSection: View {
    let workouts: [Workout]

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @State private var highlights: [ProgressHighlight] = []

    var body: some View {
        // The conditional sits *inside* a container that always exists, so `.task` has something to
        // attach to. On a `Group` whose content is empty the modifier is distributed to zero children
        // and never runs — which leaves `highlights` empty forever and the section permanently hidden.
        VStack(spacing: SECTION_HEADER_SPACING) {
            if !highlights.isEmpty {
                HStack {
                    Text(NSLocalizedString("highlights", comment: ""))
                        .sectionHeaderStyle2()
                    Spacer()
                    // Always offered, not only on overflow: the button is the way into the screen
                    // that can widen the window, so it has to be there even when the carousel
                    // happens to be showing everything the recent window holds.
                    Button {
                        homeNavigationCoordinator.path.append(.progressHighlights)
                    } label: {
                        Text(NSLocalizedString("showAll", comment: ""))
                    }
                    .fontWeight(.semibold)
                }
                ProgressHighlightsCarousel(
                    items: Array(highlights.prefix(ProgressHighlights.carouselLimit))
                )
            }
        }
        .task(id: workouts.count) {
            highlights = ProgressHighlights.compute(
                workouts: workouts,
                database: database,
                window: ProgressHighlights.recentWindow
            )
        }
    }
}
