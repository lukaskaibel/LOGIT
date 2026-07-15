//
//  SwipeableMonthView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 15.07.26.
//

import SwiftUI

/// The month-paged calendar shell shared by the History and Weekly-Goal calendars. It owns the
/// prev/next header — a month title flanked by chevrons — and a horizontally swipeable body: dragging
/// left/right reveals the adjacent month and snaps to it, and the chevrons drive the very same slide.
/// Every committed change, whether an arrow tap or a swipe, ticks a selection haptic. The forward edge
/// is capped at the current month (no future); paging backward is unbounded, matching the calendars'
/// prior behaviour.
///
/// Callers supply the two month-specific pieces: a fixed `weekdayHeader` (the weekday-symbol row, which
/// never changes from month to month) and `weeks(month)`, the grid of week rows for a given month.
/// Only `weeks` slides — the header and the weekday row stay put, as they do in a system calendar.
struct SwipeableMonthView<WeekdayHeader: View, Weeks: View>: View {
    /// The centred month, as a `startOfMonth`. Committed changes flow back out through this binding.
    @Binding var month: Date
    @ViewBuilder var weekdayHeader: () -> WeekdayHeader
    @ViewBuilder var weeks: (Date) -> Weeks

    /// Live horizontal translation of the grid: 0 at rest, positive while dragging toward the previous
    /// month, negative toward the next. The neighbouring page is only built while this is non-zero.
    @State private var dragOffset: CGFloat = 0
    /// Measured width of one page, used both to park a neighbour a full page away and to size a swipe.
    @State private var pageWidth: CGFloat = 1
    /// Latches a gesture to horizontal once its dominant axis is known, so vertical scrolls fall through
    /// to the enclosing ScrollView untouched.
    @State private var isPagingDrag: Bool?

    private let calendar = Calendar.current

    /// The next month is reachable only while it isn't in the future.
    private var canGoForward: Bool { month.startOfMonth < Date.now.startOfMonth }

    private func neighbouringMonth(_ delta: Int) -> Date {
        (calendar.date(byAdding: .month, value: delta, to: month) ?? month).startOfMonth
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekdayHeader()
            pager
        }
        .padding(.top, CELL_PADDING)
        .padding(.bottom, CELL_PADDING / 2)
        .tileStyle()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canGoForward)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, CELL_PADDING)
    }

    // MARK: - Swipeable grid

    private var pager: some View {
        ZStack(alignment: .top) {
            weeks(month)
                .frame(maxWidth: .infinity)
                .offset(x: dragOffset)
            // The one neighbour the current drag is reaching toward — never both, so an off-screen page
            // isn't laid out or its occurrence rings recomputed until a swipe actually asks for it.
            if dragOffset > 0 {
                weeks(neighbouringMonth(-1))
                    .frame(maxWidth: .infinity)
                    .offset(x: dragOffset - pageWidth)
            } else if dragOffset < 0 {
                weeks(neighbouringMonth(1))
                    .frame(maxWidth: .infinity)
                    .offset(x: dragOffset + pageWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { pageWidth = geo.size.width }
                    .onChange(of: geo.size.width) { pageWidth = $1 }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(pagingGesture)
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Decide the axis once; ignore the gesture entirely if it's a vertical scroll so the
                // ScrollView keeps it (this gesture runs simultaneously with the scroll).
                if isPagingDrag == nil {
                    isPagingDrag = abs(value.translation.width) > abs(value.translation.height)
                }
                guard isPagingDrag == true else { return }
                var translation = value.translation.width
                // Rubber-band when there's no next month to reveal at the future edge.
                if translation < 0, !canGoForward { translation /= 4 }
                dragOffset = translation
            }
            .onEnded { value in
                defer { isPagingDrag = nil }
                guard isPagingDrag == true else { return }
                // Fold a little of the fling velocity in so a fast flick pages even if it fell short.
                let travelled = value.translation.width + value.predictedEndTranslation.width / 3
                let threshold = pageWidth * 0.28
                if travelled > threshold {
                    move(by: -1)
                } else if travelled < -threshold, canGoForward {
                    move(by: 1)
                } else {
                    withAnimation(.snappy(duration: 0.25)) { dragOffset = 0 }
                }
            }
    }

    /// Slides the grid one page in `delta`'s direction, then commits the month and resets the offset —
    /// so the neighbour that just slid to centre is seamlessly re-hosted as the now-current month. This
    /// is also the chevrons' path. Blocked (with a spring-back) at the future edge; ticks a selection
    /// haptic on every real move.
    private func move(by delta: Int) {
        guard delta != 0 else { return }
        if delta > 0, !canGoForward {
            withAnimation(.snappy(duration: 0.25)) { dragOffset = 0 }
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy(duration: 0.3)) {
            dragOffset = -CGFloat(delta) * pageWidth
        } completion: {
            month = neighbouringMonth(delta)
            dragOffset = 0
        }
    }
}
