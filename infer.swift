import AppKit
import CoreImage
import CoreML
import Foundation

let args = CommandLine.arguments
if args.count == 4 && args[1] == "compile" {
    let source = URL(fileURLWithPath: args[2])
    let target = URL(fileURLWithPath: args[3])
    let compiled = try MLModel.compileModel(at: source)
    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    try FileManager.default.moveItem(at: compiled, to: target)
    exit(0)
}
guard args.count == 6, args[1] == "run", let width = Int(args[3]), let height = Int(args[4]) else {
    fatalError("usage: infer run model.mlmodelc width height depth.f32")
}
let modelWidth = 518, modelHeight = 392
let fit = min(Double(modelWidth) / Double(width), Double(modelHeight) / Double(height))
let contentWidth = min(modelWidth, Int((Double(width) * fit * (width < height ? 1.5 : 1)).rounded()))
let contentHeight = min(modelHeight, Int((Double(height) * fit * (width >= height ? 1.5 : 1)).rounded()))
let left = (modelWidth - contentWidth) / 2, bottom = (modelHeight - contentHeight) / 2
let config = MLModelConfiguration(); config.computeUnits = .all
let model = try MLModel(contentsOf: URL(fileURLWithPath: args[2]), configuration: config)
let context = CIContext(options: [.workingColorSpace: NSNull()])
let rect = CGRect(x: 0, y: 0, width: modelWidth, height: modelHeight)
FileManager.default.createFile(atPath: args[5], contents: nil)
let depthFile = try FileHandle(forWritingTo: URL(fileURLWithPath: args[5]))
defer { try? depthFile.close() }

func pixelBuffer(_ w: Int, _ h: Int) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
    precondition(status == kCVReturnSuccess)
    return buffer!
}

func readFrame(_ count: Int) throws -> Data? {
    var data = Data()
    while data.count < count {
        let part = FileHandle.standardInput.readData(ofLength: count - data.count)
        if part.isEmpty {
            if data.isEmpty { return nil }
            throw NSError(domain: "incomplete raw frame", code: 1)
        }
        data.append(part)
    }
    return data
}

let sourceBuffer = pixelBuffer(width, height)
let inputBuffer = pixelBuffer(modelWidth, modelHeight)
let frameBytes = width * height * 4
while let frame = try readFrame(frameBytes) {
    try autoreleasepool {
        CVPixelBufferLockBaseAddress(sourceBuffer, [])
        frame.withUnsafeBytes { bytes in
            let src = bytes.baseAddress!
            let dst = CVPixelBufferGetBaseAddress(sourceBuffer)!
            let stride = CVPixelBufferGetBytesPerRow(sourceBuffer)
            for y in 0..<height {
                memcpy(dst.advanced(by: y * stride), src.advanced(by: y * width * 4), width * 4)
            }
        }
        CVPixelBufferUnlockBaseAddress(sourceBuffer, [])

        let image = CIImage(cvPixelBuffer: sourceBuffer)
            .transformed(by: CGAffineTransform(scaleX: Double(contentWidth) / Double(width),
                                                y: Double(contentHeight) / Double(height)))
            .transformed(by: CGAffineTransform(translationX: Double(left), y: Double(bottom)))
        let background = image.clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: rect)
        let composed = image.composited(over: background).cropped(to: rect)
        context.render(composed, to: inputBuffer, bounds: rect, colorSpace: CGColorSpaceCreateDeviceRGB())
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: inputBuffer)]))
        guard let output = result.featureValue(for: "depth")?.imageBufferValue else { fatalError("missing depth") }
        precondition(CVPixelBufferGetWidth(output) == modelWidth && CVPixelBufferGetHeight(output) == modelHeight)
        precondition(CVPixelBufferGetPixelFormatType(output) == kCVPixelFormatType_OneComponent16Half)
        CVPixelBufferLockBaseAddress(output, .readOnly)
        let base = CVPixelBufferGetBaseAddress(output)!
        let stride = CVPixelBufferGetBytesPerRow(output)
        var floats = [Float](repeating: 0, count: contentWidth * contentHeight)
        for y in 0..<contentHeight {
            let row = base.advanced(by: (y + bottom) * stride).assumingMemoryBound(to: Float16.self)
            for x in 0..<contentWidth { floats[y * contentWidth + x] = Float(row[x + left]) }
        }
        CVPixelBufferUnlockBaseAddress(output, .readOnly)
        try floats.withUnsafeBytes { try depthFile.write(contentsOf: $0) }
    }
}
