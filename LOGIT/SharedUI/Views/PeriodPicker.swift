//
//  PeriodPicker.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The shared segmented Week / Month / Year control. One control, one `StatPeriod` enum, everywhere —
/// the Summary screen's scoped block and the stat detail screens — replacing the inline
/// `Picker(.segmented)` each screen used to hand-roll over its own granularity enum.
struct PeriodPicker: View {
    @Binding var selection: StatPeriod

    var body: some View {
        Picker(NSLocalizedString("period", comment: ""), selection: $selection) {
            ForEach(StatPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// The rolling-window counterpart: the shared 4 weeks / 3 months / 1 year control behind the
/// Summary's top pair. Separate from `PeriodPicker` because the two enums answer different
/// questions — see `TrendWindow` — and a screen picking a rolling window must never be handed a
/// calendar period by mistake.
struct TrendWindowPicker: View {
    @Binding var selection: TrendWindow

    var body: some View {
        Picker(NSLocalizedString("period", comment: ""), selection: $selection) {
            ForEach(TrendWindow.allCases) { window in
                Text(window.title).tag(window)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#Preview {
    VStack(spacing: 20) {
        PeriodPicker(selection: .constant(.week))
        PeriodPicker(selection: .constant(.month))
        PeriodPicker(selection: .constant(.year))
        TrendWindowPicker(selection: .constant(.fourWeeks))
        TrendWindowPicker(selection: .constant(.oneYear))
    }
    .padding()
}
