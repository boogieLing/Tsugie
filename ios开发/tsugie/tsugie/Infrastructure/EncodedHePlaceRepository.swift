import Compression
import CoreLocation
import CryptoKit
import Foundation
import os
import zlib

enum EncodedHePlaceRepository {
    private struct BucketDecodeResult {
        let items: [EncodedHePlaceItem]
        let cacheHit: Bool
    }

    private final class DecodedBucketLRU {
        private let capacity: Int
        private let lock = NSLock()
        nonisolated(unsafe) private var storage: [String: [EncodedHePlaceItem]] = [:]
        nonisolated(unsafe) private var order: [String] = []

        nonisolated init(capacity: Int) {
            self.capacity = max(1, capacity)
        }

        nonisolated func value(for key: String) -> [EncodedHePlaceItem]? {
            lock.lock()
            defer { lock.unlock() }
            guard let value = storage[key] else {
                return nil
            }
            touch(key)
            return value
        }

        nonisolated func insert(_ value: [EncodedHePlaceItem], for key: String) {
            lock.lock()
            defer { lock.unlock() }
            if storage[key] != nil {
                storage[key] = value
                touch(key)
                return
            }
            storage[key] = value
            order.append(key)
            trimIfNeeded()
        }

        nonisolated private func touch(_ key: String) {
            if let index = order.firstIndex(of: key) {
                order.remove(at: index)
            }
            order.append(key)
        }

        nonisolated private func trimIfNeeded() {
            while order.count > capacity, let oldest = order.first {
                order.removeFirst()
                storage.removeValue(forKey: oldest)
            }
        }
    }

    nonisolated private static let indexResourceName = "he_places.index"
    nonisolated private static let indexResourceExtension = "json"
    nonisolated private static let payloadResourceName = "he_places.payload"
    nonisolated private static let payloadResourceExtension = "bin"
    nonisolated private static let obfuscationKey = "tsugie-ios-seed-v1"
    nonisolated private static let defaultStartupCenter = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)
    nonisolated private static let logger = Logger(subsystem: "com.ushouldknowr0.tsugie", category: "EncodedHePlaceRepository")
    nonisolated private static let decodedBucketCache = DecodedBucketLRU(capacity: 96)

    nonisolated static func load() -> [HePlace] {
        loadNearby(
            center: defaultStartupCenter,
            radiusKm: 20,
            limit: 240
        )
    }

    nonisolated static func loadAll(center: CLLocationCoordinate2D = defaultStartupCenter) -> [HePlace] {
        guard let indexURL = resolveResourceURL(resourceName: indexResourceName, resourceExtension: indexResourceExtension) else {
            debugLog("loadAll abort: index resource missing (\(indexResourceName).\(indexResourceExtension))")
            return []
        }
        guard let indexData = try? Data(contentsOf: indexURL) else {
            debugLog("loadAll abort: cannot read index at \(indexURL.path)")
            return []
        }
        guard let indexEnvelope = try? JSONDecoder().decode(HePlacesSpatialIndexEnvelope.self, from: indexData) else {
            debugLog("loadAll abort: cannot decode index json")
            return []
        }
        guard let payloadURL = resolvePayloadURL(indexEnvelope: indexEnvelope) else {
            debugLog("loadAll abort: payload resource missing")
            return []
        }
        guard let fileHandle = try? FileHandle(forReadingFrom: payloadURL) else {
            debugLog("loadAll abort: cannot open payload at \(payloadURL.path)")
            return []
        }

        defer {
            try? fileHandle.close()
        }

        return loadAll(
            from: indexEnvelope,
            center: center,
            payloadReader: { bucket in
                readChunk(
                    with: fileHandle,
                    offset: bucket.payloadOffset,
                    length: bucket.payloadLength
                )
            }
        )
    }

    nonisolated static func loadNearby(
        center: CLLocationCoordinate2D,
        radiusKm: Double = 20,
        limit: Int = 240
    ) -> [HePlace] {
        guard let indexURL = resolveResourceURL(resourceName: indexResourceName, resourceExtension: indexResourceExtension) else {
            debugLog("loadNearby abort: index resource missing (\(indexResourceName).\(indexResourceExtension))")
            return []
        }
        guard let indexData = try? Data(contentsOf: indexURL) else {
            debugLog("loadNearby abort: cannot read index at \(indexURL.path)")
            return []
        }
        guard let indexEnvelope = try? JSONDecoder().decode(HePlacesSpatialIndexEnvelope.self, from: indexData) else {
            debugLog("loadNearby abort: cannot decode index json")
            return []
        }
        guard let payloadURL = resolvePayloadURL(indexEnvelope: indexEnvelope) else {
            debugLog("loadNearby abort: payload resource missing")
            return []
        }
        guard let fileHandle = try? FileHandle(forReadingFrom: payloadURL) else {
            debugLog("loadNearby abort: cannot open payload at \(payloadURL.path)")
            return []
        }

        debugLog(
            "loadNearby start center=(\(center.latitude),\(center.longitude)) radiusKm=\(radiusKm) limit=\(limit) buckets=\(indexEnvelope.payloadBuckets.count)"
        )

        defer {
            try? fileHandle.close()
        }

        return loadNearby(
            from: indexEnvelope,
            center: center,
            radiusKm: radiusKm,
            limit: limit,
            payloadReader: { bucket in
                readChunk(
                    with: fileHandle,
                    offset: bucket.payloadOffset,
                    length: bucket.payloadLength
                )
            }
        )
    }

    nonisolated static func preheatNeighborhood(
        center: CLLocationCoordinate2D,
        radiusKm: Double = 20,
        limit: Int = 240
    ) {
        guard let indexURL = resolveResourceURL(resourceName: indexResourceName, resourceExtension: indexResourceExtension),
              let indexData = try? Data(contentsOf: indexURL),
              let indexEnvelope = try? JSONDecoder().decode(HePlacesSpatialIndexEnvelope.self, from: indexData),
              let payloadURL = resolvePayloadURL(indexEnvelope: indexEnvelope),
              let fileHandle = try? FileHandle(forReadingFrom: payloadURL) else {
            return
        }

        defer {
            try? fileHandle.close()
        }

        let warmRadiusKm = min(max(radiusKm * 0.88, 8), 45)
        let warmLimit = min(max(limit / 2, 120), 320)
        let stepKm = min(max(warmRadiusKm * 0.62, 4), 18)
        let sampleCenters = preheatSampleCenters(around: center, stepKm: stepKm)

        for sampleCenter in sampleCenters {
            if Task.isCancelled {
                return
            }
            _ = loadNearby(
                from: indexEnvelope,
                center: sampleCenter,
                radiusKm: warmRadiusKm,
                limit: warmLimit,
                payloadReader: { bucket in
                    readChunk(
                        with: fileHandle,
                        offset: bucket.payloadOffset,
                        length: bucket.payloadLength
                    )
                }
            )
        }
        debugLog(
            "preheatNeighborhood done center=(\(center.latitude),\(center.longitude)) warmRadiusKm=\(warmRadiusKm) warmLimit=\(warmLimit) samples=\(sampleCenters.count)"
        )
    }

    nonisolated static func loadNearby(
        from indexData: Data,
        payloadData: Data,
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        limit: Int
    ) -> [HePlace] {
        guard let indexEnvelope = try? JSONDecoder().decode(HePlacesSpatialIndexEnvelope.self, from: indexData) else {
            return []
        }

        return loadNearby(
            from: indexEnvelope,
            center: center,
            radiusKm: radiusKm,
            limit: limit,
            payloadReader: { bucket in
                readChunk(from: payloadData, offset: bucket.payloadOffset, length: bucket.payloadLength)
            }
        )
    }

    nonisolated static func loadAll(
        from indexData: Data,
        payloadData: Data,
        center: CLLocationCoordinate2D
    ) -> [HePlace] {
        guard let indexEnvelope = try? JSONDecoder().decode(HePlacesSpatialIndexEnvelope.self, from: indexData) else {
            return []
        }

        return loadAll(
            from: indexEnvelope,
            center: center,
            payloadReader: { bucket in
                readChunk(from: payloadData, offset: bucket.payloadOffset, length: bucket.payloadLength)
            }
        )
    }

    private nonisolated static func resolvePayloadURL(indexEnvelope: HePlacesSpatialIndexEnvelope) -> URL? {
        if let payloadFile = indexEnvelope.payloadFile?.nonEmpty {
            let filename = (payloadFile as NSString).deletingPathExtension
            let ext = (payloadFile as NSString).pathExtension
            if !filename.isEmpty,
               let url = resolveResourceURL(resourceName: filename, resourceExtension: ext.isEmpty ? nil : ext) {
                return url
            }
        }

        return resolveResourceURL(resourceName: payloadResourceName, resourceExtension: payloadResourceExtension)
    }

    private nonisolated static func loadNearby(
        from indexEnvelope: HePlacesSpatialIndexEnvelope,
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        limit: Int,
        payloadReader: (EncodedPayloadBucketMeta) -> Data?
    ) -> [HePlace] {
        if Task.isCancelled {
            return []
        }
        var items: [EncodedHePlaceItem] = []
        items.reserveCapacity(512)
        var matchedBuckets = 0
        var failedChunkRead = 0
        var decodedFromCandidateBuckets = 0
        var decodedFromExpandedBuckets = 0
        var expandedRounds = 0
        var bucketDecodeCacheHits = 0

        let normalizedRadiusKm = max(radiusKm, 0.5)
        let expansionRadii = [normalizedRadiusKm, min(normalizedRadiusKm * 2, 80), min(normalizedRadiusKm * 4, 140)]
        let initialCandidateKeys = nearbyBucketKeys(
            center: center,
            precision: indexEnvelope.spatialIndex.precision,
            radiusKm: expansionRadii[0]
        )
        var inspectedKeys = Set<String>()

        for (index, searchRadiusKm) in expansionRadii.enumerated() {
            if Task.isCancelled {
                return []
            }
            var keys = nearbyBucketKeys(
                center: center,
                precision: indexEnvelope.spatialIndex.precision,
                radiusKm: searchRadiusKm
            )
            keys.subtract(inspectedKeys)
            if keys.isEmpty {
                continue
            }

            if index > 0 {
                expandedRounds += 1
            }

            inspectedKeys.formUnion(keys)
            for key in keys {
                if Task.isCancelled {
                    return []
                }
                guard let bucket = indexEnvelope.payloadBuckets[key] else {
                    continue
                }
                matchedBuckets += 1
                guard let decodeResult = decodedItems(for: bucket, payloadReader: payloadReader) else {
                    failedChunkRead += 1
                    continue
                }
                if decodeResult.cacheHit {
                    bucketDecodeCacheHits += 1
                }
                let decoded = decodeResult.items
                if index == 0 {
                    decodedFromCandidateBuckets += decoded.count
                } else {
                    decodedFromExpandedBuckets += decoded.count
                }
                items.append(contentsOf: decoded)
            }

            if !items.isEmpty {
                break
            }
        }

        let radiusMeters = max(radiusKm, 0.5) * 1_000
        let cappedLimit = max(1, limit)

        var places = items.compactMap { mapToHePlace($0, center: center) }
        places.sort(by: isCloserAndHigherPriority)
        let precisePlaces = places.filter { !$0.isApproximateCoordinate }
        let approximatePlaces = places.filter { $0.isApproximateCoordinate }
        let preciseInRange = precisePlaces.filter { $0.distanceMeters <= radiusMeters * 1.2 }
        let approximateInRange = approximatePlaces.filter { $0.distanceMeters <= radiusMeters * 1.2 }
        debugLog(
            "loadNearby stats candidateKeys=\(initialCandidateKeys.count) scannedKeys=\(inspectedKeys.count) matchedBuckets=\(matchedBuckets) failedChunkRead=\(failedChunkRead) decodeCacheHits=\(bucketDecodeCacheHits) decodedCandidate=\(decodedFromCandidateBuckets) decodedExpanded=\(decodedFromExpandedBuckets) expandedRounds=\(expandedRounds) mappedPlaces=\(places.count) precise=\(precisePlaces.count) approximate=\(approximatePlaces.count) preciseInRange=\(preciseInRange.count) approximateInRange=\(approximateInRange.count)"
        )

        if preciseInRange.count >= cappedLimit {
            return Array(preciseInRange.prefix(cappedLimit))
        }

        if !preciseInRange.isEmpty {
            return Array(preciseInRange.prefix(cappedLimit))
        }

        if !precisePlaces.isEmpty {
            return Array(precisePlaces.prefix(cappedLimit))
        }

        if !approximateInRange.isEmpty {
            return Array(approximateInRange.prefix(min(cappedLimit, 40)))
        }
        if !approximatePlaces.isEmpty {
            return Array(approximatePlaces.prefix(min(cappedLimit, 40)))
        }
        return []
    }

    private nonisolated static func loadAll(
        from indexEnvelope: HePlacesSpatialIndexEnvelope,
        center: CLLocationCoordinate2D,
        payloadReader: (EncodedPayloadBucketMeta) -> Data?
    ) -> [HePlace] {
        if Task.isCancelled {
            return []
        }
        var items: [EncodedHePlaceItem] = []
        items.reserveCapacity(indexEnvelope.payloadBuckets.count * 4)
        var failedChunkRead = 0
        var bucketDecodeCacheHits = 0

        let orderedBuckets = indexEnvelope.payloadBuckets.values.sorted {
            if $0.payloadOffset == $1.payloadOffset {
                return $0.payloadLength < $1.payloadLength
            }
            return $0.payloadOffset < $1.payloadOffset
        }

        for bucket in orderedBuckets {
            if Task.isCancelled {
                return []
            }
            guard let decodeResult = decodedItems(for: bucket, payloadReader: payloadReader) else {
                failedChunkRead += 1
                continue
            }
            if decodeResult.cacheHit {
                bucketDecodeCacheHits += 1
            }
            let decoded = decodeResult.items
            items.append(contentsOf: decoded)
        }

        var places = items.compactMap { mapToHePlace($0, center: center) }
        places.sort(by: isCloserAndHigherPriority)
        debugLog(
            "loadAll stats buckets=\(orderedBuckets.count) failedChunkRead=\(failedChunkRead) decodeCacheHits=\(bucketDecodeCacheHits) decodedItems=\(items.count) mappedPlaces=\(places.count)"
        )
        return places
    }

    private nonisolated static func decodedItems(
        for bucket: EncodedPayloadBucketMeta,
        payloadReader: (EncodedPayloadBucketMeta) -> Data?
    ) -> BucketDecodeResult? {
        let cacheKey = decodedBucketCacheKey(for: bucket)
        if let cachedItems = decodedBucketCache.value(for: cacheKey) {
            return BucketDecodeResult(items: cachedItems, cacheHit: true)
        }

        guard let payload = payloadReader(bucket) else {
            return nil
        }
        let decodedItems: [EncodedHePlaceItem] = autoreleasepool {
            decodeItems(payloadChunk: payload)
        }
        decodedBucketCache.insert(decodedItems, for: cacheKey)
        return BucketDecodeResult(items: decodedItems, cacheHit: false)
    }

    private nonisolated static func decodedBucketCacheKey(for bucket: EncodedPayloadBucketMeta) -> String {
        "\(bucket.payloadOffset):\(bucket.payloadLength):\(bucket.payloadSHA256 ?? "-")"
    }

    private nonisolated static func preheatSampleCenters(
        around center: CLLocationCoordinate2D,
        stepKm: Double
    ) -> [CLLocationCoordinate2D] {
        let clampedStepKm = max(1, stepKm)
        let diagonal = clampedStepKm * 0.72
        let vectors: [(Double, Double)] = [
            (clampedStepKm, 0),
            (-clampedStepKm, 0),
            (0, clampedStepKm),
            (0, -clampedStepKm),
            (diagonal, diagonal),
            (diagonal, -diagonal),
            (-diagonal, diagonal),
            (-diagonal, -diagonal)
        ]

        return vectors.map { northKm, eastKm in
            shiftedCoordinate(center: center, northKm: northKm, eastKm: eastKm)
        }
    }

    private nonisolated static func shiftedCoordinate(
        center: CLLocationCoordinate2D,
        northKm: Double,
        eastKm: Double
    ) -> CLLocationCoordinate2D {
        let latitude = clampLatitude(center.latitude + (northKm / 110.574))
        let metersPerLongitudeDegree = max(cos(center.latitude * .pi / 180) * 111.320, 0.1)
        let longitude = wrapLongitude(center.longitude + (eastKm / metersPerLongitudeDegree))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private nonisolated static func resolveResourceURL(resourceName: String, resourceExtension: String?) -> URL? {
        var seen = Set<ObjectIdentifier>()
        let candidates = [Bundle.main, Bundle(for: _BundleToken.self)] + Bundle.allBundles + Bundle.allFrameworks
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

    private nonisolated static func debugLog(_ message: String) {
#if DEBUG
        print("[EncodedHePlaceRepository] \(message)")
#endif
        logger.info("\(message, privacy: .public)")
    }

    private nonisolated static func decodeItems(payloadChunk: Data) -> [EncodedHePlaceItem] {
        let payloadCandidates = decodePayloadCandidates(payloadChunk)
        for payloadData in payloadCandidates {
            if let items = decodeItemsFromJSONPayload(payloadData) {
                return items
            }
        }
        return []
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

    private nonisolated static func readChunk(from payloadData: Data, offset: UInt64, length: Int) -> Data? {
        guard length > 0,
              offset <= UInt64(Int.max),
              let start = Int(exactly: offset) else {
            return nil
        }

        let end = start + length
        guard start >= 0, end <= payloadData.count else {
            return nil
        }
        return payloadData.subdata(in: start..<end)
    }

    private nonisolated static func nearbyBucketKeys(
        center: CLLocationCoordinate2D,
        precision: Int,
        radiusKm: Double
    ) -> Set<String> {
        let normalizedPrecision = max(1, min(8, precision))
        let centerHash = GeohashCodec.encode(center, precision: normalizedPrecision)
        guard let bounds = GeohashCodec.boundingBox(of: centerHash) else {
            return [centerHash]
        }

        let radiusMeters = max(radiusKm, 0.5) * 1_000
        let latStep = max(bounds.maxLat - bounds.minLat, 0.00001)
        let lngStep = max(bounds.maxLng - bounds.minLng, 0.00001)

        let latMeters = max(latStep * 111_320, 10)
        let lngMeters = max(lngStep * 111_320 * max(cos(center.latitude * .pi / 180), 0.1), 10)

        let latCells = min(32, max(1, Int(ceil(radiusMeters / latMeters))))
        let lngCells = min(32, max(1, Int(ceil(radiusMeters / lngMeters))))

        var keys: Set<String> = [centerHash]
        for latOffset in (-latCells...latCells) {
            for lngOffset in (-lngCells...lngCells) {
                let sampleLat = clampLatitude(center.latitude + (Double(latOffset) * latStep))
                let sampleLng = wrapLongitude(center.longitude + (Double(lngOffset) * lngStep))
                let sample = CLLocationCoordinate2D(latitude: sampleLat, longitude: sampleLng)
                keys.insert(GeohashCodec.encode(sample, precision: normalizedPrecision))
            }
        }
        return keys
    }

    private nonisolated static func clampLatitude(_ lat: Double) -> Double {
        max(-89.999_999, min(89.999_999, lat))
    }

    private nonisolated static func wrapLongitude(_ lng: Double) -> Double {
        var value = lng
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }

    private nonisolated static func decodePayloadCandidates(_ obfuscatedPayload: Data) -> [Data] {
        let compressed = xorObfuscate(obfuscatedPayload, keySeed: obfuscationKey)
        var candidates: [Data] = []

        // 优先尝试标准 zlib 包裹流（与脚本默认压缩兼容）。
        if let payload = try? zlibDecompressWrapped(compressed) {
            candidates.append(payload)
        }

        // 兼容历史 raw deflate 形式。
        if let payload = try? zlibDecompressRaw(compressed),
           !candidates.contains(payload) {
            candidates.append(payload)
        }

        return candidates
    }

    private nonisolated static func decodeItemsFromJSONPayload(_ payloadData: Data) -> [EncodedHePlaceItem]? {
        if let items = try? JSONDecoder().decode([EncodedHePlaceItem].self, from: payloadData) {
            return items
        }

        // 容错模式：单条坏数据不影响整个 bucket。
        guard let array = try? JSONSerialization.jsonObject(with: payloadData) as? [Any] else {
            return nil
        }

        var recovered: [EncodedHePlaceItem] = []
        recovered.reserveCapacity(array.count)
        for element in array {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let item = try? JSONDecoder().decode(EncodedHePlaceItem.self, from: elementData) else {
                continue
            }
            recovered.append(item)
        }

        return recovered.isEmpty ? nil : recovered
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

    private nonisolated static func zlibDecompressRaw(_ data: Data) throws -> Data {
        var outputSize = max(data.count * 4, 1024)
        let maxOutputSize = 64 * 1024 * 1024

        while outputSize <= maxOutputSize {
            var decompressed = [UInt8](repeating: 0, count: outputSize)
            let decodedCount = decompressed.withUnsafeMutableBufferPointer { dstBuffer -> Int in
                guard let dst = dstBuffer.baseAddress else {
                    return 0
                }
                let dstCount = dstBuffer.count
                return data.withUnsafeBytes { rawBuffer -> Int in
                    guard let src = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_decode_buffer(
                        dst,
                        dstCount,
                        src,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            if decodedCount > 0 {
                return Data(decompressed.prefix(decodedCount))
            }
            outputSize *= 2
        }

        throw SeedCodecError.decompressionFailed
    }

    private nonisolated static func zlibDecompressWrapped(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { rawBuffer -> Data in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw SeedCodecError.decompressionFailed
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: source)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else {
                throw SeedCodecError.decompressionFailed
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
                    throw SeedCodecError.decompressionFailed
                }
            }
        }
    }

    private nonisolated static func mapToHePlace(_ item: EncodedHePlaceItem, center: CLLocationCoordinate2D) -> HePlace? {
        guard let coordinate = item.record.coordinate else {
            return nil
        }

        let name = cleanDisplayText(item.record.eventName)
            ?? cleanDisplayText(item.record.venueName)
            ?? "Unknown"
        let type = HeType(rawValue: item.category) ?? .other
        let placeID = UUID(uuidString: item.iosPlaceID) ?? UUID()
        let startAt = SeedDateParser.startAt(item)
        let endAt = SeedDateParser.endAt(item, startAt: startAt)
        let mapSpot = cleanDisplayText(item.record.venueName)
            ?? cleanDisplayText(item.record.venueAddress)
            ?? cleanDisplayText(item.record.city)
            ?? cleanDisplayText(item.record.prefecture)
            ?? name
        let hint = cleanDisplayText(item.hint) ?? "\(mapSpot)・おすすめ"
        let detail = makeDetailDescription(item: item)
        let sourceURLs = makeSourceURLs(item: item)
        let imageRef = makeImageRef(item: item)
        let openHours = makeOpenHours(start: item.normalizedStartTime, end: item.normalizedEndTime)
        let realDistance = center.distance(to: coordinate)

        return HePlace(
            id: placeID,
            name: name,
            heType: type,
            coordinate: coordinate,
            geoSource: item.record.geoSource?.nonEmpty ?? "unknown",
            startAt: startAt,
            endAt: endAt,
            distanceMeters: realDistance,
            scaleScore: item.scaleScore ?? 70,
            hint: hint,
            openHours: openHours,
            mapSpot: mapSpot,
            detailDescription: detail,
            oneLiner: cleanDisplayText(item.contentOneLiner),
            detailDescriptionZH: cleanDisplayText(item.contentDescriptionZH),
            oneLinerZH: cleanDisplayText(item.contentOneLinerZH),
            detailDescriptionEN: cleanDisplayText(item.contentDescriptionEN),
            oneLinerEN: cleanDisplayText(item.contentOneLinerEN),
            launchCount: cleanDisplayText(item.record.launchCount),
            launchScale: cleanDisplayText(item.record.launchScale),
            paidSeat: cleanDisplayText(item.record.paidSeat),
            accessText: cleanDisplayText(item.record.accessText),
            parkingText: cleanDisplayText(item.record.parkingText),
            trafficControlText: cleanDisplayText(item.record.trafficControlText),
            organizer: cleanDisplayText(item.record.organizer),
            festivalType: cleanDisplayText(item.record.festivalType),
            admissionFee: cleanDisplayText(item.record.admissionFee),
            expectedVisitors: cleanDisplayText(item.record.expectedVisitors),
            sourceURLs: sourceURLs,
            descriptionSourceURL: cleanDisplayText(item.contentDescriptionSourceURL) ?? sourceURLs.first,
            imageSourceURL: cleanDisplayText(item.contentImageSourceURL),
            imageRef: imageRef,
            imageTag: type == .hanabi ? "花火" : (type == .matsuri ? "祭典" : "へ"),
            imageHint: cleanDisplayText(item.record.eventName) ?? name,
            heatScore: item.heatScore ?? 72,
            surpriseScore: item.surpriseScore ?? 66
        )
    }

    private nonisolated static func isCloserAndHigherPriority(_ lhs: HePlace, _ rhs: HePlace) -> Bool {
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        if lhs.scaleScore != rhs.scaleScore {
            return lhs.scaleScore > rhs.scaleScore
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private nonisolated static func makeOpenHours(start: String?, end: String?) -> String? {
        let startText = start?.nonEmpty
        let endText = end?.nonEmpty
        if let startText, let endText {
            return "Open \(startText) - \(endText)"
        }
        if let startText {
            return "Start \(startText)"
        }
        return nil
    }

    private nonisolated static func makeDetailDescription(item: EncodedHePlaceItem) -> String {
        if let polished = cleanDisplayText(item.contentDescription) {
            return polished
        }

        let record = item.record
        let candidates = [
            record.eventName,
            record.venueName,
            record.accessText,
            record.rainoutPolicy,
            record.contact,
            record.sourceNotes,
        ]
        let kept = candidates.compactMap(cleanDisplayText)
        return kept.isEmpty ? "詳細情報準備中" : kept.joined(separator: " / ")
    }

    private nonisolated static func makeSourceURLs(item: EncodedHePlaceItem) -> [String] {
        let candidates = item.contentSourceURLs ?? item.record.sourceURLs ?? []
        var output: [String] = []
        output.reserveCapacity(candidates.count)
        var seen = Set<String>()
        for value in candidates {
            guard let text = cleanDisplayText(value) else { continue }
            if seen.insert(text).inserted {
                output.append(text)
            }
        }
        return output
    }

    private nonisolated static func makeImageRef(item: EncodedHePlaceItem) -> HePlaceImageRef? {
        guard let payloadOffset = item.imagePayloadOffset,
              let payloadLength = item.imagePayloadLength,
              payloadLength > 0 else {
            return nil
        }
        return HePlaceImageRef(
            payloadOffset: payloadOffset,
            payloadLength: payloadLength,
            payloadSHA256: item.imagePayloadSHA256?.nonEmpty
        )
    }

    private nonisolated static func cleanDisplayText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        // Drop mojibake replacement characters to avoid broken text in UI.
        guard !trimmed.contains("\u{FFFD}") else {
            return nil
        }
        return trimmed
    }
}

nonisolated private enum SeedCodecError: Error {
    case decompressionFailed
}

private final class _BundleToken {}

nonisolated private struct HePlacesSpatialIndexEnvelope: Decodable {
    let version: Int
    let spatialIndex: SpatialIndexMeta
    let payloadFile: String?
    let payloadSHA256: String?
    let payloadSizeBytes: Int?
    let payloadBuckets: [String: EncodedPayloadBucketMeta]

    enum CodingKeys: String, CodingKey {
        case version
        case spatialIndex = "spatial_index"
        case payloadFile = "payload_file"
        case payloadSHA256 = "payload_sha256"
        case payloadSizeBytes = "payload_size_bytes"
        case payloadBuckets = "payload_buckets"
    }
}

nonisolated private struct SpatialIndexMeta: Decodable {
    let scheme: String
    let precision: Int
    let bucketCount: Int

    enum CodingKeys: String, CodingKey {
        case scheme
        case precision
        case bucketCount = "bucket_count"
    }
}

nonisolated private struct EncodedPayloadBucketMeta: Decodable {
    let recordCount: Int?
    let payloadSHA256: String?
    let payloadOffset: UInt64
    let payloadLength: Int

    enum CodingKeys: String, CodingKey {
        case recordCount = "record_count"
        case payloadSHA256 = "payload_sha256"
        case payloadOffset = "payload_offset"
        case payloadLength = "payload_length"
    }
}

nonisolated private struct EncodedHePlaceItem: Decodable {
    let category: String
    let iosPlaceID: String
    let distanceMeters: Double?
    let scaleScore: Int?
    let heatScore: Int?
    let surpriseScore: Int?
    let hint: String?
    let normalizedStartDate: String?
    let normalizedEndDate: String?
    let normalizedStartTime: String?
    let normalizedEndTime: String?
    let geohash: String?
    let contentDescription: String?
    let contentOneLiner: String?
    let contentDescriptionZH: String?
    let contentOneLinerZH: String?
    let contentDescriptionEN: String?
    let contentOneLinerEN: String?
    let contentSourceURLs: [String]?
    let contentDescriptionSourceURL: String?
    let contentImageSourceURL: String?
    let imagePayloadOffset: UInt64?
    let imagePayloadLength: Int?
    let imagePayloadSHA256: String?
    let record: FusedEventRecord

    enum CodingKeys: String, CodingKey {
        case category
        case iosPlaceID = "ios_place_id"
        case distanceMeters = "distance_meters"
        case scaleScore = "scale_score"
        case heatScore = "heat_score"
        case surpriseScore = "surprise_score"
        case hint
        case normalizedStartDate = "normalized_start_date"
        case normalizedEndDate = "normalized_end_date"
        case normalizedStartTime = "normalized_start_time"
        case normalizedEndTime = "normalized_end_time"
        case geohash
        case contentDescription = "content_description"
        case contentOneLiner = "content_one_liner"
        case contentDescriptionZH = "content_description_zh"
        case contentOneLinerZH = "content_one_liner_zh"
        case contentDescriptionEN = "content_description_en"
        case contentOneLinerEN = "content_one_liner_en"
        case contentSourceURLs = "content_source_urls"
        case contentDescriptionSourceURL = "content_description_source_url"
        case contentImageSourceURL = "content_image_source_url"
        case imagePayloadOffset = "image_payload_offset"
        case imagePayloadLength = "image_payload_length"
        case imagePayloadSHA256 = "image_payload_sha256"
        case record
    }
}

nonisolated private struct FusedEventRecord: Decodable {
    let eventName: String?
    let venueName: String?
    let venueAddress: String?
    let prefecture: String?
    let city: String?
    let lat: Double?
    let lng: Double?
    let launchCount: String?
    let launchScale: String?
    let paidSeat: String?
    let organizer: String?
    let festivalType: String?
    let admissionFee: String?
    let expectedVisitors: String?
    let accessText: String?
    let rainoutPolicy: String?
    let parkingText: String?
    let trafficControlText: String?
    let contact: String?
    let sourceNotes: String?
    let geoSource: String?
    let sourceURLs: [String]?

    enum CodingKeys: String, CodingKey {
        case eventName = "event_name"
        case venueName = "venue_name"
        case venueAddress = "venue_address"
        case prefecture
        case city
        case lat
        case lng
        case launchCount = "launch_count"
        case launchScale = "launch_scale"
        case paidSeat = "paid_seat"
        case organizer
        case festivalType = "festival_type"
        case admissionFee = "admission_fee"
        case expectedVisitors = "expected_visitors"
        case accessText = "access_text"
        case rainoutPolicy = "rainout_policy"
        case parkingText = "parking_text"
        case trafficControlText = "traffic_control_text"
        case contact
        case sourceNotes = "source_notes"
        case geoSource = "geo_source"
        case sourceURLs = "source_urls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventName = Self.decodeString(container, key: .eventName)
        venueName = Self.decodeString(container, key: .venueName)
        venueAddress = Self.decodeString(container, key: .venueAddress)
        prefecture = Self.decodeString(container, key: .prefecture)
        city = Self.decodeString(container, key: .city)
        lat = Self.decodeDouble(container, key: .lat)
        lng = Self.decodeDouble(container, key: .lng)
        launchCount = Self.decodeString(container, key: .launchCount)
        launchScale = Self.decodeString(container, key: .launchScale)
        paidSeat = Self.decodeString(container, key: .paidSeat)
        organizer = Self.decodeString(container, key: .organizer)
        festivalType = Self.decodeString(container, key: .festivalType)
        admissionFee = Self.decodeString(container, key: .admissionFee)
        expectedVisitors = Self.decodeString(container, key: .expectedVisitors)
        accessText = Self.decodeString(container, key: .accessText)
        rainoutPolicy = Self.decodeString(container, key: .rainoutPolicy)
        parkingText = Self.decodeString(container, key: .parkingText)
        trafficControlText = Self.decodeString(container, key: .trafficControlText)
        contact = Self.decodeString(container, key: .contact)
        sourceNotes = Self.decodeString(container, key: .sourceNotes)
        geoSource = Self.decodeString(container, key: .geoSource)
        sourceURLs = Self.decodeStringList(container, key: .sourceURLs)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng, (-90...90).contains(lat), (-180...180).contains(lng) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private nonisolated static func decodeString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private nonisolated static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: key),
           let value = Double(text) {
            return value
        }
        return nil
    }

    private nonisolated static func decodeStringList(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [String]? {
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key),
           let text = value.nonEmpty {
            if text.contains("|") {
                return text.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            return [text]
        }
        return nil
    }
}

nonisolated private enum SeedDateParser {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    nonisolated static func startAt(_ item: EncodedHePlaceItem) -> Date? {
        guard let day = item.normalizedStartDate?.nonEmpty else {
            return nil
        }
        let time = item.normalizedStartTime?.nonEmpty ?? "18:00"
        return dateTimeFormatter.date(from: "\(day) \(time)")
    }

    nonisolated static func endAt(_ item: EncodedHePlaceItem, startAt: Date?) -> Date? {
        if let day = item.normalizedEndDate?.nonEmpty {
            let time = item.normalizedEndTime?.nonEmpty ?? "21:00"
            if let end = dateTimeFormatter.date(from: "\(day) \(time)") {
                if let startAt, end < startAt {
                    return calendar.date(byAdding: .hour, value: 2, to: startAt)
                }
                return end
            }
        }

        if let startAt {
            return calendar.date(byAdding: .hour, value: 2, to: startAt)
        }
        return nil
    }
}

nonisolated private enum GeohashCodec {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let bits: [Int] = [16, 8, 4, 2, 1]
    private static let decodeMap: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, ch) in alphabet.enumerated() {
            map[ch] = index
        }
        return map
    }()

    nonisolated static func encode(_ coordinate: CLLocationCoordinate2D, precision: Int) -> String {
        var latRange = (-90.0, 90.0)
        var lngRange = (-180.0, 180.0)
        var isLng = true
        var bitIndex = 0
        var current = 0
        var out: [Character] = []

        while out.count < precision {
            if isLng {
                let mid = (lngRange.0 + lngRange.1) / 2
                if coordinate.longitude >= mid {
                    current |= bits[bitIndex]
                    lngRange.0 = mid
                } else {
                    lngRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if coordinate.latitude >= mid {
                    current |= bits[bitIndex]
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }

            isLng.toggle()
            if bitIndex < 4 {
                bitIndex += 1
            } else {
                out.append(alphabet[current])
                bitIndex = 0
                current = 0
            }
        }

        return String(out)
    }

    nonisolated static func boundingBox(of geohash: String) -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? {
        var latRange = (-90.0, 90.0)
        var lngRange = (-180.0, 180.0)
        var isLng = true

        for ch in geohash {
            guard let decoded = decodeMap[ch] else {
                return nil
            }
            for bit in bits {
                let isSet = (decoded & bit) != 0
                if isLng {
                    let mid = (lngRange.0 + lngRange.1) / 2
                    if isSet {
                        lngRange.0 = mid
                    } else {
                        lngRange.1 = mid
                    }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if isSet {
                        latRange.0 = mid
                    } else {
                        latRange.1 = mid
                    }
                }
                isLng.toggle()
            }
        }

        return (latRange.0, latRange.1, lngRange.0, lngRange.1)
    }
}

nonisolated private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let lhs = CLLocation(latitude: latitude, longitude: longitude)
        let rhs = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return lhs.distance(from: rhs)
    }
}

nonisolated private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
