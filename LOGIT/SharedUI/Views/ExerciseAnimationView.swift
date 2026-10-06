//
//  ExerciseAnimationView.swift
//  LOGIT
//

import SwiftUI

/// The looping demonstration of a built-in exercise: the app's minimalist figure performing it,
/// with the working muscles highlighted. It is drawn live with Metal from the exercise's baked
/// rig (`ExerciseRig`, a few kilobytes), from the exercise's own camera and cropped tight to the
/// figure; `ExerciseFigure3DView` draws the same rig turnable. It shows at 96 pt beside the detail
/// screen's title and 48 pt in the exercise cells.
///
/// An exercise without a rig (a custom one) renders nothing, so call sites can place the view
/// unconditionally. The figure is drawn only while it is on screen (its rig is decoded then too),
/// and Reduce Motion holds its first frame instead of looping.
struct ExerciseAnimationView: View {
    let exercise: Exercise?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = false

    var body: some View {
        if let key = ExerciseAnimationLibrary.key(for: exercise), ExerciseRig.has(key: key) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isOnScreen, let rig = ExerciseRig.named(key) {
                        // screenshots hold the loop's first frame, so every locale captures the same pose
                        FigureMetalView(rig: rig, framing: .icon, playing: !reduceMotion && !ScreenshotFixtures.isEnabled)
                    }
                }
                .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
                .accessibilityHidden(true)
        }
    }
}

/// The looping figure left of an exercise's name in the exercise cells. It stands bare on the
/// cell, a little taller than the name and muscle group together, inside the cell's own padding.
/// A custom exercise, which has no figure, gets a quiet glyph in its muscle group's colour in the
/// same place, so every name in a list starts at the same edge.
struct ExerciseAnimationIcon: View {
    let exercise: Exercise?

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 48

    var body: some View {
        Group {
            if ExerciseAnimationLibrary.hasAnimation(for: exercise) {
                ExerciseAnimationView(exercise: exercise)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle((exercise?.muscleGroup?.color ?? .secondary).gradient)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholderSymbol: String {
        switch exercise?.muscleGroup {
        case .cardio: "figure.run"
        case .abdominals: "figure.core.training"
        default: "figure.strengthtraining.traditional"
        }
    }
}

// MARK: - Lookup

enum ExerciseAnimationLibrary {
    private static let defaultPrefix = "_default.exercise."

    static func hasAnimation(for exercise: Exercise?) -> Bool {
        key(for: exercise).map(ExerciseRig.has(key:)) ?? false
    }

    /// The library key of the exercise's rig: a built-in exercise's name is its key behind the
    /// `_default.exercise.` prefix.
    static func key(for exercise: Exercise?) -> String? {
        guard let name = exercise?.name else { return nil }
        if name.hasPrefix(defaultPrefix) {
            let key = String(name.dropFirst(defaultPrefix.count))
            return keyAliases[key] ?? key
        }
        return previewAliases[name]
    }

    /// Keys the test scenarios use that aren't library keys.
    private static let keyAliases = [
        "overheadPress": "militaryPress",
        "inclineBenchPress": "inclinedBarbellBenchPress",
        "tricepsExtensions": "overheadTricepExtension",
        "bicepsCurls": "dumbbellCurls",
    ]

    /// The preview dataset names its exercises with display strings rather than library keys.
    private static let previewAliases: [String: String] = Dictionary(
        [
            ("previewBenchPress", "barbellBenchPress"),
            ("previewInclineBenchPress", "inclinedBarbellBenchPress"),
            ("previewOverheadPress", "militaryPress"),
            ("previewLateralRaises", "lateralRaises"),
            ("previewTricepsExtensions", "overheadTricepExtension"),
            ("previewDips", "dips"),
            ("previewSquat", "squats"),
            ("previewSquats", "squats"),
            ("previewLunges", "dumbbellLunges"),
            ("previewLegExtensions", "legExtension"),
            ("previewDeadlift", "deadlift"),
            ("previewStandingRows", "barbellRows"),
            ("previewBicepsCurls", "dumbbellCurls"),
            ("previewBarbellCurl", "barbellCurls"),
            ("previewLatPulldown", "latPulldowns"),
            ("previewCrunches", "crunches"),
            ("previewPushup", "pushups"),
        ].map { (NSLocalizedString($0.0, comment: ""), $0.1) },
        uniquingKeysWith: { first, _ in first }
    )
}
