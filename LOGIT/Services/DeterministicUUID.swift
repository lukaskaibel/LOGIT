//
//  DeterministicUUID.swift
//  LOGIT
//

import Foundation

/// Generates stable UUIDs for bundled default content (exercises, templates).
///
/// Seeding must be able to recognize entities it created in an earlier run — across app
/// updates and reinstalls — so default entities get their UUID derived from a fixed
/// namespace plus their JSON id instead of a random one. The algorithm is frozen: default
/// exercises shipped with these UUIDs, so any change would orphan them in existing stores.
enum DeterministicUUID {
    static func make(namespace: String, id: String) -> UUID {
        let input = namespace + id

        guard let data = input.data(using: .utf8) else {
            return UUID()
        }

        // Simple hash-based UUID generation
        var hash = data.withUnsafeBytes { bytes -> [UInt8] in
            var result = [UInt8](repeating: 0, count: 16)
            for (index, byte) in bytes.enumerated() {
                result[index % 16] ^= byte
            }
            return result
        }

        // Set version (3) and variant bits for UUID
        hash[6] = (hash[6] & 0x0F) | 0x30
        hash[8] = (hash[8] & 0x3F) | 0x80

        let uuidString = String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                               hash[0], hash[1], hash[2], hash[3],
                               hash[4], hash[5], hash[6], hash[7],
                               hash[8], hash[9], hash[10], hash[11],
                               hash[12], hash[13], hash[14], hash[15])

        return UUID(uuidString: uuidString) ?? UUID()
    }
}
