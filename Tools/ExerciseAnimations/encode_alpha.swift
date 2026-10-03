// Transparent HEVC through AVFoundation, the way the app decodes it.
//
//   encode_alpha <out.mov> <width> <height> <fps> <quality 0-1> <alpha quality 0-1>  < rgba frames
//
// Reads straight-alpha RGBA frames on stdin and writes an HEVC-with-alpha QuickTime clip tagged
// BT.709 primaries and matrix with the sRGB transfer function, so the figure's colours come back
// exactly as rendered. (ffmpeg's VideoToolbox path leaves the clip untagged, and iOS then decodes
// it as BT.709 gamma, lifting the dark greys by several levels.)
import AVFoundation
import VideoToolbox

let args = CommandLine.arguments
guard args.count == 7, let width = Int(args[2]), let height = Int(args[3]), let fps = Int32(args[4]),
      let quality = Double(args[5]), let alphaQuality = Double(args[6])
else {
    FileHandle.standardError.write("usage: encode_alpha out.mov width height fps quality alphaQuality\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
try? FileManager.default.removeItem(at: url)

let colour: [String: Any] = [
    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
]
let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoColorPropertiesKey: colour,
    AVVideoCompressionPropertiesKey: [
        AVVideoQualityKey: quality,
        kVTCompressionPropertyKey_TargetQualityForAlpha as String: alphaQuality,
        kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoAllowFrameReorderingKey: true,
    ] as [String: Any],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
guard writer.startWriting() else { fatalError("\(writer.error!)") }
writer.startSession(atSourceTime: .zero)

let frameBytes = width * height * 4
let stdin = FileHandle.standardInput
var index: Int64 = 0
var pending = Data()
while true {
    while pending.count < frameBytes {
        let chunk = stdin.readData(ofLength: frameBytes - pending.count)
        if chunk.isEmpty { break }
        pending.append(chunk)
    }
    if pending.count < frameBytes { break }
    let frame = pending.prefix(frameBytes)
    pending.removeFirst(frameBytes)

    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { fatalError("no pixel buffer") }
    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    frame.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
        let s = src.bindMemory(to: UInt8.self)
        for y in 0 ..< height {
            let row = base + y * stride
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                let a = UInt16(s[i + 3])
                // RGBA straight -> BGRA premultiplied
                row[x * 4 + 0] = UInt8((UInt16(s[i + 2]) * a + 127) / 255)
                row[x * 4 + 1] = UInt8((UInt16(s[i + 1]) * a + 127) / 255)
                row[x * 4 + 2] = UInt8((UInt16(s[i + 0]) * a + 127) / 255)
                row[x * 4 + 3] = UInt8(a)
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    while !input.isReadyForMoreMediaData { usleep(1000) }
    adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps))
    index += 1
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
if writer.status != .completed { fatalError("\(String(describing: writer.error))") }
