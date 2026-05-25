// LocationManager.swift
import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking:          Bool    = false
    @Published var distanceMiles:       Double  = 0.0
    @Published var elapsedSeconds:      Int     = 0
    @Published var errorMessage:        String? = nil

    private let manager      = CLLocationManager()
    private var lastLocation:  CLLocation?
    private var totalMeters:   Double = 0
    private var timer:         Timer?

    override init() {
        super.init()
        manager.delegate        = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter  = 10
        authorizationStatus     = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    var canTrack: Bool {
        authorizationStatus == .authorizedWhenInUse ||
        authorizationStatus == .authorizedAlways
    }

    func startTrip() {
        guard canTrack else { requestPermission(); return }
        totalMeters    = 0
        distanceMiles  = 0
        elapsedSeconds = 0
        lastLocation   = nil
        isTracking     = true
        errorMessage   = nil
        manager.startUpdatingLocation()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }
    }

    @discardableResult
    func stopTrip() -> Double {
        manager.stopUpdatingLocation()
        timer?.invalidate(); timer = nil
        isTracking   = false
        lastLocation = nil
        return distanceMiles
    }

    var elapsedFormatted: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last,
              newLocation.horizontalAccuracy >= 0,
              newLocation.horizontalAccuracy < 50 else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if let last = self.lastLocation {
                self.totalMeters  += newLocation.distance(from: last)
                self.distanceMiles = self.totalMeters / 1609.344
            }
            self.lastLocation = newLocation
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .denied ||
               manager.authorizationStatus == .restricted {
                self.errorMessage = "Location access denied. Enable it in Settings."
                self.isTracking   = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = "GPS error: \(error.localizedDescription)"
        }
    }
}
