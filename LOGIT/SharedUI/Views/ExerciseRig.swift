//
//  ExerciseRig.swift
//  LOGIT
//

import Foundation
import simd

/// One built-in exercise's baked 3D animation, rendered live by `ExerciseFigureRenderer` from any
/// angle. `Tools/ExerciseAnimations` (`build.py rig`) solves the figure's skeleton and the
/// equipment as 3D primitives for every frame of the loop and stores them quantized, delta-coded
/// and deflated (`ExerciseRigs/<key>.rig`, a few kilobytes each); see `logitanim/export3d.py`.
final class ExerciseRig {
    enum Hand: Int {
        case fist = 0, palm = 1, wrist = 2
    }

    struct Equipment {
        enum Kind: String {
            case cyl, cap, cone, sph, box
        }

        enum Mode: Int {
            /// No knockout band; cuts one into what lies behind it; a backdrop (wall, water) drawn
            /// behind every other part from any side.
            case plain = 0, band = 1, backdrop = 2
        }

        let kind: Kind
        let color: SIMD3<Float>
        let mode: Mode
        let group: Int
        /// Where its parameters start in a frame's channels.
        let offset: Int
    }

    let key: String
    let duration: Double
    let fps: Double
    let frameCount: Int
    let channelCount: Int
    let muscles: [String]
    let muscleColor: SIMD3<Float>
    let palette: [String: SIMD3<Float>]
    /// The camera the exercise was designed for: degrees around the vertical (0 side-on, 90 from
    /// the front, -90 from behind) and above the horizon.
    let yaw: Float
    let pitch: Float
    let floor: (center: SIMD3<Float>, radius: Float)?
    /// The tight 2D content box seen from the exercise's own camera (x0, y0, x1, y1).
    let contentBox: SIMD4<Float>
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
    let hands: (left: Hand, right: Hand)
    let equipment: [Equipment]

    private let values: [Float]                 // frame-major
    private let jointOffsets: [String: Int]
    private let vectorOffsets: [String: Int]

    // MARK: Loading

    private static let directory = Bundle.main.url(forResource: "ExerciseRigs", withExtension: nil)
    private static let available: Set<String> = {
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(names.filter { $0.hasSuffix(".rig") }.map { String($0.dropLast(4)) })
    }()

    private static let cache = NSCache<NSString, ExerciseRig>()

    static func has(key: String) -> Bool {
        available.contains(key)
    }

    /// The rig for a library key, decoded once and cached.
    static func named(_ key: String) -> ExerciseRig? {
        if let rig = cache.object(forKey: key as NSString) {
            return rig
        }
        guard available.contains(key), let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).rig")),
              let rig = ExerciseRig(data: data) else { return nil }
        cache.setObject(rig, forKey: key as NSString)
        return rig
    }

    init?(data: Data) {
        guard data.count > 12, data.prefix(4) == Data("LGRG".utf8) else { return nil }
        let headerLength = Int(data.readUInt32(at: 4))
        let headerEnd = 8 + headerLength
        guard data.count >= headerEnd + 4,
              let header = try? JSONSerialization.jsonObject(with: data.subdata(in: 8 ..< headerEnd)) as? [String: Any]
        else { return nil }
        let bodyLength = Int(data.readUInt32(at: headerEnd))
        let bodyStart = headerEnd + 4
        guard data.count >= bodyStart + bodyLength,
              let inflated = try? (data.subdata(in: bodyStart ..< bodyStart + bodyLength) as NSData)
                .decompressed(using: .zlib) as Data
        else { return nil }

        guard let frames = header["frames"] as? Int, let channels = header["channels"] as? Int,
              let kinds = header["kinds"] as? String, kinds.count == channels,
              let posStep = (header["posStep"] as? NSNumber)?.floatValue,
              let dirOne = (header["dirOne"] as? NSNumber)?.floatValue,
              inflated.count == frames * channels * 2
        else { return nil }

        // channel-major int16 deltas -> frame-major floats
        let scales: [Float] = kinds.map { $0 == "d" ? 1 / dirOne : posStep }
        var values = [Float](repeating: 0, count: frames * channels)
        inflated.withUnsafeBytes { raw in
            let deltas = raw.bindMemory(to: Int16.self)
            for c in 0 ..< channels {
                var running: Int32 = 0
                let base = c * frames
                for f in 0 ..< frames {
                    running += Int32(Int16(littleEndian: deltas[base + f]))
                    values[f * channels + c] = Float(running) * scales[c]
                }
            }
        }

        func color(_ hex: Any?) -> SIMD3<Float> {
            guard let s = hex as? String, s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return .zero }
            return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
        }
        func vec3(_ any: Any?) -> SIMD3<Float> {
            let a = (any as? [NSNumber])?.map(\.floatValue) ?? [0, 0, 0]
            return SIMD3(a[0], a[1], a[2])
        }

        key = header["key"] as? String ?? ""
        duration = (header["duration"] as? NSNumber)?.doubleValue ?? 1
        fps = (header["fps"] as? NSNumber)?.doubleValue ?? 30
        frameCount = frames
        channelCount = channels
        self.values = values
        muscles = header["muscles"] as? [String] ?? []
        muscleColor = color(header["muscleColor"])
        palette = (header["palette"] as? [String: String] ?? [:]).mapValues { color($0) }
        let camera = header["camera"] as? [String: NSNumber]
        yaw = camera?["yaw"]?.floatValue ?? 0
        pitch = camera?["pitch"]?.floatValue ?? 0
        if let f = header["floor"] as? [String: Any] {
            floor = (vec3(f["center"]), (f["radius"] as? NSNumber)?.floatValue ?? 60)
        } else {
            floor = nil
        }
        let box = (header["box2d"] as? [NSNumber])?.map(\.floatValue) ?? [-50, 0, 50, 180]
        contentBox = SIMD4(box[0], box[1], box[2], box[3])
        let bounds = header["bounds"] as? [String: Any]
        boundsMin = vec3(bounds?["min"])
        boundsMax = vec3(bounds?["max"])
        let hands = (header["hands"] as? [Int]) ?? [0, 0]
        self.hands = (Hand(rawValue: hands[0]) ?? .fist, Hand(rawValue: hands[1]) ?? .fist)

        var offset = 0
        var joints: [String: Int] = [:]
        for name in header["joints"] as? [String] ?? [] {
            joints[name] = offset
            offset += 3
        }
        var vectors: [String: Int] = [:]
        for name in header["vectors"] as? [String] ?? [] {
            vectors[name] = offset
            offset += 3
        }
        jointOffsets = joints
        vectorOffsets = vectors
        let palette = self.palette
        equipment = (header["equipment"] as? [[String: Any]] ?? []).compactMap { e in
            guard let kind = (e["kind"] as? String).flatMap(Equipment.Kind.init(rawValue:)),
                  let count = e["count"] as? Int else { return nil }
            defer { offset += count }
            let mode = (e["mode"] as? Int).flatMap(Equipment.Mode.init(rawValue:))
                ?? ((e["gap"] as? Bool ?? false) ? .band : .plain)
            return Equipment(kind: kind, color: palette[e["color"] as? String ?? ""] ?? .one,
                             mode: mode, group: e["group"] as? Int ?? 0, offset: offset)
        }
        guard offset == channels else { return nil }
    }

    // MARK: Sampling

    /// The pose at `time` seconds into the loop, interpolated between the baked frames. The frames
    /// split the loop evenly (`duration / frameCount` apart: about, not exactly, 1 / fps).
    func pose(at time: Double) -> Pose {
        let f = (time.truncatingRemainder(dividingBy: duration) + duration)
            .truncatingRemainder(dividingBy: duration) / duration * Double(frameCount)
        let i0 = Int(f) % frameCount
        let i1 = (i0 + 1) % frameCount
        let w = Float(f - f.rounded(.down))
        var out = [Float](repeating: 0, count: channelCount)
        values.withUnsafeBufferPointer { v in
            let a = i0 * channelCount, b = i1 * channelCount
            for c in 0 ..< channelCount {
                out[c] = v[a + c] + (v[b + c] - v[a + c]) * w
            }
        }
        return Pose(values: out, joints: jointOffsets, vectors: vectorOffsets)
    }

    struct Pose {
        let values: [Float]
        fileprivate let joints: [String: Int]
        fileprivate let vectors: [String: Int]

        func joint(_ name: String) -> SIMD3<Float> {
            guard let o = joints[name] else { return .zero }
            return SIMD3(values[o], values[o + 1], values[o + 2])
        }

        /// A direction, unit length again after interpolation.
        func vector(_ name: String) -> SIMD3<Float> {
            guard let o = vectors[name] else { return SIMD3(1, 0, 0) }
            let v = SIMD3(values[o], values[o + 1], values[o + 2])
            let n = simd_length(v)
            return n > 1e-6 ? v / n : SIMD3(1, 0, 0)
        }

        func scalar(_ index: Int) -> Float {
            values[index]
        }

        func vec3(_ index: Int) -> SIMD3<Float> {
            SIMD3(values[index], values[index + 1], values[index + 2])
        }
    }
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32 {
        var v: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) { copyBytes(to: $0, from: offset ..< offset + 4) }
        return UInt32(littleEndian: v)
    }
}
