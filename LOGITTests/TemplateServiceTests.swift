//
//  TemplateServiceTests.swift
//  LOGITTests
//
//  Created by Lukas Kaibel on 03.10.23.
//

import Combine
@testable import LOGIT
import OSLog
import XCTest

final class TemplateServiceTests: XCTestCase {
    let database = Database(isPreview: true)
    lazy var templateService = TemplateService(database: database)

    var cancellables = [AnyCancellable]()

    func testAthleanXTotalBodyA() throws {
        let expectation = XCTestExpectation(description: "Template creation completion")

        let image = getImage("athleanx_total_body_A")
        XCTAssertNotNil(image, "Getting test image failed")

        templateService.createTemplate(from: image!)
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

                XCTAssertEqual(template.name?.lowercased(), "perfect total body workout a", "Template name not matching photo.")
                XCTAssertEqual(template.setGroups.count, 7, "Number of SetGroups not matching the photo")

                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "squat",
                    numberOfSets: [3],
                    repetitions: [5],
                    weight: [0]
                ))

                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "barbell hip thrust",
                    numberOfSets: [3, 4],
                    repetitions: [10, 11, 12],
                    weight: [0]
                ))

//                XCTAssertTrue(self.templateHasSetGroup(
//                    template,
//                    nameContaining: "weighted chin ups",
//                    numberOfSets: [3],
//                    repetitions: [6, 7, 8, 9, 10],
//                    weight: [0]
//                ))

                XCTAssertTrue(self.templateHasSetGroup(
                    template,
                    nameContaining: "carry",
                    numberOfSets: [3, 4],
                    repetitions: [50],
                    weight: [0]
                ))
                expectation.fulfill() // Signal that the async work is done
            })
            .store(in: &cancellables)

        // Wait for the expectation to be fulfilled (with a timeout)
        wait(for: [expectation], timeout: 60)
    }

    private func getImage(_ name: String) -> UIImage? {
        // Access the image directly from the asset catalog
        let image = UIImage(named: name, in: Bundle(for: type(of: self)), compatibleWith: nil)

        if image == nil {
            XCTFail("Couldn't find image '\(name)' in WorkoutImages.")
        }

        return image
    }

    private func templateHasSetGroup(
        _ template: Template,
        nameContaining name: String,
        numberOfSets: [Int],
        repetitions: [Int],
        weight: [Int]
    ) -> Bool {
        var result = true
        if let setGroup = template.setGroups.first(where: { $0.exercise?.name?.lowercased().contains(name.lowercased()) ?? false }) {
            if !numberOfSets.contains(where: { $0 == setGroup.sets.count }) {
                result = false
                Logger().error("\(name) Number of sets '\(setGroup.sets.count)' not equal to '\(numberOfSets)'")
            }
            if !repetitions.contains(where: { $0 == (setGroup.sets.value(at: 0) as? TemplateStandardSet)!.repetitions }) {
                result = false
                Logger().error("\(name) Repetitions '\((setGroup.sets.value(at: 0) as? TemplateStandardSet)!.repetitions)' not equal to '\(repetitions)'")
            }
            if !weight.contains(where: { $0 == (setGroup.sets.value(at: 0) as? TemplateStandardSet)!.weight }) {
                result = false
                Logger().error("\(name) Weight '\((setGroup.sets.value(at: 0) as? TemplateStandardSet)!.weight)' not equal to '\(weight)'")
            }
        } else {
            result = false
            Logger().error("\(name) Template does not have exercise with name containing: '\(name)'")
        }
        return result
    }
}
