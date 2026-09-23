//
//  WorkoutNoteField.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.08.26.
//

import SwiftUI

/// The workout's own note — "bench felt easy, go 82.5 next time".
///
/// One component, three homes: the recorder header (over the muscle wash, so `.translucent`), the
/// note sheet the finish panel's note tile opens, and the workout editor (`.tile`). Deliberately the
/// same shape as `WorkoutSetGroupCell.noteField` — a note on the workout and a note on an exercise
/// should not look like two different features.
///
/// When the workout came from a template that has been run before, last session's note lives
/// **inside this same card**, above a hairline, rather than in a separate row floating above it.
/// They are one thing: the note for this slot, with the last one still legible while you write the
/// next. Two stacked cards read as two unrelated fields and invited the question "which one am I
/// typing into?".
struct WorkoutNoteField: View {
    enum Style {
        /// A translucent card, for the header and the note sheet, where the muscle wash shows through.
        case translucent
        /// The app's standard opaque cell, for the editor.
        case tile
    }

    @ObservedObject var workout: Workout
    var isFocused: FocusState<Bool>.Binding
    var style: Style = .translucent
    var prompt: String = NSLocalizedString("addNote...", comment: "")
    var lineLimit: ClosedRange<Int> = 1...6
    /// Whether to offer last session's note above the field at all. The detail/editor screens pass
    /// `false`: there is nothing to prompt once the session is over.
    var showsPreviousNote: Bool = true

    @ViewBuilder
    var body: some View {
        switch style {
        case .translucent:
            // The same surface the header's stat tiles wear. It was clear Liquid Glass until the
            // specular rims turned out to be the loudest thing on the header.
            card
                .translucentTileStyle()
                .animation(.snappy(duration: 0.28), value: showsRecall)
        case .tile:
            card
                .tileStyle()
                .animation(.snappy(duration: 0.28), value: showsRecall)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPreviousNote, showsRecall, let previous = workout.previousTemplateNote {
                previousNote(previous.note, date: previous.date)
                Divider()
                    .overlay(Color.label.opacity(0.12))
                    .padding(.vertical, 10)
            }
            noteField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
    }

    /// Last session's note stays up while this one is still blank **and** while you are actually
    /// writing — you write "hit 72.5" precisely because last time said "go 82.5", so pulling the
    /// reference away at the first keystroke would take it exactly when it is being used. It
    /// collapses once the note is written and the keyboard is gone.
    private var showsRecall: Bool {
        !workout.hasNote || isFocused.wrappedValue
    }

    private func previousNote(_ note: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                "\(NSLocalizedString("lastTime", comment: "")) · \(date.description(.short))"
            )
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(Color.tertiaryLabel)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("previousWorkoutNote")
    }

    private var noteField: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.footnote)
                .foregroundStyle(Color.secondaryLabel)
                .padding(.top, 1)
            TextField(
                "Note",
                text: Binding(get: { workout.note ?? "" }, set: { workout.note = $0 }),
                prompt: Text(prompt).foregroundStyle(Color.tertiaryLabel),
                axis: .vertical
            )
            .focused(isFocused)
            .onSubmit(of: .text) {
                workout.note = (workout.note ?? "") + "\n"
                isFocused.wrappedValue = true
            }
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .font(.subheadline)
            .foregroundStyle(Color.label)
            .accessibilityIdentifier("workoutNoteField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The note as it reads after the fact — workout detail, where nothing is editable in place.
struct WorkoutNoteCard: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("note", comment: ""))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.secondaryLabel)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Color.label)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .tileStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workoutNoteCard")
    }
}

// MARK: - On half a tile

/// The note on half a tile: its label over as much of the note as fits, the last visible line
/// ending in an ellipsis, or the prompt while there is none. A button into
/// `WorkoutNoteEditorSheet`.
///
/// The finish panel stands it beside the effort tile — the two are the workout's own account of
/// itself, and side by side they cost one row instead of two sections. The row takes the effort
/// tile's height and the note fills it: however long the note, the row never grows.
struct WorkoutNoteTile: View {
    @ObservedObject var workout: Workout
    var prompt: String = NSLocalizedString("workoutNotePrompt", comment: "")
    let action: () -> Void

    private var note: String {
        (workout.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(NSLocalizedString("note", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.label)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondaryLabel)
                }
                // No line limit: the text takes every line the height it is given can hold and
                // truncates the last of them — "as much as fits", whatever the tile's height.
                Text(workout.hasNote ? note : prompt)
                    .font(.subheadline)
                    .foregroundStyle(workout.hasNote ? Color.label : Color.tertiaryLabel)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(CELL_PADDING)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        // Identifier and label on the Button itself, as `WorkoutEffortTile` does, so the button
        // trait survives for `app.buttons["workoutNoteTile"]`.
        .buttonStyle(.plain)
        .accessibilityIdentifier("workoutNoteTile")
        .accessibilityLabel(NSLocalizedString("note", comment: ""))
        .accessibilityValue(workout.hasNote ? note : prompt)
        .translucentTileStyle()
    }
}

// MARK: - The whole note

/// The whole note, editable — the same card the recorder header writes into, last session's note
/// above the hairline and this one below it — on a sheet over the workout's muscle wash, the
/// background the effort sheet wears, so the two ways of describing a workout read as one family.
///
/// Edits land on the workout as they are typed, like everywhere else the note is written; Done only
/// closes the sheet. A blank note opens with the keyboard up (the tap was to write one); a written
/// one opens to be read, all of it, with the keyboard a tap away.
struct WorkoutNoteEditorSheet: View {
    @ObservedObject var workout: Workout

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                WorkoutNoteField(
                    workout: workout,
                    isFocused: $isFocused,
                    style: .translucent,
                    prompt: NSLocalizedString("workoutNotePrompt", comment: ""),
                    lineLimit: 6 ... 60
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(NSLocalizedString("note", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .accessibilityIdentifier("workoutNoteDone")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            WorkoutEffortBackground(muscleGroups: workout.muscleGroups)
        }
        .task {
            guard !workout.hasNote else { return }
            // After the sheet has risen: focusing during the presentation animation is dropped
            // intermittently, and the keyboard would race the sheet up the screen anyway.
            try? await Task.sleep(for: .milliseconds(380))
            isFocused = true
        }
    }
}

extension View {
    /// Presents the note editor over this view — the one way the note tile opens, wherever it sits.
    func workoutNoteEditorSheet(isPresented: Binding<Bool>, workout: Workout) -> some View {
        sheet(isPresented: isPresented) {
            WorkoutNoteEditorSheet(workout: workout)
        }
    }
}
