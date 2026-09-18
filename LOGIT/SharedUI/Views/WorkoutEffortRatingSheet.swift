//
//  WorkoutEffortRatingSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 18.09.26.
//

import ColorfulX
import SwiftUI

// MARK: - The sheet

/// The one screen a workout is rated on. Two circular buttons, the question, the bars, and the
/// rating spelled out underneath — Apple's effort screen, down to the geometry, with LOGIT's
/// muscle wash behind it instead of Apple's flat colour.
///
/// **It holds a draft.** The ✓ is the commit: the drag moves local state, cheap, and nothing
/// reaches the managed object until the sheet closes on it. Writing per slot republished the
/// whole editor (set list included) on every bar a finger crossed, which is what used to make
/// the scale feel laggy there — and it also meant closing with ✗ left the rating behind.
struct WorkoutEffortRatingSheet: View {
    @Binding var score: Int?
    let muscleGroups: [MuscleGroup]

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Int?
    @State private var isShowingDescriptions = false

    var body: some View {
        NavigationStack {
            ratingPage
                .navigationDestination(isPresented: $isShowingDescriptions) {
                    WorkoutEffortDescriptionList(
                        score: $draft,
                        onBack: { isShowingDescriptions = false },
                        onSkip: {
                            // Skipping is an answer, not a cancel: it commits "unrated" and
                            // leaves, the same way ✓ commits a number.
                            draft = nil
                            score = nil
                            dismiss()
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
        }
        .presentationBackground {
            WorkoutEffortBackground(muscleGroups: muscleGroups)
        }
        .onAppear { draft = score }
    }

    private var ratingPage: some View {
        VStack(spacing: 0) {
            HStack {
                EffortCircleButton(systemImage: "xmark", style: .secondary) { dismiss() }
                    .accessibilityLabel(NSLocalizedString("cancel", comment: ""))
                    .accessibilityIdentifier("effortCancelButton")
                Spacer()
                EffortCircleButton(
                    systemImage: "checkmark",
                    style: .prominent,
                    isEnabled: draft != nil
                ) {
                    score = draft
                    dismiss()
                }
                .accessibilityLabel(NSLocalizedString("done", comment: ""))
                .accessibilityIdentifier("effortConfirmButton")
            }
            Spacer(minLength: 24)
            Text(NSLocalizedString("rateYourEffort", comment: ""))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.label)
            Spacer(minLength: 24)
            WorkoutEffortPicker(score: $draft) { isShowingDescriptions = true }
            // Two spacers below against one above each of the title and the picker: the rating
            // sits in the upper two thirds of the sheet, where a thumb reaches it, rather than
            // floating in the middle of an empty screen.
            Spacer(minLength: 24)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The descriptions

/// The ten ratings in full: what each band feels like, how long you could hold it, and a row per
/// score to pick from. It is the answer to "what counts as a 7", and it is the only place the
/// rating can be taken back — Skip is the bottom of this list, not a button beside the bars,
/// because clearing a rating should cost more than a stray tap.
struct WorkoutEffortDescriptionList: View {
    @Binding var score: Int?
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                EffortCircleButton(systemImage: "chevron.left", style: .secondary, action: onBack)
                    .accessibilityLabel(NSLocalizedString("back", comment: ""))
                    .accessibilityIdentifier("effortDescriptionsBackButton")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(NSLocalizedString("effortSelectDescription", comment: ""))
                        .font(.title3)
                        .foregroundStyle(Color.label)
                    ForEach(WorkoutEffort.allCases) { effort in
                        section(effort)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                            .padding(.bottom, 10)
                        skipRow
                        Text(NSLocalizedString("effortSkipFootnote", comment: ""))
                            .font(.footnote)
                            .foregroundStyle(Color.secondaryLabel)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ effort: WorkoutEffort) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(effort.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.label)
                Text(effort.feelDescription)
                Text(effort.enduranceDescription)
            }
            .font(.body)
            .foregroundStyle(Color.label)
            card {
                ForEach(Array(effort.scores), id: \.self) { value in
                    if value != effort.scores.lowerBound {
                        Divider()
                    }
                    row(value: value, effort: effort)
                }
            }
        }
    }

    private func row(value: Int, effort: WorkoutEffort) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            score = value
            onBack()
        } label: {
            HStack(spacing: 14) {
                WorkoutEffortScoreBadge(score: value, diameter: 28)
                Text(effort.name)
                    .font(.title3)
                    .foregroundStyle(Color.label)
                Spacer(minLength: 8)
                if value == score {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.label)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("effortDescriptionRow\(value)")
    }

    private var skipRow: some View {
        card {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                onSkip()
            } label: {
                HStack(spacing: 14) {
                    WorkoutEffortSkipIcon()
                    Text(NSLocalizedString("skip", comment: ""))
                        .font(.title3)
                        .foregroundStyle(Color.label)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("effortSkip")
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.tertiaryFill, in: .rect(cornerRadius: 16))
    }
}

/// The scale with a line through it. Drawn from the same bars as everywhere else rather than a
/// symbol that merely resembles them, so Skip reads as "no rating on *this* scale".
private struct WorkoutEffortSkipIcon: View {
    var body: some View {
        WorkoutEffortBars(score: nil, size: .mini)
            .frame(width: 28)
            .overlay {
                Capsule()
                    .fill(Color.secondaryLabel)
                    .frame(width: 2.5, height: 36)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 28, height: 28)
    }
}

// MARK: - Chrome

/// The rating screen's circular buttons. `prominent` is the commit — filled, the way Apple fills
/// the ✓ — and dims to a plain disc while there is nothing to commit.
private struct EffortCircleButton: View {
    enum Style { case secondary, prominent }

    let systemImage: String
    let style: Style
    var isEnabled: Bool = true
    let action: () -> Void

    private let diameter: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(background, in: .circle)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.snappy(duration: 0.2), value: isEnabled)
    }

    private var foreground: Color {
        switch style {
        case .secondary: return .label
        case .prominent: return isEnabled ? .black : .secondaryLabel
        }
    }

    /// `systemFill` rather than the tertiary step both discs used at first: over the muscle wash
    /// the fainter one disappeared, and a ✗ you cannot find is worse than one that is too loud.
    private var background: Color {
        switch style {
        case .secondary: return .fill
        case .prominent: return isEnabled ? .label : .fill
        }
    }
}

// MARK: - The background

/// LOGIT's one departure from Apple's effort screen: the workout's own muscle groups wash the
/// top of it, the same ambient `ColorfulX` field the recorder and the workout detail wear, so
/// the sheet belongs to the workout it is rating.
struct WorkoutEffortBackground: View {
    let muscleGroups: [MuscleGroup]

    var body: some View {
        ZStack {
            Color.black
            ColorfulView(color: muscleGroups.map { $0.color }, speed: .constant(0))
                // Four stops, not two: the colour has to carry past the bars (Apple's screen is
                // one flat colour top to bottom) without the long even fade that turns a
                // multi-muscle blend olive across the whole screen.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.85), location: 0),
                            .init(color: .black.opacity(0.5), location: 0.26),
                            .init(color: .black.opacity(0.16), location: 0.62),
                            .init(color: .clear, location: 0.96),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Presenting it

extension View {
    /// Presents the rating screen over this view. Every host that rates a workout uses this, so
    /// the sheet's detents, background and commit behaviour cannot drift apart between screens.
    func workoutEffortRatingSheet(
        isPresented: Binding<Bool>,
        score: Binding<Int?>,
        muscleGroups: [MuscleGroup]
    ) -> some View {
        sheet(isPresented: isPresented) {
            WorkoutEffortRatingSheet(score: score, muscleGroups: muscleGroups)
        }
    }
}

// MARK: - The rating, in place

/// The rating screen without its chrome, on a card. The recorder's finish panel *is* the moment
/// a workout is rated, so it rates in place instead of behind a tap — but from the same bars,
/// the same capsule and the same description list as the sheet.
struct WorkoutEffortRatingCard: View {
    @Binding var score: Int?
    let muscleGroups: [MuscleGroup]

    @State private var isShowingDescriptions = false

    var body: some View {
        WorkoutEffortPicker(score: $score, size: .compact) {
            isShowingDescriptions = true
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 18)
        .translucentTileStyle()
        .sheet(isPresented: $isShowingDescriptions) {
            WorkoutEffortDescriptionList(
                score: $score,
                onBack: { isShowingDescriptions = false },
                onSkip: {
                    score = nil
                    isShowingDescriptions = false
                }
            )
            .presentationBackground {
                WorkoutEffortBackground(muscleGroups: muscleGroups)
            }
        }
    }
}

#Preview {
    struct Wrapper: View {
        @State private var score: Int? = 5
        var body: some View {
            WorkoutEffortRatingSheet(score: $score, muscleGroups: [.chest, .shoulders])
        }
    }
    return Wrapper()
}
