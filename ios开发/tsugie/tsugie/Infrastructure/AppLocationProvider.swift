import CoreLocation
import Foundation

enum AppLocationFallbackReason: String, Hashable {
    case permissionDenied
    case outsideJapan
}

struct AppLocationResolution {
    let coordinate: CLLocationCoordinate2D
    let fallbackReason: AppLocationFallbackReason?
}

protocol AppLocationProviding {
    func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution
}

extension AppLocationProviding {
    func currentCoordinate(fallback: CLLocationCoordinate2D) async -> CLLocationCoordinate2D {
        await resolveCurrentLocation(fallback: fallback).coordinate
    }
}

struct DefaultAppLocationProvider: AppLocationProviding {
    enum Mode {
        case developmentFixed
        case live
    }

    static let developmentFixedCoordinate = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)
    private static let japanLatitudeRange: ClosedRange<CLLocationDegrees> = 20.0...46.5
    private static let japanLongitudeRange: ClosedRange<CLLocationDegrees> = 122.0...154.5

    // 默认启用真实定位；不在日本境内或权限不可用时回退天空树。
    private static let stageDefaultMode: Mode = .live

    private let mode: Mode

    init(mode: Mode = Self.stageDefaultMode) {
        self.mode = mode
    }

    static func isInJapan(_ coordinate: CLLocationCoordinate2D) -> Bool {
        japanLatitudeRange.contains(coordinate.latitude) && japanLongitudeRange.contains(coordinate.longitude)
    }

    func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution {
        switch mode {
        case .developmentFixed:
            return AppLocationResolution(
                coordinate: Self.developmentFixedCoordinate,
                fallbackReason: nil
            )
        case .live:
            return await LiveCurrentLocationService.shared.resolveCurrentLocation(fallback: fallback)
        }
    }
}

@MainActor
private final class LiveCurrentLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LiveCurrentLocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution {
        guard CLLocationManager.locationServicesEnabled() else {
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: .permissionDenied
            )
        }

        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: .permissionDenied
            )
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: nil
            )
        }

        let resolvedCoordinate = await requestLocationOnce() ?? manager.location?.coordinate

        guard let resolvedCoordinate else {
            let fallbackReason: AppLocationFallbackReason? =
                manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
                ? .permissionDenied
                : nil
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: fallbackReason
            )
        }

        guard DefaultAppLocationProvider.isInJapan(resolvedCoordinate) else {
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: .outsideJapan
            )
        }

        return AppLocationResolution(coordinate: resolvedCoordinate, fallbackReason: nil)
    }

    private func requestLocationOnce(timeoutSeconds: Double = 6.0) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            if isAuthorizedForLocation(manager.authorizationStatus) {
                manager.requestLocation()
            }

            Task { [weak self] in
                let timeoutNs = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNs)
                self?.completeLocationRequest(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else {
            return
        }

        if isAuthorizedForLocation(manager.authorizationStatus) {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            completeLocationRequest(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completeLocationRequest(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            // Keep waiting until timeout because CoreLocation may report temporary unknown before a valid fix.
            return
        }
        completeLocationRequest(with: nil)
    }

    private func isAuthorizedForLocation(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func completeLocationRequest(with coordinate: CLLocationCoordinate2D?) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume(returning: coordinate)
    }
}
