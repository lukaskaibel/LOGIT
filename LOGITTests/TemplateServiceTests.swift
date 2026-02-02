//
//  TemplateServiceTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 03.10.23.
//
//  ⚠️ INTEGRATION TESTS - These tests require a valid OPENAI_API_KEY and network access.
//  They make live API calls for OCR and AI parsing, and are non-deterministic.
//  Set RUN_INTEGRATION_TESTS=true in environment to run these tests.
//

import Combine
@testable import LOGIT
import OSLog
import XCTest

final class TemplateServiceTests: XCTestCase {
    
    private var database: Database!
    private var templateService: TemplateService!
    private var cancellables = Set<AnyCancellable>()
    
    /// Set this to true to run integration tests locally
    /// In CI, these tests will be skipped unless RUN_INTEGRATION_TESTS env var is set
    private var shouldRunIntegrationTests: Bool {
        ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true"
    }
    
    override func setUp() {
        super.setUp()
        database = Database(isPreview: true)
        templateService = TemplateService(database: database)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        database = nil
        templateService = nil
        super.tearDown()
    }

    // MARK: - Integration Tests (Require OpenAI API + Test Images)

    func testAthleanXTotalBodyA() throws {
        // Skip if integration tests are disabled
        try XCTSkipUnless(shouldRunIntegrationTests, "Integration tests disabled. Set RUN_INTEGRATION_TESTS=true to run.")
        
        let expectation = XCTestExpectation(description: "Template creation completion")

        guard let image = getImage("athleanx_total_body_A") else {
            XCTFail("Getting test image failed")
            return
        }

        templateService.createTemplate(from: image)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case let .failure(error):
                    XCTFail("Failed to create template from image: \(error)")
                }
            }, receiveValue: { [weak self] template in
                guard let self = self else {
                    XCTFail("Self was deallocated before the closure was called!")
                    return
                }

                // Verify template name (case-insensitive)
                XCTAssertEqual(
                    template.name?.lowercased(),
                    "perfect total body workout a",
                    "Template name not matching photo."
                )
                
                // Verify number of exercises
                XCTAssertEqual(
                    template.setGroups.count,
                    7,
                    "Number of SetGroups not matching the photo"
                )

                // Verify specific exercises are detected
                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "squat",
                    numberOfSets: [3],
                    repetitions: [5],
                    weight: [0]
                ), "Should detect squat exercise")

                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "barbell hip thrust",
                    numberOfSets: [3, 4],
                    repetitions: [10, 11, 12],
                    weight: [0]
                ), "Should detect barbell hip thrust exercise")

                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "carry",
                    numberOfSets: [3, 4],
                    repetitions: [50],
                    weight: [0]
                ), "Should detect carry exercise")
                
                expectation.fulfill()
            })
            .store(in: &cancellables)

        // Longer timeout for OCR + AI processing
        wait(for: [expectation], timeout: 60)
    }

    // MARK: - Helper Methods

    private func getImage(_ name: String) -> UIImage? {
        let image = UIImage(named: name, in: Bundle(for: type(of: self)), compatibleWith: nil)
        return image
    }

    private func templateHasSetGroup(
        _ template: Template,
        nameContaining name: String,
        numberOfSets: [Int],
        repetitions: [Int],
        weight: [Int]
    ) -> Bool {
        guard let setGroup = template.setGroups.first(where: {
            $0.exercise?.name?.lowercased().contains(name.lowercased()) ?? false
        }) else {
            Logger().error("Template does not have exercise with name containing: '\(name)'")
            return false
        }
        
        var result = true
        
        if !numberOfSets.contains(setGroup.sets.count) {
            Logger().error("\(name) Number of sets '\(setGroup.sets.count)' not in expected values '\(numberOfSets)'")
            result = false
        }
        
        if let standardSet = setGroup.sets.first as? TemplateStandardSet {
            if !repetitions.contains(Int(standardSet.repetitions)) {
                Logger().error("\(name) Repetitions '\(standardSet.repetitions)' not in expected values '\(repetitions)'")
                result = false
            }
            if !weight.contains(Int(standardSet.weight)) {
                Logger().error("\(name) Weight '\(standardSet.weight)' not in expected values '\(weight)'")
                result = false
            }
        }
        
        return result
    }
}

