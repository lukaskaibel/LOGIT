//
//  LocalizedMarkdown.swift
//  LOGIT
//
//  Created by OpenAI on 22.04.26.
//

import Foundation

enum LocalizedMarkdown {
    static func load(named resourceName: String) -> String? {
        let preferredLocale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let normalizedLocale = preferredLocale.replacingOccurrences(of: "_", with: "-")
        let languageCode = normalizedLocale.split(separator: "-").first.map(String.init)

        let candidates = [
            "\(resourceName)_\(normalizedLocale)",
            languageCode.map { "\(resourceName)_\($0)" },
            resourceName
        ].compactMap { $0 }

        for candidate in candidates {
            if let markdown = loadResource(named: candidate) {
                return markdown
            }
        }

        return nil
    }

    private static func loadResource(named resourceName: String) -> String? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
