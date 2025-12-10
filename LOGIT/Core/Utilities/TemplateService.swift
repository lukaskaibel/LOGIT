//
//  TemplateService.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 01.08.23.
//

import Combine
import OpenAIKit
import OSLog
import SwiftUI

class TemplateService: ObservableObject {
    private static let logger = Logger(subsystem: "com.lukaskbl.LOGIT", category: "TemplateService")

    enum Error: Swift.Error {
        case emptyResponse, invalidData, invalidImage, jsonParsingError, keysNotMatching,
             noRecognizedText
    }

    private let database: Database
    private var exerciseService: ExerciseService

    var cancellables = [AnyCancellable]()

    init(database: Database) {
        self.database = database
        exerciseService = ExerciseService(database: database)
    }

    // MARK: - Prompts

    private let systemPrompt = """
        Your job is to extract the workout from a text.
        You will have to infer if a value means number of sets, repetitions, or weight.
        Exercise names should only include the name of the exercise, nothing else.
        If you cannot infer a value, use the default from below.
        Return a JSON like this:
        Workout = {
            name: string = "",
            setGroups: [{
                exercise: Exercise,
                sets: [{
                    repetitions: integer = 0,
                    weight: integer = 0
                }]
            }]
        }
        Exercise = {
            name: string
        }
    """

    // MARK: - Public Methods

    func createTemplate(from uiImage: UIImage) -> AnyPublisher<Template, Swift.Error> {
        Self.logger.info("Creating Template from UIImage...")

        return TextProcessing.readText(from: uiImage)
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .flatMap { recognizedText -> AnyPublisher<String, Swift.Error> in
                guard let text = recognizedText else {
                    return Fail(error: Error.noRecognizedText).eraseToAnyPublisher()
                }
                return Just(text).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .flatMap { [unowned self] in generateTemplateJSONText(from: $0) }
            .flatMap { TextProcessing.extractJsonDataFromString($0) }
            .flatMap { [unowned self] in createTemplateDTO(from: $0) }
            .flatMap { [unowned self] in createTemplateFromDTO($0) }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - Private Helper Methods

    private func generateTemplateJSONText(from text: String) -> AnyPublisher<String, Swift.Error> {
        Self.logger.info("Generating Template JSON from text: \(text)")
        let systemMessage = AIMessage(role: .system, content: systemPrompt)
        let userMessage = AIMessage(role: .user, content: text)

        let publisher = Future<String, Swift.Error> { promise in
            OpenAIKit(apiToken: OPENAI_API_KEY)
                .sendChatCompletion(
                    newMessage: userMessage,
                    previousMessages: [systemMessage],
                    model: .custom("gpt-4o-mini"),
                    maxTokens: nil,
                    temperature: 0
                ) { result in
                    switch result {
                    case let .success(aiResult):
                        if let text = aiResult.choices.first?.message?.content {
                            promise(.success(text))
                        } else {
                            Self.logger.error("Failed to generate Template from JSON")
                            promise(.failure(Error.emptyResponse))
                        }
                    case let .failure(error):
                        Self.logger.error("Failed to generate Template from JSON: \(error)")
                        promise(.failure(error))
                    }
                }
        }

        return AnyPublisher(publisher)
    }

    private func createTemplateDTO(from jsonData: Data) -> AnyPublisher<TemplateDTO, Swift.Error> {
        Self.logger.info("Decoding JSON to TemplateDTO...")
        let decoder = JSONDecoder()
        return Just(jsonData)
            .decode(type: TemplateDTO.self, decoder: decoder)
            .eraseToAnyPublisher()
    }

    private func createTemplateFromDTO(_ dto: TemplateDTO) -> AnyPublisher<Template, Swift.Error> {
        Self.logger.info("Converting TemplateDTO to Template...")
        let exerciseNames = dto.setGroups.compactMap { $0.exercise.name }

        return exerciseService.matchExercisesToExisting(exerciseNames)
            .flatMap { [self] nameToExerciseMapping -> AnyPublisher<Template, Swift.Error> in
                let template = self.database.newTemplate(name: dto.name)

                let indexedPublishers: [AnyPublisher<(TemplateSetGroup, Int), Swift.Error>] = dto.setGroups.enumerated().compactMap { index, setGroupDTO in
                    guard let exerciseName = setGroupDTO.exercise.name else { return nil }

                    if let exercise = nameToExerciseMapping[exerciseName], let exercise = exercise {
                        let setGroup = self.createSetGroupFromDTO(setGroupDTO, withExercise: exercise)
                        return Just((setGroup, index))
                            .setFailureType(to: Swift.Error.self)
                            .eraseToAnyPublisher()
                    } else {
                        return self.exerciseService.createExercise(for: exerciseName)
                            .map { exercise in
                                self.database.flagAsTemporary(exercise)
                                return (self.createSetGroupFromDTO(setGroupDTO, withExercise: exercise), index)
                            }
                            .eraseToAnyPublisher()
                    }
                }

                return Publishers.Sequence(sequence: indexedPublishers)
                    .flatMap(maxPublishers: .max(dto.setGroups.count)) { $0 }
                    .collect()
                    .map { indexedSetGroups in
                        let sortedSetGroups = indexedSetGroups.sorted(by: { $0.1 < $1.1 }).map { $0.0 }
                        template.setGroups.append(contentsOf: sortedSetGroups)
                        return template
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func createSetGroupFromDTO(_ dto: TemplateSetGroupDTO, withExercise exercise: Exercise) -> TemplateSetGroup {
        Self.logger.info("Converting TemplateSetGroup from TemmplateSetGroupDTO")
        let setGroup = database.newTemplateSetGroup(createFirstSetAutomatically: false, exercise: exercise)
        for setDTO in dto.sets {
            database.newTemplateStandardSet(repetitions: setDTO.repetitions, weight: setDTO.weight, setGroup: setGroup)
        }
        return setGroup
    }

    private func createOrGetExistingExercise(for name: String) -> AnyPublisher<
        Exercise, Swift.Error
    > {
        Self.logger.info("Creating or fetching existing exercise matching name: \(name)")
        if let existingExercise = database.getExercises(withNameIncluding: name).first {
            Self.logger.debug("Found existing Exercise with name: \(existingExercise.name)")
            return Just(existingExercise)
                .setFailureType(to: Swift.Error.self)
                .eraseToAnyPublisher()
        } else {
            return exerciseService.createExercise(for: name)
                .handleEvents(receiveOutput: { [unowned self] newExercise in
                    database.flagAsTemporary(newExercise)
                })
                .eraseToAnyPublisher()
        }
    }
}
