import CryptoKit
import Foundation
import ImageIO
import UIKit
import zlib

enum HePlaceImageRepository {
    nonisolated private static let indexResourceName = "he_places.index"
    nonisolated private static let indexResourceExtension = "json"
    nonisolated private static let defaultImagePayloadName = "he_images.payload"
    nonisolated private static let defaultImagePayloadExt = "bin"
    nonisolated private static let obfuscationKey = "tsugie-ios-seed-v1"
    nonisolated private static let imagePayloadURL: URL? = discoverImagePayloadURL()

    nonisolated static func loadImage(for place: HePlace, maxPixelSize: Int = 1280) -> UIImage? {
        loadImage(imageRef: place.imageRef, maxPixelSize: maxPixelSize)
    }

    nonisolated static func loadImage(imageRef: HePlaceImageRef?, maxPixelSize: Int = 1280) -> UIImage? {
        guard let imageRef,
              imageRef.payloadLength > 0,
              let payloadURL = imagePayloadURL else { return nil }

        guard let fileHandle = try? FileHandle(forReadingFrom: payloadURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        guard let chunk = readChunk(
            with: fileHandle,
            offset: imageRef.payloadOffset,
            length: imageRef.payloadLength
        ) else {
            return nil
        }

        guard let imageData = decodeImageChunk(chunk) else {
            return nil
        }

        return downsampleImage(data: imageData, maxPixelSize: max(256, maxPixelSize))
    }

    private nonisolated static func discoverImagePayloadURL() -> URL? {
        if let indexURL = resolveResourceURL(resourceName: indexResourceName, resourceExtension: indexResourceExtension),
           let indexData = try? Data(contentsOf: indexURL),
           let file = imagePayloadFileName(from: indexData) {
            let fileName = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            if !fileName.isEmpty,
               let url = resolveResourceURL(resourceName: fileName, resourceExtension: ext.isEmpty ? nil : ext) {
                return url
            }
        }

        return resolveResourceURL(resourceName: defaultImagePayloadName, resourceExtension: defaultImagePayloadExt)
    }

    private nonisolated static func imagePayloadFileName(from indexData: Data) -> String? {
        guard let rootObject = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
              let imagePayload = rootObject["image_payload"] as? [String: Any],
              let rawFileName = imagePayload["file"] as? String else {
            return nil
        }

        let trimmed = rawFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func resolveResourceURL(resourceName: String, resourceExtension: String?) -> URL? {
        var seen = Set<ObjectIdentifier>()
        let candidates = [Bundle.main, Bundle(for: _ImageBundleToken.self)] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            let identifier = ObjectIdentifier(bundle)
            if seen.contains(identifier) {
                continue
            }
            seen.insert(identifier)
            if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
                return url
            }
            if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Resources") {
                return url
            }
        }
        return nil
    }

    private nonisolated static func readChunk(with fileHandle: FileHandle, offset: UInt64, length: Int) -> Data? {
        guard length > 0 else {
            return nil
        }

        do {
            try fileHandle.seek(toOffset: offset)
            guard let data = try fileHandle.read(upToCount: length), data.count == length else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private nonisolated static func decodeImageChunk(_ obfuscatedPayload: Data) -> Data? {
        let compressed = xorObfuscate(obfuscatedPayload, keySeed: obfuscationKey)
        return try? zlibDecompressWrapped(compressed)
    }

    private nonisolated static func xorObfuscate(_ data: Data, keySeed: String) -> Data {
        let key = Array(SHA256.hash(data: Data(keySeed.utf8)))
        var output = Data(count: data.count)

        output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                let inPtr = inputBytes.bindMemory(to: UInt8.self).baseAddress
                let outPtr = outputBytes.bindMemory(to: UInt8.self).baseAddress
                guard let inPtr, let outPtr else { return }

                for index in 0..<data.count {
                    let mix = UInt8((index * 131 + 17) & 0xFF)
                    outPtr[index] = inPtr[index] ^ key[index % key.count] ^ mix
                }
            }
        }
        return output
    }

    private nonisolated static func zlibDecompressWrapped(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { rawBuffer -> Data in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw HeImageCodecError.decompressionFailed
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else {
                throw HeImageCodecError.decompressionFailed
            }
            defer { inflateEnd(&stream) }

            let chunkSize = 64 * 1024
            var output = Data()
            var chunk = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let status: Int32 = chunk.withUnsafeMutableBufferPointer { buffer in
                    guard let target = buffer.baseAddress else {
                        return Z_STREAM_ERROR
                    }
                    stream.next_out = target
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: chunk.prefix(produced))
                }

                if status == Z_STREAM_END {
                    return output
                }
                if status != Z_OK {
                    throw HeImageCodecError.decompressionFailed
                }
            }
        }
    }

    private nonisolated static func downsampleImage(data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

private final class _ImageBundleToken {}

private enum HeImageCodecError: Error {
    case decompressionFailed
}
