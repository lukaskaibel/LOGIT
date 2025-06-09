//
//  ExerciseService.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 04.08.23.
//

import Combine
import Foundation
import OpenAIKit
import OSLog

class ExerciseService {
    private static let logger = Logger(subsystem: ".com.lukaskbl.LOGIT", category: "ExerciseService")

    enum Error: Swift.Error {
        case emptyResponse, jsonParsingError, keysNotMatching
    }

    let database: Database

    init(database: Database) {
        self.database = database
    }

    // MARK: - Prompts

    let createExercisePrompt = """
        For the following exercise name, return a JSON object with the type of training.
        enum Type {
            \((MuscleGroup.allCases.map { $0.rawValue }).joined(separator: ", "))
        }
        Return JSON of form:
        {
        name: string,
        type: Type
        }
    """

    lazy var getMatchingExercisePrompt = """
        Your job is to map a list of words to a list of exercises, if the word refers to the exercise.
        The word should also be mapped to the exercise, if it just means the exercise in a different language.
        Do not match exercises with different equipment (e.g. dumbbell != barbell) or execution (e.g. standing != sitting).
        Return a JSON like this: { matches: [{ word: string, exercise: Exercise | null }] }.
        enum Exercise {
            \(database.getExercises().compactMap { $0.name }.joined(separator: ", "))
        }
    """

    // MARK: - Public Methods

    /// Matches a given list of Exercise names to the corresponding Exercise entity, if one exists.
    /// - Parameter exerciseNames: List of Exercise names.
    /// - Returns: Returns a publisher that publishes a dictionary with the given names as keys and the Exercises, if found, as values (otherwise nil).
    func matchExercisesToExisting(_ exerciseNames: [String]) -> AnyPublisher<
        [String: Exercise?], Swift.Error
    > {
        Self.logger.info("Looking for existing Exercises matching: \(exerciseNames)")
        let systemMessage = AIMessage(role: .system, content: getMatchingExercisePrompt)
        let userMessage = AIMessage(role: .user, content: exerciseNames.joined(separator: ", "))
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
                            promise(.failure(Error.emptyResponse))
                        }
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
        }
        .flatMap { text -> AnyPublisher<Data, Swift.Error> in
            return TextProcessing.extractJsonDataFromString(text)
        }
        .flatMap { jsonData -> AnyPublisher<[String: Exercise?], Swift.Error> in
            return Future<[String: Exercise?], Swift.Error> { [unowned self] promise in
                guard
                    let json = try? JSONSerialization.jsonObject(with: jsonData, options: [])
                    as? [String: Any]
                else {
                    return promise(.failure(Error.jsonParsingError))
                }

                guard let matchesKey = findKey("matches", in: json)
                else {
                    return promise(.failure(Error.keysNotMatching))
                }

                let matches = json[matchesKey] as? [[String: Any]]

                var result = [String: Exercise?]()
                matches?
                    .forEach { match in
                        guard let exerciseNameKey = findKey("word", in: match),
                              let existingExerciseNameKey = findKey("exercise", in: match)
                        else {
                            return promise(.failure(Error.keysNotMatching))
                        }

                        guard let exerciseName = match[exerciseNameKey] as? String else { return }
                        guard let existingExerciseName = match[existingExerciseNameKey] as? String
                        else { return }

                        let existingExercise =
                            database.getExercises(withNameIncluding: existingExerciseName).first
                        result[exerciseName] = existingExercise
                    }

                let pairedExercises = zip(result.keys, result.values.map { $0?.name ?? "nil" }).map { "\($0): \($1)" }.joined(separator: ", ")
                Self.logger.debug("Found matching exercises for names: \(pairedExercises)")
                promise(.success(result))
            }
            .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()

        return publisher
    }

    /// Creates a new Exercise entity in the database with corresponding Muscle Group (using ChatGPT API).
    /// - Parameter name: Name of the exercise that will be created.
    /// - Returns: Returns a publisher that publishes either the Exercise, or an error.
    func createExercise(for name: String) -> AnyPublisher<Exercise, Swift.Error> {
        Self.logger.info("Creating Exercise for name: \(name)")

        let systemMessage = AIMessage(role: .system, content: createExercisePrompt)
        let userMessage = AIMessage(role: .user, content: name)

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
                            print("Got response for system message: \(systemMessage)")
                            Self.logger.debug("Returned Exercise JSON: \(text)")
                            promise(.success(text))
                        } else {
                            promise(.failure(Error.emptyResponse))
                        }
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
        }
        .flatMap { text -> AnyPublisher<Data, Swift.Error> in
            return TextProcessing.extractJsonDataFromString(text)
        }
        .flatMap { [unowned self] jsonData -> AnyPublisher<Exercise, Swift.Error> in
            return createExercise(from: jsonData)
        }
        .eraseToAnyPublisher()

        return publisher
    }

    // MARK: - Private Helper Methods

    // Helper function to find a matching key, checking if the key contains the property name
    private func findKey(_ propertyName: String, in dictionary: [String: Any]) -> String? {
        return dictionary.keys.first(where: { $0.lowercased().contains(propertyName.lowercased()) })
    }

    private func createExercise(from jsonData: Data) -> AnyPublisher<Exercise, Swift.Error> {
        Self.logger.info("Decoding Exercise from JSON: \(jsonData.description)")
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        } else {
            print("Failed to convert Data to String")
        }
        let decoder = JSONDecoder()
        return Just(jsonData)
            .decode(type: ExerciseDTO.self, decoder: decoder)
            .tryMap { [unowned self] dto -> Exercise in
                guard let name = dto.name, let muscleGroup = dto.type else {
                    throw Error.jsonParsingError
                }
                return self.database.newExercise(name: name, muscleGroup: muscleGroup)
            }
            .eraseToAnyPublisher()
    }
}
