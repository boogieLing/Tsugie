import CoreLocation
import Foundation

protocol AppLocationProviding {
    func currentCoordinate(fallback: CLLocationCoordinate2D) async -> CLLocationCoordinate2D
}

struct DefaultAppLocationProvider: AppLocationProviding {
    enum Mode {
        case developmentFixed
        case live
    }

    static let developmentFixedCoordinate = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)

    // 开发阶段默认固定天空树桩点；切生产动态定位时改为 `.live`。
    private static let stageDefaultMode: Mode = .developmentFixed

    private let mode: Mode

    init(mode: Mode = Self.stageDefaultMode) {
        self.mode = mode
    }

    func currentCoordinate(fallback: CLLocationCoordinate2D) async -> CLLocationCoordinate2D {
        switch mode {
        case .developmentFixed:
            return Self.developmentFixedCoordinate
        case .live:
            return await LiveCurrentLocationService.shared.currentCoordinate(fallback: fallback)
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

    func currentCoordinate(fallback: CLLocationCoordinate2D) async -> CLLocationCoordinate2D {
        guard CLLocationManager.locationServicesEnabled() else {
            return fallback
        }

        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            return fallback
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return fallback
        }

        if let coordinate = await requestLocationOnce() {
            return coordinate
        }

        return manager.location?.coordinate ?? fallback
    }

    private func requestLocationOnce(timeoutSeconds: Double = 2.0) async -> CLLocationCoordinate2D? {
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
