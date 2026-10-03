// Offscreen test harness for the app's real-time exercise figure (LOGIT/SharedUI/Views/
// ExerciseRig.swift, ExerciseFigureScene.swift, ExerciseFigureShaders.swift), built for macOS
// by metal/run.sh. Renders frames to PNG on the card colour and times the GPU.
//
//   harness <file.rig> <out.png> <time> <yaw> <pitch> <px> <originX> <originY> <scale> [repeat]
//
// origin/scale place the world on the canvas exactly as sdf.Canvas does (pixels of the world
// origin, pixels per cm), so the output lines up with the Python renders pixel for pixel.

import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import simd

struct Uniforms {
    var origin: SIMD2<Float>
    var scale: Float
    var primCount: UInt32
}

let args = CommandLine.arguments
guard args.count >= 10 else {
    print("usage: harness <file.rig> <out.png> <time> <yaw> <pitch> <px> <originX> <originY> <scale> [repeat]")
    exit(2)
}
let rigURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let time = Double(args[3])!
let yaw = Float(args[4])!, pitch = Float(args[5])!
let px = Int(args[6])!
let origin = SIMD2<Float>(Float(args[7])!, Float(args[8])!)
let scale = Float(args[9])!
let repeats = args.count > 10 ? Int(args[10])! : 1

let loadStart = CFAbsoluteTimeGetCurrent()
guard let data = try? Data(contentsOf: rigURL), let rig = ExerciseRig(data: data) else {
    print("could not load \(rigURL.path)")
    exit(1)
}
let device = MTLCreateSystemDefaultDevice()!
let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
// later loads, without first-use costs (JSON, decompression)
var later: [Double] = []
for _ in 0 ..< 5 {
    let s0 = CFAbsoluteTimeGetCurrent()
    _ = ExerciseRig(data: try! Data(contentsOf: rigURL))
    later.append((CFAbsoluteTimeGetCurrent() - s0) * 1000)
}
print(String(format: "later rig loads: %@ ms", later.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
let compileStart = CFAbsoluteTimeGetCurrent()
let library = try! device.makeLibrary(source: ExerciseFigureShaders.source, options: nil)
let desc = MTLRenderPipelineDescriptor()
desc.vertexFunction = library.makeFunction(name: "figure_vertex")
desc.fragmentFunction = library.makeFunction(name: "figure_fragment")
desc.colorAttachments[0].pixelFormat = .rgba8Unorm
let pipeline = try! device.makeRenderPipelineState(descriptor: desc)
let compileTime = CFAbsoluteTimeGetCurrent() - compileStart
let queue = device.makeCommandQueue()!

let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: px, height: px, mipmapped: false)
texDesc.usage = [.renderTarget, .shaderRead]
texDesc.storageMode = .shared
let target = device.makeTexture(descriptor: texDesc)!

func buffer<T>(_ array: [T]) -> MTLBuffer {
    let bytes = max(MemoryLayout<T>.stride * array.count, 16)
    let b = device.makeBuffer(length: bytes, options: .storageModeShared)!
    array.withUnsafeBytes { raw in
        if let base = raw.baseAddress { memcpy(b.contents(), base, raw.count) }
    }
    return b
}

var cpuTotal = 0.0, gpuTotal = 0.0
var frame = FigureFrame()
for i in 0 ..< repeats {
    let t0 = CFAbsoluteTimeGetCurrent()
    // time the frames leading up to `time`, so the last one rendered (and saved) is `time` itself
    let pose = rig.pose(at: time - Double(repeats - 1 - i) / 30.0)
    frame = FigureScene.build(rig: rig, pose: pose, camera: FigureCamera(yaw: yaw, pitch: pitch))
    var uniforms = Uniforms(origin: origin, scale: scale, primCount: UInt32(frame.prims.count))
    cpuTotal += CFAbsoluteTimeGetCurrent() - t0

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    let cmd = queue.makeCommandBuffer()!
    let enc = cmd.makeRenderCommandEncoder(descriptor: pass)!
    enc.setRenderPipelineState(pipeline)
    enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    enc.setFragmentBuffer(buffer(frame.prims), offset: 0, index: 1)
    enc.setFragmentBuffer(buffer(frame.verts), offset: 0, index: 2)
    enc.setFragmentBuffer(buffer(frame.overlays), offset: 0, index: 3)
    enc.setFragmentBuffer(buffer(frame.aux), offset: 0, index: 4)
    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
    gpuTotal += cmd.gpuEndTime - cmd.gpuStartTime
}

// read back, composite over the card colour (#1C1C1E), write PNG
var pixels = [UInt8](repeating: 0, count: px * px * 4)
target.getBytes(&pixels, bytesPerRow: px * 4, from: MTLRegionMake2D(0, 0, px, px), mipmapLevel: 0)
let bg: [Float] = [0x1C, 0x1C, 0x1E].map { Float($0) / 255 }
var rgb = [UInt8](repeating: 0, count: px * px * 3)
for i in 0 ..< px * px {
    let a = Float(pixels[i * 4 + 3]) / 255
    for c in 0 ..< 3 {
        let v = Float(pixels[i * 4 + c]) / 255 + bg[c] * (1 - a)
        rgb[i * 3 + c] = UInt8(max(0, min(255, v * 255 + 0.5)))
    }
}
let provider = CGDataProvider(data: Data(rgb) as CFData)!
let image = CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: px * 3,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: 0),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print(String(format: "rig load+decode %.2f ms, shader compile %.1f ms", loadTime * 1000, compileTime * 1000))
print(String(format: "prims %d verts %d overlays %d | cpu %.3f ms/frame | gpu %.3f ms/frame at %dx%d",
             frame.prims.count, frame.verts.count, frame.overlays.count,
             cpuTotal / Double(repeats) * 1000, gpuTotal / Double(repeats) * 1000, px, px))
