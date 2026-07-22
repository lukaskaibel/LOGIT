//
//  MeasurementDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.11.24.
//

import Charts
import SwiftUI

struct MeasurementDetailScreen: View {
    @EnvironmentObject var measurementController: MeasurementEntryController

    let measurementType: MeasurementEntryType

    @State private var chartRange: ChartRange = .threeMonths
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?
    @State private var isAddingEntry = false
    @State private var newEntryDate: Date = .now
    @State private var newEntryValue: Double = 0

    /// Standalone field identity for the add-measurement sheet — there's no set behind this
    /// field, so it gets one fixed UUID (stable across renders, or the field would lose its
    /// state to `.id(index)` re-identification).
    private static let newEntryFieldIndex = IntegerField.Index(setID: UUID())

    private var entries: [MeasurementEntry] {
        measurementController.getMeasurementEntries(ofType: measurementType)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                chartSection
                entriesListSection
            }
            .padding(.horizontal)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(measurementType.title)
                        .font(.headline)
                    Text(NSLocalizedString("measurements", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            addEntrySheet
        }
        .onAppear {
            initializeChartScrollPosition()
        }
        .onChange(of: chartRange) {
            initializeChartScrollPosition()
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        // Fetch the entries once for this render — `getMeasurementEntries` hits Core Data, and it was
        // read ~a dozen times per frame (once per axis mark through `firstDataDate`, plus the y-scale,
        // the selection and every mark), which churned while scrolling or inspecting.
        let entries = entries
        let firstDataDate = entries.last?.date
        let visibleDomainSeconds = chartRange.visibleDomainSeconds(firstDataDate: firstDataDate)
        let visibleEnd = Calendar.current.date(byAdding: .second, value: visibleDomainSeconds, to: chartScrollPosition) ?? chartScrollPosition
        let latestEntry = entries.first
        let snappedSelectedEntry = selectedDate != nil ? nearestEntry(to: selectedDate, in: entries, visibleEnd: visibleEnd) : nil
        // The highest value in the window on screen — moves as you scroll; the reference the current
        // measurement is read against in the header.
        let highestVisible = entries
            .filter { ($0.date).map { $0 >= chartScrollPosition && $0 <= visibleEnd } ?? false }
            .map(\.decimalValue)
            .max()
        let yMax = chartYScaleMax(in: entries)

        VStack {
            RangePicker(selection: $chartRange)
                .padding(.vertical)

            comparisonHeader(latest: latestEntry, highestVisible: highestVisible, firstDataDate: firstDataDate)

            Chart {
                if selectedDate != nil, let selectedEntry = snappedSelectedEntry, let sDate = selectedEntry.date {
                    let snapped = Calendar.current.startOfDay(for: sDate)
                    RuleMark(x: .value("Selected", snapped, unit: .day))
                        .foregroundStyle(Color.accentColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading) {
                                UnitView(
                                    value: formatDecimal(selectedEntry.decimalValue),
                                    unit: measurementType.unit
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                Text(snapped.formatted(.dateTime.day().month()))
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                        }
                }

                if let firstEntry = entries.last {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Value", firstEntry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(snappedSelectedEntry == nil ? 1.0 : 0.3)
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Value", firstEntry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        Color.accentColor.opacity(0.5),
                        Color.accentColor.opacity(0.2),
                        Color.accentColor.opacity(0.05),
                    ]))
                    .opacity(snappedSelectedEntry == nil ? 1.0 : 0.3)
                }

                ForEach(entries.reversed()) { entry in
                    LineMark(
                        x: .value("Date", entry.date ?? .now, unit: .day),
                        y: .value("Value", entry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .symbol {
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(
                                Color.accentColor.gradient
                                    .opacity({
                                        guard let s = snappedSelectedEntry?.date else { return 1.0 }
                                        return Calendar.current.isDate(entry.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                                    }())
                            )
                            .overlay {
                                Circle()
                                    .frame(width: 4, height: 4)
                                    .foregroundStyle(Color.black)
                            }
                            .background(Circle().fill(Color.black))
                    }
                    .opacity({
                        guard let s = snappedSelectedEntry?.date else { return 1.0 }
                        return Calendar.current.isDate(entry.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                    }())
                    AreaMark(
                        x: .value("Date", entry.date ?? .now, unit: .day),
                        y: .value("Value", entry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        Color.accentColor.opacity(0.5),
                        Color.accentColor.opacity(0.2),
                        Color.accentColor.opacity(0.05),
                    ]))
                    .opacity(selectedDate == nil ? 1.0 : 0.0)
                }

                if selectedDate == nil, let lastEntry = entries.first, let lastDate = lastEntry.date, !Calendar.current.isDateInToday(lastDate) {
                    RuleMark(
                        xStart: .value("Start", lastDate),
                        xEnd: .value("End", Date()),
                        y: .value("Value", lastEntry.decimalValue)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            dash: [5, 10]
                        )
                    )
                }
            }
            .chartXScale(domain: chartRange.xDomain(firstDataDate: firstDataDate))
            .chartYScale(domain: 0.0 ... yMax)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $chartScrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(matching: chartRange.scrollSnapComponents)
            )
            .chartXSelection(value: $selectedDate)
            .chartXVisibleDomain(length: visibleDomainSeconds)
            .chartXAxis {
                let axisStride = chartRange.axisStride(firstDataDate: firstDataDate)
                AxisMarks(
                    position: .bottom,
                    values: .stride(by: axisStride.component, count: axisStride.count)
                ) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel(chartRange.axisLabel(for: date, firstDataDate: firstDataDate))
                            .foregroundStyle(chartRange.isCurrentAxisMark(date, firstDataDate: firstDataDate) ? Color.primary : .secondary)
                            .font(.caption.weight(.bold))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, yMax / 2.0, yMax])
            }
            .emptyPlaceholder(entries) {
                Text(NSLocalizedString("noData", comment: ""))
            }
            .frame(height: 300)
            .padding(.trailing, 5)
        }
    }

    // MARK: - Entries List Section

    @ViewBuilder
    private var entriesListSection: some View {
        let entries = entries
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("allEntries", comment: "All Entries"))
                .tileHeaderStyle()
            VStack(spacing: CELL_SPACING) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.date?.description(.short) ?? NSLocalizedString("noDate", comment: ""))
                        Spacer()
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(formatDecimal(entry.decimalValue))
                                .font(.title3)
                            Text(measurementType.unit)
                                .font(.footnote)
                                .textCase(.uppercase)
                        }
                        .fontWeight(.semibold)
                    }
                    .padding(CELL_PADDING)
                    .onDeleteView {
                        withAnimation {
                            measurementController.deleteMeasurementEntry(entry)
                        }
                    }
                    .tileStyle()
                }
            }
            .emptyPlaceholder(entries) {
                Text(NSLocalizedString("noData", comment: ""))
            }
        }
    }

    // MARK: - Add Entry Sheet

    @ViewBuilder
    private var addEntrySheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    NSLocalizedString("date", comment: ""),
                    selection: $newEntryDate,
                    displayedComponents: [.date]
                )
                HStack {
                    Text(NSLocalizedString("value", comment: ""))
                    Spacer()
                    DecimalField(
                        placeholder: 0,
                        value: $newEntryValue,
                        maxDigits: 4,
                        decimalPlaces: 1,
                        index: Self.newEntryFieldIndex,
                        focusedIntegerFieldIndex: .constant(nil),
                        unit: measurementType.unit
                    )
                }
            }
            .navigationTitle(NSLocalizedString("addMeasurement", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        resetNewEntry()
                        isAddingEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("add", comment: "")) {
                        measurementController.addMeasurementEntry(
                            ofType: measurementType,
                            decimalValue: newEntryValue,
                            onDate: newEntryDate
                        )
                        resetNewEntry()
                        isAddingEntry = false
                    }
                    .fontWeight(.bold)
                    .disabled(newEntryValue == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Private Methods

    private func initializeChartScrollPosition() {
        chartScrollPosition = chartRange.initialScrollPosition(firstDataDate: firstDataDate)
    }

    private func resetNewEntry() {
        newEntryDate = .now
        newEntryValue = 0
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    /// Earliest entry date — anchors the scrollable domain and the All range (entries are newest-first).
    private var firstDataDate: Date? {
        entries.last?.date
    }

    private func chartYScaleMax(in entries: [MeasurementEntry]) -> Double {
        let maxValue = entries.map { $0.decimalValue }.max() ?? 100
        let yAxisMaxValues: [Double] = [10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000]
        return yAxisMaxValues.filter { $0 > maxValue }.min() ?? maxValue
    }

    private func nearestEntry(to date: Date?, in entries: [MeasurementEntry], visibleEnd: Date) -> MeasurementEntry? {
        let visibleEntries = entries.filter {
            guard let d = $0.date else { return false }
            return d >= chartScrollPosition && d <= visibleEnd
        }
        let candidates = visibleEntries.isEmpty ? entries : visibleEntries
        guard !candidates.isEmpty, let target = date else { return nil }
        return candidates.min { a, b in
            let ad = a.date ?? .distantPast
            let bd = b.date ?? .distantPast
            return abs(ad.timeIntervalSince(target)) < abs(bd.timeIntervalSince(target))
        }
    }

    // MARK: - Comparison header

    /// The scoreboard: the current measurement on the trailing side (the fixed subject), the highest
    /// value in the visible window on the leading side (the reference — it moves as you scroll), and
    /// the badge reading one against the other. Neutral, like Duration: a measurement sitting higher or
    /// lower isn't better or worse on its own.
    private func comparisonHeader(latest: MeasurementEntry?, highestVisible: Double?, firstDataDate: Date?) -> some View {
        let percentChange: Double? = {
            guard let latest, let highest = highestVisible, highest > 0 else { return nil }
            return (latest.decimalValue - highest) / highest * 100
        }()
        return MetricComparisonView(
            leading: .init(
                label: NSLocalizedString("highest", comment: ""),
                value: highestVisible.map(formatDecimal) ?? "––",
                unit: measurementType.unit,
                caption: chartRange.visibleWindowDescription(from: chartScrollPosition, firstDataDate: firstDataDate)
            ),
            trailing: .init(
                label: NSLocalizedString("current", comment: ""),
                value: latest.map { formatDecimal($0.decimalValue) } ?? "––",
                unit: measurementType.unit,
                caption: latest?.date.map { $0.formatted(.dateTime.day().month()) }
            ),
            trailingValueStyle: AnyShapeStyle(Color.accentColor.gradient),
            percentChange: percentChange,
            positiveColor: .secondary
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MeasurementDetailScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeasurementDetailScreen(measurementType: .bodyweight)
                .previewEnvironmentObjects()
        }
    }
}
