import Compression
import CoreLocation
import CryptoKit
import Foundation
import XCTest
@testable import tsugie

final class EncodedHePlaceRepositoryTests: XCTestCase {
    private let keySeed = "tsugie-ios-seed-v1"
    private let center = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)

    func testLoadNearbyFiltersByRadius() throws {
        let payloadJSON = """
        [
          {
            "category": "hanabi",
            "ios_place_id": "11111111-1111-1111-1111-111111111111",
            "scale_score": 88,
            "record": {
              "event_name": "Near Event",
              "lat": 35.711,
              "lng": 139.812
            }
          },
          {
            "category": "matsuri",
            "ios_place_id": "22222222-2222-2222-2222-222222222222",
            "scale_score": 95,
            "record": {
              "event_name": "Far Event",
              "lat": -33.86,
              "lng": 151.20
            }
          }
        ]
        """

        let (indexData, payloadData) = try makeSpatialPackage(payloadJSON: payloadJSON, bucketKey: "x", precision: 1)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 30,
            limit: 50
        )

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "Near Event")
    }

    func testLoadNearbyRespectsLimit() throws {
        let payloadJSON = """
        [
          {
            "category": "hanabi",
            "ios_place_id": "33333333-3333-3333-3333-333333333333",
            "scale_score": 70,
            "record": {
              "event_name": "Near A",
              "lat": 35.7105,
              "lng": 139.8108
            }
          },
          {
            "category": "hanabi",
            "ios_place_id": "44444444-4444-4444-4444-444444444444",
            "scale_score": 99,
            "record": {
              "event_name": "Near B",
              "lat": 35.7102,
              "lng": 139.8107
            }
          }
        ]
        """

        let (indexData, payloadData) = try makeSpatialPackage(payloadJSON: payloadJSON, bucketKey: "x", precision: 1)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 30,
            limit: 1
        )

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "Near B")
    }

    func testLoadNearbyPrefersPreciseCoordinatesOverPrefCenterFallback() throws {
        let payloadJSON = """
        [
          {
            "category": "hanabi",
            "ios_place_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "scale_score": 90,
            "record": {
              "event_name": "Approximate Event",
              "geo_source": "pref_center_fallback",
              "lat": 35.71010,
              "lng": 139.81070
            }
          },
          {
            "category": "hanabi",
            "ios_place_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            "scale_score": 80,
            "record": {
              "event_name": "Precise Event",
              "geo_source": "network_geocode",
              "lat": 35.71040,
              "lng": 139.81100
            }
          }
        ]
        """

        let (indexData, payloadData) = try makeSpatialPackage(payloadJSON: payloadJSON, bucketKey: "x", precision: 1)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 30,
            limit: 1
        )

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "Precise Event")
        XCTAssertEqual(places.first?.geoSource, "network_geocode")
    }

    func testLoadNearbyDoesNotBackfillApproximateWhenPreciseExists() throws {
        let payloadJSON = """
        [
          {
            "category": "hanabi",
            "ios_place_id": "0f0f0f0f-0000-4000-8000-000000000001",
            "scale_score": 90,
            "record": {
              "event_name": "Approximate Event",
              "geo_source": "pref_center_fallback",
              "lat": 35.71010,
              "lng": 139.81070
            }
          },
          {
            "category": "hanabi",
            "ios_place_id": "0f0f0f0f-0000-4000-8000-000000000002",
            "scale_score": 80,
            "record": {
              "event_name": "Precise Event",
              "geo_source": "source_exact",
              "lat": 35.71040,
              "lng": 139.81100
            }
          }
        ]
        """

        let (indexData, payloadData) = try makeSpatialPackage(payloadJSON: payloadJSON, bucketKey: "x", precision: 1)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 20,
            limit: 10
        )

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "Precise Event")
    }

    func testLoadNearbyDoesNotFallbackToFullScanWhenSpatialBucketMisses() throws {
        let payloadJSON = """
        [
          {
            "category": "hanabi",
            "ios_place_id": "99999999-9999-4999-8999-999999999999",
            "scale_score": 88,
            "record": {
              "event_name": "Out Of Range Bucket Event",
              "lat": 35.711,
              "lng": 139.812
            }
          }
        ]
        """

        let (indexData, payloadData) = try makeSpatialPackage(payloadJSON: payloadJSON, bucketKey: "zzzzz", precision: 5)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 1,
            limit: 50
        )

        XCTAssertTrue(places.isEmpty)
    }

    func testLoadNearbyFromInvalidIndexReturnsEmpty() {
        let bad = Data("{\"version\":3,\"payload_buckets\":{}}".utf8)
        let places = EncodedHePlaceRepository.loadNearby(
            from: bad,
            payloadData: Data(),
            center: center,
            radiusKm: 30,
            limit: 100
        )
        XCTAssertTrue(places.isEmpty)
    }

    func testLoadNearbyFromGeneratedPayloadFilesAroundSkytree() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Infrastructure
            .deletingLastPathComponent()   // tsugieTests
            .deletingLastPathComponent()   // tsugie
        let indexURL = root.appendingPathComponent("tsugie/Resources/he_places.index.json")
        let payloadURL = root.appendingPathComponent("tsugie/Resources/he_places.payload.bin")

        let indexData = try Data(contentsOf: indexURL)
        let payloadData = try Data(contentsOf: payloadURL)
        let places = EncodedHePlaceRepository.loadNearby(
            from: indexData,
            payloadData: payloadData,
            center: center,
            radiusKm: 30,
            limit: 700
        )

        XCTAssertGreaterThan(places.count, 50)
    }

    private func makeSpatialPackage(
        payloadJSON: String,
        bucketKey: String,
        precision: Int
    ) throws -> (indexData: Data, payloadData: Data) {
        let entryCount = try countJSONArrayEntries(payloadJSON)
        let payloadChunk = try encodePayload(payloadJSON: payloadJSON)
        let indexDoc: [String: Any] = [
            "version": 3,
            "spatial_index": [
                "scheme": "geohash_prefix_v1",
                "precision": precision,
                "bucket_count": 1,
            ],
            "payload_file": "he_places.payload.bin",
            "payload_buckets": [
                bucketKey: [
                    "record_count": entryCount,
                    "payload_offset": 0,
                    "payload_length": payloadChunk.count,
                ],
            ],
        ]

        let indexData = try JSONSerialization.data(withJSONObject: indexDoc, options: [])
        return (indexData: indexData, payloadData: payloadChunk)
    }

    private func encodePayload(payloadJSON: String) throws -> Data {
        let raw = Data(payloadJSON.utf8)
        let compressed = try zlibCompress(raw)
        return xorObfuscate(compressed, keySeed: keySeed)
    }

    private func countJSONArrayEntries(_ payloadJSON: String) throws -> Int {
        guard let data = payloadJSON.data(using: .utf8),
              let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw NSError(domain: "EncodedHePlaceRepositoryTests", code: 2)
        }
        return array.count
    }

    private func xorObfuscate(_ data: Data, keySeed: String) -> Data {
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

    private func zlibCompress(_ data: Data) throws -> Data {
        var outputSize = max(data.count * 2, 1024)
        let maxOutputSize = 64 * 1024 * 1024

        while outputSize <= maxOutputSize {
            var compressed = [UInt8](repeating: 0, count: outputSize)
            let encodedCount = compressed.withUnsafeMutableBufferPointer { dstBuffer -> Int in
                guard let dst = dstBuffer.baseAddress else {
                    return 0
                }
                let dstCount = dstBuffer.count
                return data.withUnsafeBytes { srcBuffer -> Int in
                    guard let src = srcBuffer.bindMemory(to: UInt8.self).baseAddress else {
                        return 0
                    }
                    return compression_encode_buffer(
                        dst,
                        dstCount,
                        src,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            if encodedCount > 0 {
                return Data(compressed.prefix(encodedCount))
            }
            outputSize *= 2
        }

        throw NSError(domain: "EncodedHePlaceRepositoryTests", code: 1)
    }
}
