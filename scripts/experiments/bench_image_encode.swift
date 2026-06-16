// Micro-benchmark for the pngWrite stage: how long does ImageIO take to encode a
// representative retina capture as PNG vs uncompressed TIFF, and how big are the files?
// Run: swift scripts/experiments/bench_image_encode.swift <input.png> [repeats]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: bench_image_encode.swift <input.png> [repeats]\n".utf8))
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let repeats = args.count >= 3 ? Int(args[2]) ?? 7 : 7

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(inputURL.path)\n".utf8))
    exit(1)
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

func benchEncode(_ name: String, type: UTType, properties: CFDictionary?) {
    var times: [Double] = []
    var bytes = 0
    for index in 0...repeats { // first iteration is warmup
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-encode-\(name)-\(index)")
            .appendingPathExtension(type.preferredFilenameExtension ?? "bin")
        let started = Date()
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("cannot create destination \(name)\n".utf8))
            return
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("finalize failed \(name)\n".utf8))
            return
        }
        let elapsed = Date().timeIntervalSince(started) * 1000
        if index > 0 { times.append(elapsed) }
        bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int).flatMap { $0 } ?? 0
        try? FileManager.default.removeItem(at: url)
    }
    print(String(format: "%@: median %.1fms  size %.1fMB", name, median(times), Double(bytes) / 1_048_576))
}

print("image: \(image.width)x\(image.height)")
benchEncode("png", type: .png, properties: nil)
benchEncode("tiff-none", type: .tiff, properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1]] as CFDictionary)
benchEncode("tiff-lzw", type: .tiff, properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] as CFDictionary)
benchEncode("jpeg-q95", type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
benchEncode("heic-lossless", type: .heic, properties: [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
