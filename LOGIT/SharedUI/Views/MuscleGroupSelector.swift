//
//  MuscleGroupSelector.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.04.22.
//

import SwiftUI

struct MuscleGroupSelector: View {
    @Binding var selectedMuscleGroup: MuscleGroup?
    let muscleGroups: [MuscleGroup]
    let canBeNil: Bool
    let animation: Bool
    /// Wrapped capsules show every group at once — the exercise editor uses this so no option
    /// hides off-screen. The default stays the single scrolling row used by the filter bars.
    let wraps: Bool

    init(
        selectedMuscleGroup: Binding<MuscleGroup?>,
        from muscleGroups: [MuscleGroup] = MuscleGroup.allCases,
        canBeNil: Bool = true,
        withAnimation: Bool = false,
        wraps: Bool = false
    ) {
        _selectedMuscleGroup = selectedMuscleGroup
        self.muscleGroups = muscleGroups
        self.canBeNil = canBeNil
        animation = withAnimation
        self.wraps = wraps
    }

    var body: some View {
        if wraps {
            FlowLayout {
                capsules
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    capsules
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var capsules: some View {
        if canBeNil {
            Button(NSLocalizedString("all", comment: "")) {
                if animation {
                    withAnimation {
                        selectedMuscleGroup = nil
                    }
                } else {
                    selectedMuscleGroup = nil
                }
            }
            .buttonStyle(CapsuleButtonStyle(isSelected: selectedMuscleGroup == nil, compact: wraps))
        }
        ForEach(muscleGroups) { muscleGroup in
            Button(muscleGroup.description) {
                if animation {
                    withAnimation {
                        selectedMuscleGroup = muscleGroup
                    }
                } else {
                    selectedMuscleGroup = muscleGroup
                }
            }
            .buttonStyle(
                CapsuleButtonStyle(
                    color: muscleGroup.color,
                    isSelected: selectedMuscleGroup == muscleGroup,
                    compact: wraps
                )
            )
        }
    }
}

/// Line-wrapping layout for variable-width capsules. Two things separate it from a plain
/// wrap: rows are *balanced*, so eight muscle names settle into two even rows instead of
/// three ragged ones, and each row is *justified*, so the capsules spread across the width
/// rather than cramming against the leading edge. Localized names never truncate.
struct FlowLayout: Layout {
    /// The tightest gap between two capsules; justification only ever widens it.
    var minSpacing: CGFloat = 8
    /// How far a justified gap may open before the row is left-aligned instead — without a
    /// ceiling, a short row would drift apart into disconnected islands.
    var maxSpacing: CGFloat = 26
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? .infinity
        let rows = balancedRows(sizes: sizes, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + rowHeight($1, sizes: sizes) }
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map { rowWidth($0, sizes: sizes) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = balancedRows(sizes: sizes, maxWidth: bounds.width)
        // One gap for the whole block, not per row: rows of different total width would
        // otherwise each get their own rhythm, which reads as an accident rather than a grid.
        let spacing = uniformSpacing(rows: rows, sizes: sizes, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            let height = rowHeight(row, sizes: sizes)
            let width = row.reduce(0) { $0 + sizes[$1].width }
                + spacing * CGFloat(max(row.count - 1, 0))
            // Centered, so the leftover on a shorter row splits evenly instead of stranding
            // the whole remainder on the trailing edge.
            var x = bounds.minX + max(bounds.width - width, 0) / 2
            for index in row {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += height + rowSpacing
        }
    }

    /// The widest gap every row can afford — the fullest row sets the limit, so no row
    /// overflows and all of them breathe alike.
    private func uniformSpacing(rows: [[Int]], sizes: [CGSize], maxWidth: CGFloat) -> CGFloat {
        let affordable = rows.compactMap { row -> CGFloat? in
            let gaps = row.count - 1
            guard gaps > 0 else { return nil }
            let slack = maxWidth - row.reduce(0) { $0 + sizes[$1].width }
            return slack / CGFloat(gaps)
        }
        guard let tightest = affordable.min() else { return minSpacing }
        return min(max(tightest, minSpacing), maxSpacing)
    }

    // MARK: - Row Building

    private func rowWidth(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.reduce(0) { $0 + sizes[$1].width } + minSpacing * CGFloat(max(row.count - 1, 0))
    }

    private func rowHeight(_ row: [Int], sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].height }.max() ?? 0
    }

    /// Packs into the fewest rows the width allows, then evens those rows out: the narrowest
    /// row limit that still fits in that many rows is the balanced one, found by bisection.
    /// Without this, greedy packing leaves the remainder stranded alone on a last line.
    private func balancedRows(sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        guard !sizes.isEmpty, maxWidth.isFinite, maxWidth > 0 else {
            return sizes.isEmpty ? [] : [Array(sizes.indices)]
        }
        let greedy = pack(sizes: sizes, limit: maxWidth)
        guard greedy.count > 1 else { return greedy }

        var low = sizes.map(\.width).max() ?? 0
        var high = maxWidth
        var balanced = greedy
        while high - low > 0.5 {
            let mid = (low + high) / 2
            let candidate = pack(sizes: sizes, limit: mid)
            if candidate.count <= greedy.count {
                balanced = candidate
                high = mid
            } else {
                low = mid
            }
        }
        return balanced
    }

    private func pack(sizes: [CGSize], limit: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if current.isEmpty {
                current = [index]
                width = size.width
                continue
            }
            let grown = width + minSpacing + size.width
            if grown > limit {
                rows.append(current)
                current = [index]
                width = size.width
            } else {
                current.append(index)
                width = grown
            }
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

struct MuscleGroupSelector_Previews: PreviewProvider {
    static var previews: some View {
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest))
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest), from: [.chest, .back])
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest), from: [])
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest), canBeNil: false, wraps: true)
            .padding()
    }
}
