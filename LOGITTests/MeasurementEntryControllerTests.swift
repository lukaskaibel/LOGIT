//
//  MeasurementEntryControllerTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 20.09.23.
//

import XCTest

@testable import LOGIT

final class MeasurementEntryControllerTests: XCTestCase {
    
    private var database: Database!
    private var controller: MeasurementEntryController!
    private var userDefaultsHelper: UserDefaultsTestHelper!
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        controller = MeasurementEntryController(database: database)
        userDefaultsHelper = UserDefaultsTestHelper()
        userDefaultsHelper.setTestValue("kg", forKey: "weightUnit")
    }
    
    override func tearDown() {
        userDefaultsHelper.restoreAll()
        database = nil
        controller = nil
        super.tearDown()
    }

    // MARK: - Basic Add/Get Tests

    func testAddMeasurementEntry() throws {
        let uniqueValue = Int.random(in: 1000...9999)
        controller.addMeasurementEntry(ofType: .bodyweight, value: uniqueValue, onDate: .now)
        
        let measurements = controller.getMeasurementEntries(ofType: .bodyweight)
        let values = measurements.map { $0.value }
        XCTAssertTrue(values.contains(uniqueValue), "Expected measurement with value \(uniqueValue)")
    }
    
    func testAddMeasurementEntryWithLengthType() throws {
        controller.addMeasurementEntry(ofType: .length(.bicepsLeft), value: 35, onDate: .now)

        let measurements = controller.getMeasurementEntries(ofType: .length(.bicepsLeft))
        XCTAssertTrue(measurements.count >= 1, "Expected at least one biceps measurement")
        
        let hasCorrectValue = measurements.contains { $0.value == 35 }
        XCTAssertTrue(hasCorrectValue, "Expected measurement with value 35")
    }

    func testGetMeasurementEntries() throws {
        // Create unique values for this test
        let uniqueChest = Int.random(in: 100...199)
        let uniqueNeck = Int.random(in: 40...59)
        
        controller.addMeasurementEntry(ofType: .length(.chest), value: uniqueChest, onDate: .now)
        controller.addMeasurementEntry(ofType: .length(.neck), value: uniqueNeck, onDate: .now)

        let chestEntries = controller.getMeasurementEntries(ofType: .length(.chest))
        let neckEntries = controller.getMeasurementEntries(ofType: .length(.neck))

        XCTAssertTrue(chestEntries.contains { $0.value == uniqueChest }, "Expected chest entry with value \(uniqueChest)")
        XCTAssertTrue(neckEntries.contains { $0.value == uniqueNeck }, "Expected neck entry with value \(uniqueNeck)")
    }
    
    // MARK: - Decimal Value Tests
    
    func testAddMeasurementEntryWithDecimalValue() {
        let decimalWeight = 75.5
        controller.addMeasurementEntry(ofType: .bodyweight, decimalValue: decimalWeight, onDate: .now)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let hasMatchingEntry = entries.contains { abs($0.decimalValue - decimalWeight) < 0.01 }
        XCTAssertTrue(hasMatchingEntry, "Expected entry with decimal value ~75.5")
    }
    
    func testDecimalValuePrecision() {
        // Test that small decimal values are preserved
        let preciseWeight = 80.125
        controller.addMeasurementEntry(ofType: .bodyweight, decimalValue: preciseWeight, onDate: .now)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let matchingEntry = entries.first { abs($0.decimalValue - preciseWeight) < 0.001 }
        XCTAssertNotNil(matchingEntry, "Should preserve 3 decimal places")
    }
    
    // MARK: - Delete Tests
    
    func testDeleteMeasurementEntry() {
        let uniqueValue = Int.random(in: 10000...99999)
        controller.addMeasurementEntry(ofType: .bodyweight, value: uniqueValue, onDate: .now)
        
        var entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let entryToDelete = entries.first { $0.value == uniqueValue }
        XCTAssertNotNil(entryToDelete, "Entry should exist before deletion")
        
        controller.deleteMeasurementEntry(entryToDelete!)
        
        // Database.delete uses context.perform which is async
        // Use performAndWait to ensure deletion completes before checking
        let expectation = self.expectation(description: "Delete completed")
        database.context.perform {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        
        entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let stillExists = entries.contains { $0.value == uniqueValue }
        XCTAssertFalse(stillExists, "Entry should be deleted")
    }
    
    // MARK: - Sorting Tests
    
    func testEntriesAreSortedByDateDescending() {
        let oldDate = Date.daysAgo(10)
        let recentDate = Date.daysAgo(1)
        
        // Use unique identifiable values
        let oldValue = 1111
        let recentValue = 2222
        
        // Add older entry first, then newer
        controller.addMeasurementEntry(ofType: .length(.waist), value: oldValue, onDate: oldDate)
        controller.addMeasurementEntry(ofType: .length(.waist), value: recentValue, onDate: recentDate)
        
        let entries = controller.getMeasurementEntries(ofType: .length(.waist))
        
        // Find positions of our test entries
        if let recentIndex = entries.firstIndex(where: { $0.value == recentValue }),
           let oldIndex = entries.firstIndex(where: { $0.value == oldValue }) {
            XCTAssertTrue(recentIndex < oldIndex, "More recent entry should come first (descending order)")
        }
    }
    
    // MARK: - Type Filtering Tests
    
    func testEntriesAreFilteredByType() {
        let uniqueBody = Int.random(in: 70...80)
        let uniqueChest = Int.random(in: 100...110)
        
        controller.addMeasurementEntry(ofType: .bodyweight, value: uniqueBody, onDate: .now)
        controller.addMeasurementEntry(ofType: .length(.chest), value: uniqueChest, onDate: .now)
        
        let bodyweightEntries = controller.getMeasurementEntries(ofType: .bodyweight)
        let chestEntries = controller.getMeasurementEntries(ofType: .length(.chest))
        
        // Bodyweight entries should not contain chest values
        let bodyweightHasChest = bodyweightEntries.contains { $0.value == uniqueChest }
        XCTAssertFalse(bodyweightHasChest, "Bodyweight entries should not include chest measurements")
        
        // Chest entries should not contain bodyweight values
        let chestHasBodyweight = chestEntries.contains { $0.value == uniqueBody }
        XCTAssertFalse(chestHasBodyweight, "Chest entries should not include bodyweight measurements")
    }
    
    // MARK: - Edge Cases
    
    func testAddEntryWithZeroValue() {
        controller.addMeasurementEntry(ofType: .bodyweight, value: 0, onDate: .now)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let hasZero = entries.contains { $0.value == 0 }
        XCTAssertTrue(hasZero, "Should allow zero value")
    }
    
    func testAddEntryWithLargeValue() {
        let largeValue = 500  // 500 kg (very large but possible for equipment/sled)
        controller.addMeasurementEntry(ofType: .bodyweight, value: largeValue, onDate: .now)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let hasLarge = entries.contains { $0.value == largeValue }
        XCTAssertTrue(hasLarge, "Should handle large values")
    }
    
    func testAddEntryWithPastDate() {
        let pastDate = Date.daysAgo(365)  // One year ago
        let uniqueValue = 9876
        
        controller.addMeasurementEntry(ofType: .bodyweight, value: uniqueValue, onDate: pastDate)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let entry = entries.first { $0.value == uniqueValue }
        
        XCTAssertNotNil(entry, "Should add entry with past date")
        if let entryDate = entry?.date {
            let calendar = Calendar.current
            XCTAssertTrue(calendar.isDate(entryDate, inSameDayAs: pastDate), "Entry should have correct past date")
        }
    }
    
    func testAddEntryWithFutureDate() {
        let futureDate = Date.daysFromNow(30)  // 30 days from now
        let uniqueValue = 5432
        
        controller.addMeasurementEntry(ofType: .bodyweight, value: uniqueValue, onDate: futureDate)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let entry = entries.first { $0.value == uniqueValue }
        
        XCTAssertNotNil(entry, "Should allow future date (for pre-planning)")
    }
    
    func testMultipleEntriesOnSameDay() {
        let today = Date()
        let value1 = 8001
        let value2 = 8002
        
        controller.addMeasurementEntry(ofType: .bodyweight, value: value1, onDate: today)
        controller.addMeasurementEntry(ofType: .bodyweight, value: value2, onDate: today)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyweight)
        let has1 = entries.contains { $0.value == value1 }
        let has2 = entries.contains { $0.value == value2 }
        
        XCTAssertTrue(has1 && has2, "Should allow multiple entries on the same day")
    }
    
    // MARK: - All Measurement Types
    
    func testAllLengthMeasurementTypes() {
        let lengthTypes: [MeasurementEntryType] = [
            .length(.chest),
            .length(.bicepsLeft),
            .length(.bicepsRight),
            .length(.waist),
            .length(.thighLeft),
            .length(.thighRight),
            .length(.calfLeft),
            .length(.calfRight),
            .length(.neck)
        ]
        
        for (index, type) in lengthTypes.enumerated() {
            let value = 100 + index
            controller.addMeasurementEntry(ofType: type, value: value, onDate: .now)
            
            let entries = controller.getMeasurementEntries(ofType: type)
            let hasEntry = entries.contains { $0.value == value }
            XCTAssertTrue(hasEntry, "Should handle \(type) measurement type")
        }
    }
    
    func testBodyFatPercentageMeasurement() {
        controller.addMeasurementEntry(ofType: .bodyFatPercentage, value: 15, onDate: .now)
        
        let entries = controller.getMeasurementEntries(ofType: .bodyFatPercentage)
        XCTAssertTrue(entries.contains { $0.value == 15 }, "Should handle body fat percentage")
    }
}

