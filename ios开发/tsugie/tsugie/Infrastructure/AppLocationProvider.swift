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
    private static let japanMainlandRegion = (
        latitude: 30.0...46.5,
        longitude: 128.5...154.5
    )
    private static let japanRyukyuRegion = (
        latitude: 20.0...30.0,
        longitude: 122.0...131.0
    )
    private static let japanOgasawaraRegion = (
        latitude: 20.0...30.0,
        longitude: 136.0...154.5
    )

    // 默认启用真实定位；不在日本境内或权限不可用时回退天空树。
    private static let stageDefaultMode: Mode = .live

    private let mode: Mode

    init(mode: Mode = Self.stageDefaultMode) {
        self.mode = mode
    }

    static func isInJapan(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        let inMainland = japanMainlandRegion.latitude.contains(lat) && japanMainlandRegion.longitude.contains(lng)
        let inRyukyu = japanRyukyuRegion.latitude.contains(lat) && japanRyukyuRegion.longitude.contains(lng)
        let inOgasawara = japanOgasawaraRegion.latitude.contains(lat) && japanOgasawaraRegion.longitude.contains(lng)
        return inMainland || inRyukyu || inOgasawara
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
    private var locationContinuations: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []
    private var locationTimeoutTask: Task<Void, Never>?
    private var isRequestingLocation = false
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var authorizationTimeoutTask: Task<Void, Never>?
    private var isRequestingAuthorization = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorizationIfNeeded()
        }
        switch status {
        case .denied, .restricted:
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: .permissionDenied
            )
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            return AppLocationResolution(
                coordinate: fallback,
                fallbackReason: .permissionDenied
            )
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

    private func requestAuthorizationIfNeeded(timeoutSeconds: Double = 6.0) async -> CLAuthorizationStatus {
        let currentStatus = manager.authorizationStatus
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            guard !isRequestingAuthorization else {
                return
            }
            isRequestingAuthorization = true
            manager.requestWhenInUseAuthorization()

            authorizationTimeoutTask?.cancel()
            authorizationTimeoutTask = Task { [weak self] in
                let timeoutNs = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNs)
                await MainActor.run {
                    guard let self else { return }
                    self.completeAuthorizationRequest(with: self.manager.authorizationStatus)
                }
            }
        }
    }

    private func requestLocationOnce(timeoutSeconds: Double = 6.0) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            guard !isRequestingLocation else {
                return
            }
            isRequestingLocation = true

            if isAuthorizedForLocation(manager.authorizationStatus) {
                manager.requestLocation()
            } else {
                completeLocationRequest(with: nil)
                return
            }

            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { [weak self] in
                let timeoutNs = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeoutNs)
                await MainActor.run {
                    self?.completeLocationRequest(with: nil)
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            completeAuthorizationRequest(with: status)
        }

        guard !locationContinuations.isEmpty else {
            return
        }

        if isAuthorizedForLocation(status) {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
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

    private func completeAuthorizationRequest(with status: CLAuthorizationStatus) {
        guard !authorizationContinuations.isEmpty else {
            return
        }
        let pending = authorizationContinuations
        authorizationContinuations.removeAll(keepingCapacity: false)
        isRequestingAuthorization = false
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
        for continuation in pending {
            continuation.resume(returning: status)
        }
    }

    private func completeLocationRequest(with coordinate: CLLocationCoordinate2D?) {
        guard !locationContinuations.isEmpty else {
            return
        }
        let pending = locationContinuations
        locationContinuations.removeAll(keepingCapacity: false)
        isRequestingLocation = false
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        for continuation in pending {
            continuation.resume(returning: coordinate)
        }
    }
}
