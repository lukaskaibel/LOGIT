//
//  RangePicker.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.07.26.
//

import SwiftUI

/// The shared segmented 3M / 1Y / All control for the capability charts — the rolling-range
/// counterpart of `PeriodPicker`, so every chart that pans through continuous history offers the
/// same ranges with the same labels.
struct RangePicker: View {
    @Binding var selection: ChartRange

    var body: some View {
        Picker(NSLocalizedString("range", comment: ""), selection: $selection) {
            ForEach(ChartRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#Preview {
    VStack(spacing: 20) {
        RangePicker(selection: .constant(.threeMonths))
        RangePicker(selection: .constant(.year))
        RangePicker(selection: .constant(.allTime))
    }
    .padding()
}
