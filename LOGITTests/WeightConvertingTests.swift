//
//  WeightConvertingTests.swift
//  LOGITTests
//
//  Tests for weight unit conversion utilities
//

import XCTest

@testable import LOGIT

final class WeightConvertingTests: XCTestCase {
    
    private var userDefaultsHelper: UserDefaultsTestHelper!
    
    override func setUp() {
        super.setUp()
        userDefaultsHelper = UserDefaultsTestHelper()
    }
    
    override func tearDown() {
        userDefaultsHelper.restoreAll()
        super.tearDown()
    }
    
    // MARK: - Kilograms Conversion Tests
    
    func testConvertWeightForStoringKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 1 kg = 1000 grams
        let stored = convertWeightForStoring(Int64(1))
        XCTAssertEqual(stored, 1000, "1 kg should be stored as 1000 grams")
    }
    
    func testConvertWeightForStoringKgDouble() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 1.5 kg = 1500 grams
        let stored = convertWeightForStoring(1.5)
        XCTAssertEqual(stored, 1500, "1.5 kg should be stored as 1500 grams")
    }
    
    func testConvertWeightForDisplayingKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 1000 grams = 1 kg
        let displayed = convertWeightForDisplaying(Int64(1000))
        XCTAssertEqual(displayed, 1, "1000 grams should display as 1 kg")
    }
    
    func testConvertWeightForDisplayingDecimalKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 1500 grams = 1.5 kg
        let displayed = convertWeightForDisplayingDecimal(Int64(1500))
        XCTAssertEqual(displayed, 1.5, accuracy: 0.001, "1500 grams should display as 1.5 kg")
    }
    
    // MARK: - Pounds Conversion Tests
    
    func testConvertWeightForStoringLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        // 1 lbs ≈ 453.592 grams
        let stored = convertWeightForStoring(Int64(1))
        XCTAssertEqual(stored, 453, "1 lbs should be stored as ~453 grams (rounded)")
    }
    
    func testConvertWeightForStoringLbsDouble() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        // 2.5 lbs ≈ 1133.98 grams
        let stored = convertWeightForStoring(2.5)
        XCTAssertEqual(stored, 1134, "2.5 lbs should be stored as ~1134 grams")
    }
    
    func testConvertWeightForDisplayingLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        // 453 grams ≈ 1 lbs
        let displayed = convertWeightForDisplaying(Int64(454))
        XCTAssertEqual(displayed, 1, "~454 grams should display as 1 lbs")
    }
    
    func testConvertWeightForDisplayingDecimalLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        // 1134 grams ≈ 2.5 lbs
        let displayed = convertWeightForDisplayingDecimal(Int64(1134))
        XCTAssertEqual(displayed, 2.5, accuracy: 0.01, "1134 grams should display as ~2.5 lbs")
    }
    
    // MARK: - Round Trip Tests
    
    func testRoundTripKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        let originalValue = 75.5
        let stored = convertWeightForStoring(originalValue)
        let displayed = convertWeightForDisplayingDecimal(stored)
        
        XCTAssertEqual(displayed, originalValue, accuracy: 0.001, "Round trip should preserve value for kg")
    }
    
    func testRoundTripLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        let originalValue = 165.5
        let stored = convertWeightForStoring(originalValue)
        let displayed = convertWeightForDisplayingDecimal(stored)
        
        XCTAssertEqual(displayed, originalValue, accuracy: 0.01, "Round trip should preserve value for lbs")
    }
    
    // MARK: - Edge Cases
    
    func testZeroWeightKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        XCTAssertEqual(convertWeightForStoring(Int64(0)), 0, "Zero kg should store as 0 grams")
        XCTAssertEqual(convertWeightForDisplaying(Int64(0)), 0, "Zero grams should display as 0 kg")
        XCTAssertEqual(convertWeightForDisplayingDecimal(Int64(0)), 0.0, "Zero grams should display as 0.0 kg")
    }
    
    func testZeroWeightLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        XCTAssertEqual(convertWeightForStoring(Int64(0)), 0, "Zero lbs should store as 0 grams")
        XCTAssertEqual(convertWeightForDisplaying(Int64(0)), 0, "Zero grams should display as 0 lbs")
        XCTAssertEqual(convertWeightForDisplayingDecimal(Int64(0)), 0.0, "Zero grams should display as 0.0 lbs")
    }
    
    func testLargeWeightKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 500 kg (reasonable max for deadlift world record territory)
        let stored = convertWeightForStoring(Int64(500))
        XCTAssertEqual(stored, 500000, "500 kg should store as 500000 grams")
        
        let displayed = convertWeightForDisplaying(stored)
        XCTAssertEqual(displayed, 500, "500000 grams should display as 500 kg")
    }
    
    func testLargeWeightLbs() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")
        
        // 1000 lbs
        let stored = convertWeightForStoring(Int64(1000))
        let displayed = convertWeightForDisplaying(stored)
        XCTAssertEqual(displayed, 1000, "Round trip of 1000 lbs should work")
    }
    
    func testSmallDecimalKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 0.5 kg = 500 grams
        let stored = convertWeightForStoring(0.5)
        XCTAssertEqual(stored, 500, "0.5 kg should store as 500 grams")
    }
    
    func testVerySmallDecimalKg() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 0.001 kg = 1 gram
        let stored = convertWeightForStoring(0.001)
        XCTAssertEqual(stored, 1, "0.001 kg should store as 1 gram")
    }
    
    func testNegativeWeight() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // Negative weights should work mathematically (though not used in practice)
        let stored = convertWeightForStoring(-5.0)
        XCTAssertEqual(stored, -5000, "Negative weight should store correctly")
        
        let displayed = convertWeightForDisplayingDecimal(Int64(-5000))
        XCTAssertEqual(displayed, -5.0, "Negative grams should display correctly")
    }
    
    // MARK: - Format Weight For Display Tests
    
    func testFormatWeightForDisplayZero() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        let formatted = formatWeightForDisplay(Int64(0))
        XCTAssertEqual(formatted, "0", "Zero should format as '0'")
    }
    
    func testFormatWeightForDisplayWholeNumber() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 50000 grams = 50 kg
        let formatted = formatWeightForDisplay(Int64(50000))
        XCTAssertEqual(formatted, "50", "50 kg should format without decimals")
    }
    
    func testFormatWeightForDisplayWithDecimal() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 50500 grams = 50.5 kg
        let formatted = formatWeightForDisplay(Int64(50500))
        XCTAssertEqual(formatted, "50.5", "50.5 kg should format with one decimal")
    }
    
    func testFormatWeightForDisplayMultipleDecimals() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")

        // 50125 grams = 50.125 kg — kg keeps 3 fraction digits (grams are exact in kg).
        let formatted = formatWeightForDisplay(Int64(50125))
        XCTAssertEqual(formatted, "50.125", "kg display keeps gram-exact decimals")
    }

    /// Regression: entering 162.5 lbs stores round(162.5 × 453.592) = 73709 g; at 3 display
    /// decimals that came back as "162.501" (the reported rounding artifact). Two-decimal
    /// display must round the storage noise away.
    func testFormatWeightForDisplayLbsRoundTripHasNoGramNoise() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")

        let stored = convertWeightForStoring(162.5)
        XCTAssertEqual(formatWeightForDisplay(stored), "162.5", "entered lbs values must round-trip cleanly")

        let storedQuarter = convertWeightForStoring(190.25)
        XCTAssertEqual(formatWeightForDisplay(storedQuarter), "190.25", "quarter-pound plates must round-trip cleanly")
    }
    
    // MARK: - Integer Overload Tests
    
    func testConvertWeightForDisplayingInt() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        let displayed = convertWeightForDisplaying(1000)  // Int overload
        XCTAssertEqual(displayed, 1, "Int overload should work same as Int64")
    }
    
    func testConvertWeightForDisplayingDecimalInt() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        let displayed = convertWeightForDisplayingDecimal(1500)  // Int overload
        XCTAssertEqual(displayed, 1.5, accuracy: 0.001, "Int overload for decimal should work same as Int64")
    }
    
    func testFormatWeightForDisplayInt() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        let formatted = formatWeightForDisplay(50000)  // Int overload
        XCTAssertEqual(formatted, "50", "Int overload for format should work same as Int64")
    }
    
    // MARK: - LBS Display Rounding (95 lbs → 94.999 bug)

    func testLbsWholeNumberRoundTripDisplaysWholeNumber() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")

        // 95 lbs stores as round(95 × 453.592) = 43091 g; reading it back at 3 decimal
        // places showed 94.999. It must display as exactly 95 again.
        let stored = convertWeightForStoring(95.0)
        XCTAssertEqual(stored, 43091)
        XCTAssertEqual(convertWeightForDisplayingDecimal(stored), 95.0)
        XCTAssertEqual(formatWeightForDisplay(stored), "95")
    }

    func testLbsRoundTripIsExactForQuarterPoundIncrements() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")

        // Every 0.25 lb increment up to 1000 lbs must survive store → display unchanged.
        var value = 0.25
        while value <= 1000 {
            let stored = convertWeightForStoring(value)
            XCTAssertEqual(
                convertWeightForDisplayingDecimal(stored), value,
                "Round trip changed \(value) lbs"
            )
            value += 0.25
        }
    }

    func testLbsRoundTripIsExactForTwoDecimalValues() {
        userDefaultsHelper.setTestValue("lbs", forKey: "weightUnit")

        // Arbitrary 2-decimal entries (not just plate increments) round-trip exactly.
        for hundredths in [1, 33, 1099, 10201, 22537, 40007, 99999] {
            let value = Double(hundredths) / 100
            let stored = convertWeightForStoring(value)
            XCTAssertEqual(
                convertWeightForDisplayingDecimal(stored), value,
                "Round trip changed \(value) lbs"
            )
        }
    }

    func testKgRoundTripStaysExactAtThreeDecimals() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")

        // Kilograms map to grams exactly, so 3-decimal entries must stay untouched.
        let stored = convertWeightForStoring(50.125)
        XCTAssertEqual(stored, 50125)
        XCTAssertEqual(convertWeightForDisplayingDecimal(stored), 50.125)
    }

    // MARK: - Precision Tests

    func testRoundingToThreeDecimalPlaces() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")

        // The decimal CONVERSION keeps 3 places so data consumers (measurements, charts)
        // don't lose stored precision; only display FORMATTING rounds to 2.
        let displayed = convertWeightForDisplayingDecimal(Int64(50123))
        XCTAssertEqual(displayed, 50.123, accuracy: 0.0001)

        let displayed2 = convertWeightForDisplayingDecimal(Int64(50001))
        XCTAssertEqual(displayed2, 50.001, accuracy: 0.0001)
    }
}

// MARK: - Distance Conversion Tests

final class DistanceConvertingTests: XCTestCase {

    private var userDefaultsHelper: UserDefaultsTestHelper!

    override func setUp() {
        super.setUp()
        userDefaultsHelper = UserDefaultsTestHelper()
    }

    override func tearDown() {
        userDefaultsHelper.restoreAll()
        super.tearDown()
    }

    // MARK: - Long Distances (km/mi)

    func testConvertDistanceForStoringKm() {
        userDefaultsHelper.setTestValue("km", forKey: "distanceUnit")

        XCTAssertEqual(convertDistanceForStoring(5.5), 5500, "5.5 km should store as 5500 meters")
    }

    func testConvertDistanceForStoringMi() {
        userDefaultsHelper.setTestValue("mi", forKey: "distanceUnit")

        XCTAssertEqual(convertDistanceForStoring(1.0), 1609, "1 mi should store as 1609 meters")
    }

    func testConvertDistanceForDisplayingDecimalKm() {
        userDefaultsHelper.setTestValue("km", forKey: "distanceUnit")

        XCTAssertEqual(convertDistanceForDisplayingDecimal(5500), 5.5, accuracy: 0.001)
    }

    func testConvertDistanceForDisplayingDecimalMi() {
        userDefaultsHelper.setTestValue("mi", forKey: "distanceUnit")

        XCTAssertEqual(convertDistanceForDisplayingDecimal(1609), 1.0, accuracy: 0.01)
    }

    func testFormatDistanceDropsTrailingZeros() {
        userDefaultsHelper.setTestValue("km", forKey: "distanceUnit")

        XCTAssertEqual(formatDistanceForDisplay(Int64(5000)), "5")
        XCTAssertEqual(formatDistanceForDisplay(Int64(5500)), "5.5")
        XCTAssertEqual(formatDistanceForDisplay(Int64(5550)), "5.55")
        XCTAssertEqual(formatDistanceForDisplay(Int64(0)), "0")
    }

    // MARK: - Short Distances (m/yd)

    func testShortDistanceMetersPassThrough() {
        userDefaultsHelper.setTestValue("km", forKey: "distanceUnit")

        XCTAssertEqual(convertShortDistanceForStoring(40), 40, "Meters store as meters")
        XCTAssertEqual(convertShortDistanceForDisplaying(40), 40)
    }

    func testShortDistanceYardsConversion() {
        userDefaultsHelper.setTestValue("mi", forKey: "distanceUnit")

        XCTAssertEqual(convertShortDistanceForStoring(50), 46, "50 yd should store as 46 meters")
        XCTAssertEqual(convertShortDistanceForDisplaying(46), 50, "46 meters should display as 50 yd")
    }

    // MARK: - Style Dispatch

    func testFormatDistanceForDisplayByStyle() {
        userDefaultsHelper.setTestValue("km", forKey: "distanceUnit")

        XCTAssertEqual(formatDistanceForDisplay(Int64(5500), style: .long), "5.5")
        XCTAssertEqual(formatDistanceForDisplay(Int64(40), style: .short), "40")
        XCTAssertEqual(distanceUnitTitle(for: .long), "km")
        XCTAssertEqual(distanceUnitTitle(for: .short), "m")
    }

    // MARK: - Measurement Type Field Consistency

    func testInputFieldCountMatchesTrackedFields() {
        for type in SetMeasurementType.allCases {
            let tracked = [
                type.usesRepetitions, type.usesWeight, type.usesDuration, type.usesDistance,
            ].filter { $0 }.count
            XCTAssertEqual(
                type.inputFieldCount, tracked,
                "\(type.rawValue) must show one input field per tracked value"
            )
        }
    }

    func testDistanceStyleExistsExactlyForDistanceTypes() {
        for type in SetMeasurementType.allCases {
            XCTAssertEqual(
                type.distanceStyle != nil, type.usesDistance,
                "\(type.rawValue) distance style must accompany a distance field"
            )
        }
    }
}
