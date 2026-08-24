//
//  WorkoutNoteField.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.08.26.
//

import SwiftUI

/// The workout's own note — "bench felt easy, go 82.5 next time".
///
/// One component, three homes: the recorder header (over the muscle wash, so `.glass`), the finish
/// panel, and the workout editor (`.tile`). Deliberately the same shape as
/// `WorkoutSetGroupCell.noteField` — a note on the workout and a note on an exercise should not
/// look like two different features.
///
/// When the workout came from a template that has been run before, last session's note lives
/// **inside this same card**, above a hairline, rather than in a separate row floating above it.
/// They are one thing: the note for this slot, with the last one still legible while you write the
/// next. Two stacked cards read as two unrelated fields and invited the question "which one am I
/// typing into?".
struct WorkoutNoteField: View {
    enum Style {
        /// Clear glass, for the header and finish panel where the muscle wash shows through.
        case glass
        /// The app's standard opaque cell, for the editor.
        case tile
    }

    @ObservedObject var workout: Workout
    var isFocused: FocusState<Bool>.Binding
    var style: Style = .glass
    var prompt: String = NSLocalizedString("addNote...", comment: "")
    var lineLimit: ClosedRange<Int> = 1...6
    /// Whether to offer last session's note above the field at all. The detail/editor screens pass
    /// `false`: there is nothing to prompt once the session is over.
    var showsPreviousNote: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPreviousNote, showsRecall, let previous = workout.previousTemplateNote {
                previousNote(previous.note, date: previous.date)
                Divider()
                    .overlay(Color.label.opacity(0.12))
                    .padding(.vertical, 10)
            }
            noteField
        }
        .padding(CELL_PADDING)
        .background {
            switch style {
            case .glass:
                // Matches the header's stat tiles: clear glass so the workout's colours come
                // through from the wash behind it rather than a solid slab sitting on top.
                Color.clear.glassEffect(.clear, in: .rect(cornerRadius: 24))
            case .tile:
                RoundedRectangle(cornerRadius: 20).fill(Color.secondaryBackground)
            }
        }
        .animation(.snappy(duration: 0.28), value: showsRecall)
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
