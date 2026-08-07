//
//  SummaryTrendSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI

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
    @State private var strength: StrengthProgress = .empty

    /// The workouts inside the selected window — what Balance reports over.
    private var currentWindowWorkouts: [Workout] {
        workouts.filter { workout in
            guard !workout.isEmpty, let date = workout.date else { return false }
            return window.contains(date)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                homeNavigationCoordinator.path.append(.strength)
            } label: {
                StrengthTile(progress: strength)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            Button {
                homeNavigationCoordinator.path.append(.muscleGroupsOverview)
            } label: {
                MuscleBalanceGoalTile(workouts: currentWindowWorkouts)
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
