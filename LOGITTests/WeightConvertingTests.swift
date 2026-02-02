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
        
        // 50125 grams = 50.125 kg
        let formatted = formatWeightForDisplay(Int64(50125))
        XCTAssertEqual(formatted, "50.125", "50.125 kg should format with three decimals")
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
    
    // MARK: - Precision Tests
    
    func testRoundingToThreeDecimalPlaces() {
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
        
        // 50123 grams = 50.123 kg (exactly 3 decimal places)
        let displayed = convertWeightForDisplayingDecimal(Int64(50123))
        XCTAssertEqual(displayed, 50.123, accuracy: 0.0001)
        
        // Check that we don't get more than 3 decimal places
        let displayed2 = convertWeightForDisplayingDecimal(Int64(50001))
        XCTAssertEqual(displayed2, 50.001, accuracy: 0.0001)
    }
}
