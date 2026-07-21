//
//  SetVolumeBarChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import Charts
import SwiftUI

/// Minimal bar chart showing the volume of every set in a workout, in workout order.
/// Each bar is colored with the muscle group color of the set's exercise; super sets
/// stack one segment per exercise. Tapping or dragging selects a set and reveals its
/// exercise, set number and volume. Sets without volume keep their slot as a gap.
struct SetVolumeBarChart: View {
    private struct Segment: Identifiable {
        let id: String
        let setIndex: Int
        let setNumberInGroup: Int
        let exerciseName: String
        let color: Color
        /// Volume in storage units (grams), converted only for display.
        let volume: Int
    }

    // MARK: - State

    @State private var rawSelection: String?

    // MARK: - Variables

    private let segments: [Segment]
    private let setCount: Int

    init(sets: [WorkoutSet]) {
        var segments = [Segment]()
        for (index, workoutSet) in sets.enumerated() {
            let setIndex = index + 1
            let setNumberInGroup = (workoutSet.setGroup?.sets.firstIndex(of: workoutSet) ?? 0) + 1
            // One segment per distinct exercise in the set, in entry order: a standard or drop
            // set stays one bar, a super set (or a future circuit) splits into one colored
            // segment per exercise.
            var exerciseVolumes = [(exercise: Exercise?, volume: Int)]()
            for value in workoutSet.entryValues {
                let volume = Int(value.repetitions * value.weight)
                guard volume > 0 else { continue }
                if let existingIndex = exerciseVolumes.firstIndex(
                    where: { $0.exercise == value.exercise }
                ) {
                    exerciseVolumes[existingIndex].volume += volume
                } else {
                    exerciseVolumes.append((value.exercise, volume))
                }
            }
            for (segmentIndex, exerciseVolume) in exerciseVolumes.enumerated() {
                let exercise = exerciseVolume.exercise ?? workoutSet.exercise
                segments.append(
                    Segment(
                        id: "\(setIndex)-\(segmentIndex)",
                        setIndex: setIndex,
                        setNumberInGroup: setNumberInGroup,
                        exerciseName: exercise?.displayName ?? "",
                        color: exercise?.muscleGroup?.color ?? .accentColor,
                        volume: exerciseVolume.volume
                    )
                )
            }
        }
        self.segments = segments
        setCount = sets.count
    }

    // MARK: - Body

    var body: some View {
        let selectedSegments = selectedSetIndex.map { index in segments.filter { $0.setIndex == index } } ?? []
        Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Set", String(segment.setIndex)),
                    y: .value("Volume", convertWeightForDisplayingDecimal(segment.volume)),
                    width: .ratio(0.35)
                )
                .foregroundStyle(segment.color.gradient)
                .opacity(selectedSetIndex == nil || selectedSetIndex == segment.setIndex ? 1.0 : 0.3)
                .clipShape(Capsule())
            }
            if let selectedSetIndex, let firstSegment = selectedSegments.first {
                RuleMark(x: .value("Selected", String(selectedSetIndex)))
                    .foregroundStyle(firstSegment.color.gradient.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        VStack(alignment: .leading) {
                            UnitView(
                                value: formatWeightForDisplay(selectedSegments.map { $0.volume }.reduce(0, +)),
                                unit: WeightUnit.used.rawValue
                            )
                            .foregroundStyle(firstSegment.color.gradient)
                            Text(selectionDescription(for: selectedSegments))
                                .fontWeight(.bold)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.tertiaryBackground))
                    }
            }
        }
        .chartXScale(domain: (1 ... max(setCount, 1)).map { String($0) })
        .chartXSelection(value: $rawSelection)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    // MARK: - Computed Properties

    /// The set the gesture currently points at, snapped to the nearest set that has volume.
    private var selectedSetIndex: Int? {
        guard let rawSelection = rawSelection, let rawIndex = Int(rawSelection) else { return nil }
        return Set(segments.map { $0.setIndex })
            .min { abs($0 - rawIndex) < abs($1 - rawIndex) }
    }

    private func selectionDescription(for selectedSegments: [Segment]) -> String {
        guard let firstSegment = selectedSegments.first else { return "" }
        var exerciseNames = [String]()
        for segment in selectedSegments where !exerciseNames.contains(segment.exerciseName) {
            exerciseNames.append(segment.exerciseName)
        }
        return "\(exerciseNames.joined(separator: " & ")) · \(NSLocalizedString("set", comment: "")) \(firstSegment.setNumberInGroup)"
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        SetVolumeBarChart(sets: database.testWorkout.sets)
            .frame(height: 130)
            .padding(CELL_PADDING)
            .tileStyle()
            .padding()
    }
}

struct SetVolumeBarChart_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
