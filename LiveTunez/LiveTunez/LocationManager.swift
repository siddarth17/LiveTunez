import Foundation
import MapKit

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var region = MKCoordinateRegion()
    @Published var searchedPlaces: [Place] = []
    @Published var selectedPlace: Place?
    @Published var selectedLatitude: Double?
    @Published var selectedLongitude: Double?
    private var geocodingTask: DispatchWorkItem?
    private let locationManager = CLLocationManager()
    @Published var currentCity: String? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("CityUpdated"), object: nil)
        }
    }
    @Published var currentState: String?
    private var lastGeocodedLocation: CLLocation?
    private let geocodingThreshold: CLLocationDistance = 1000 // meters

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 1000 // meters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.delegate = self
    }
    
    func updateCurrentLocation() {
        guard let location = location else { return }
        
        if let lastLocation = lastGeocodedLocation,
           location.distance(from: lastLocation) < geocodingThreshold {
            return
        }
        
        geocodingTask?.cancel()
        
        let task = DispatchWorkItem { [weak self] in
            self?.performGeocoding(for: location)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: task)
        
        geocodingTask = task
    }
    
    private func performGeocoding(for location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Reverse geocoding error: \(error.localizedDescription)")
                return
            }
            
            guard let placemark = placemarks?.first else { return }
            
            DispatchQueue.main.async {
                self.currentCity = placemark.locality
                self.currentState = placemark.administrativeArea
                self.lastGeocodedLocation = location
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
                    let latitude = firstPlace.latitude.isFinite ? firstPlace.latitude : 0
                    let longitude = firstPlace.longitude.isFinite ? firstPlace.longitude : 0
                    let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    self?.region = MKCoordinateRegion(center: center, latitudinalMeters: 5000, longitudinalMeters: 5000)
                    self?.selectedPlace = firstPlace
                    self?.selectedLatitude = latitude
                    self?.selectedLongitude = longitude
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
