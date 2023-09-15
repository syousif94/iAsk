//
//  Location.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/17/23.
//

import CoreLocation
import AsyncLocationKit

class Location {
    
    static let shared = Location()
    
    enum LocationManagerError: Error {
        case notAllowed
        case unknownAuthorizationStatus
        case locationFailed
    }
    
    var locationManager: AsyncLocationManager? = nil
    
    init() {
        DispatchQueue.main.async {
            self.locationManager = AsyncLocationManager(desiredAccuracy: .threeKilometersAccuracy)
        }
    }
    
    var lastLocation: CLLocation? = nil

    func get() async throws -> CLLocation? {
        if let location = lastLocation {
            return location
        }
        var authorization = self.locationManager?.getAuthorizationStatus()
        switch authorization {
        case .notDetermined:
            authorization =  await self.locationManager?.requestPermission(with: .whenInUsage)
            if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
                fallthrough
            }
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = try? await self.locationManager?.requestLocation() {
                switch location {
                case .didUpdateLocations(let locations):
                    lastLocation = locations.first
                    return lastLocation
                default:
                    throw LocationManagerError.locationFailed
                }
            }
            else {
                throw LocationManagerError.locationFailed
            }
        case .denied, .restricted:
            throw LocationManagerError.notAllowed
        default:
            throw LocationManagerError.notAllowed
        }
        return nil
    }
    
    enum GeocodeError: Error {
        case failed
    }
    
    func geocode(coordinate: CLLocationCoordinate2D) async throws -> CLPlacemark {
        return try await withCheckedThrowingContinuation { continuation in
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            
            geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let placemark = placemarks?.first {
                    continuation.resume(returning: placemark)
                } else {
                    continuation.resume(throwing: GeocodeError.failed)
                }
            }
        }
    }
}
