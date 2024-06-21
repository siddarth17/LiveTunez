//
//  LocationManager.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import Foundation
import MapKit
@MainActor
class LocationManager : NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var region = MKCoordinateRegion()
    @Published var searchedPlaces: [Place] = []
    @Published var selectedPlace: Place?
    @Published var selectedLatitude: Double?
    @Published var selectedLongitude: Double?
    private let locationManager = CLLocationManager()
    @Published var currentCity: String? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("CityUpdated"), object: nil)
        }
    }
    @Published var currentState: String?
    override init(){
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.delegate = self
    }
    func updateCurrentLocation() {
        guard let location = location else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                return
            }
            guard let placemark = placemarks?.first else { return }
            DispatchQueue.main.async {
                self?.currentCity = placemark.locality
                self?.currentState = placemark.administrativeArea
            }
        }
    }
    func updateCurrentCity(_ city: String) {
        currentCity = city
    }
    func searchPlaces(_ searchText: String) {
        selectedPlace = nil
        selectedLatitude = nil
        selectedLongitude = nil
        updateCurrentCity("")
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = region

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                return
            }

            guard let response = response else {
                print("No search results found.")
                return
            }

            DispatchQueue.main.async {
                self?.searchedPlaces = response.mapItems.map { Place(mapItem: $0) }
                if let firstPlace = self?.searchedPlaces.first {
                    self?.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: firstPlace.latitude, longitude: firstPlace.longitude), latitudinalMeters: 5000, longitudinalMeters: 5000)
                    self?.selectedPlace = firstPlace
                    self?.selectedLatitude = firstPlace.latitude
                    self?.selectedLongitude = firstPlace.longitude
                    self?.updateCurrentCity(firstPlace.name)
                }
            }
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        self.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        updateCurrentLocation()
    }
}
