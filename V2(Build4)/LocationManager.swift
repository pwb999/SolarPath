//  LocationManager.swift
//  MoonPathV1 Watch App
//
//  Robust “fresh fix” location manager for watchOS 11+
//  - Requests a one-shot location AND starts a short burst of updates
//  - Stops updates quickly to save battery
//  - Uses CLLocation.timestamp as “Last fix”
//  - Swift 6 concurrency-safe (no Sendable warnings)
//
import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    //Greenwich Observatory
    @Published var latitude: Double = 51.4769
    @Published var longitude: Double = -0.0005

    @Published var isAuthorized: Bool = false

    /// “Last fix” should be the CLLocation timestamp
    @Published var lastFixTime: Date? = nil

    /// Status line shown in your UI
    @Published var statusText: String = "—"

    /// Cancel any pending “stop after N seconds” task
    private var stopTask: Task<Void, Never>?

    override init() {
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness

        // Ask for permission (system prompt shown if status is .notDetermined)
        manager.requestWhenInUseAuthorization()

        updateAuthFlagAndStatus()

        if isAuthorized {
            forceFreshFix()
        }
    }

    func refreshLocation() {
        updateAuthFlagAndStatus()

        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = "Requesting permission…"
            manager.requestWhenInUseAuthorization()
            return

        case .authorizedAlways, .authorizedWhenInUse:
            forceFreshFix()

        case .denied, .restricted:
            // You cannot re-show the prompt; user must change Settings.
            statusText = "Enable Location Services"
        @unknown default:
            statusText = "Enable Location Services"
        }
    }

    private func updateAuthFlagAndStatus() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            // Keep whatever status we already have (Fixing… / GPS in use)
            if statusText == "—" { statusText = "GPS in use" }

        case .notDetermined:
            isAuthorized = false
            statusText = "Requesting permission…"

        case .denied, .restricted:
            isAuthorized = false
            statusText = "Enable Location Services"

        @unknown default:
            isAuthorized = false
            statusText = "Enable Location Services"
        }
    }

    private func forceFreshFix() {
        statusText = "Fixing…"

        // One-shot request (may return cached)
        manager.requestLocation()

        // Burst updates for a few seconds to encourage a real fix
        manager.startUpdatingLocation()

        stopTask?.cancel()

        // IMPORTANT: run this task on the MainActor so we can touch @Published + manager safely.
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self else { return }

            self.manager.stopUpdatingLocation()
            if self.lastFixTime == nil {
                self.statusText = "No fix"
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthFlagAndStatus()

        if isAuthorized {
            forceFreshFix()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }

        // Ignore stale fixes (older than 2 minutes)
        let age = Date().timeIntervalSince(loc.timestamp)
        if age > 120 {
            statusText = "Stale fix"
            return
        }

        // Ignore very poor accuracy fixes (tune if you like)
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 300 {
            statusText = "Fixing…"
            return
        }

        latitude = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        lastFixTime = loc.timestamp
        statusText = "GPS in use"

        // Good fix achieved — stop to save battery
        manager.stopUpdatingLocation()
        stopTask?.cancel()
        stopTask = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let ns = error as NSError
        statusText = "Location error (\(ns.code))"
        print("Location error: \(ns.domain) \(ns.code) \(ns.localizedDescription)")

        manager.stopUpdatingLocation()
        stopTask?.cancel()
        stopTask = nil
    }
}
