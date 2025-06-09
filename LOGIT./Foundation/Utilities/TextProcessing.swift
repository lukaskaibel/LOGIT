//
//  TextProcessing.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 03.08.23.
//

import Combine
import Foundation
import OpenAIKit
import OSLog
import UIKit
import Vision

enum TextProcessing {
    enum Error: Swift.Error {
        case emptyResponse, invalidImage, noRecognizedText, failedToFindBoundaries, invalidJSON
    }

    static func readText(from image: UIImage) -> AnyPublisher<String?, Swift.Error> {
        guard let cgImage = image.cgImage else {
            return Fail(error: Error.invalidImage).eraseToAnyPublisher()
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage)

        let publisher = Future<String?, Swift.Error> { promise in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    promise(.failure(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    promise(.failure(Error.noRecognizedText))
                    return
                }

                let text =
                    observations.compactMap {
                        $0.topCandidates(1).first?.string
                    }
                    .joined(separator: ", ")

                promise(.success(text))
            }

            do {
                try requestHandler.perform([request])
            } catch {
                promise(.failure(error))
            }
        }

        return AnyPublisher(publisher)
    }

    static func extractJsonDataFromString(_ inputString: String) -> AnyPublisher<Data, Swift.Error> {
        guard let startRange = inputString.range(of: "{"),
              let endRange = inputString.range(of: "}", options: .backwards)
        else {
            return Fail(error: Error.failedToFindBoundaries).eraseToAnyPublisher()
        }

        let jsonRange = startRange.lowerBound ..< endRange.upperBound
        let jsonString = String(inputString[jsonRange])

        guard let jsonData = jsonString.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: jsonData)) != nil
        else {
            return Fail(error: Error.invalidJSON).eraseToAnyPublisher()
        }

        return Just(jsonData)
            .setFailureType(to: Swift.Error.self)
            .eraseToAnyPublisher()
    }
}
