//
//  ConcertViewModel.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//


import Foundation
import SwiftUI
import Combine
import MapKit
import Contacts

struct AppConcert: Identifiable, Decodable, Encodable {
    let id: UUID
    let setlistId: String
    let artistName: String
    let eventTitle: String
    let dateTime: Date
    let venueName: String
    let location: String
    var image: String
    var isSaved: Bool = false
    var contactIdentifiers: [String] = []

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: dateTime)
    }
}

struct SpotifyArtistSearchResult: Codable {
    let artists: ArtistsResult
}

struct ArtistsResult: Codable {
    let items: [ArtistItem]
}

struct ArtistItem: Codable {
    let name: String
    let images: [ArtistImage]
}

struct ArtistImage: Codable {
    let url: String
}

@MainActor
class ConcertViewModel: ObservableObject {
    @Published var concertsInCurrentCity: [AppConcert] = []
        
    private var locationManager: LocationManager?
        
    func setup(locationManager: LocationManager) {
        self.locationManager = locationManager
        NotificationCenter.default.addObserver(self, selector: #selector(cityUpdated), name: NSNotification.Name("CityUpdated"), object: nil)
        loadConcerts()
    }
    
    @objc private func cityUpdated() {
        loadConcerts()
    }
    
    private func loadConcerts() {
        guard let city = locationManager?.currentCity else { return }
        Task {
            concertsInCurrentCity = await fetchConcerts(in: city)
        }
    }

    private func fetchConcerts(in city: String) async -> [AppConcert] {
        let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.setlist.fm/rest/1.0/search/setlists?cityName=\(encodedCity)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("cKKe9xoznjm0XD59guHo4YXBAYyBOcjSlLkk", forHTTPHeaderField: "x-api-key")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let setlistSearchResult = try JSONDecoder().decode(SetlistSearchResult.self, from: data)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "dd-MM-yyyy" 

            let concerts = setlistSearchResult.setlist.compactMap { setlist -> AppConcert? in
                guard let date = dateFormatter.date(from: setlist.eventDate) else {
                    print("Error parsing date for setlist id: \(setlist.id)")
                    return nil
                }

                return AppConcert(
                    id: UUID(),
                    setlistId: setlist.id,
                    artistName: setlist.artist.name,
                    eventTitle: setlist.artist.name,
                    dateTime: date,
                    venueName: setlist.venue.name,
                    location: "\(setlist.venue.city.name), \(setlist.venue.city.country.name)",
                    image: setlist.artist.name
                )
            }
            return concerts
        } catch {
            print("Error fetching concerts: \(error.localizedDescription)")
            return []
        }
    }
}

struct HomeView: View {
    @StateObject var concertsViewModel = ConcertViewModel()
    @EnvironmentObject var locationManager: LocationManager
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Live Tunez")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color.purple)
                        .padding(.horizontal)
                    
                    if let city = locationManager.currentCity {
                        Text("Concerts in \(city)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    } else {
                        Text("Loading concerts...")
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    }
                    
                    HStack {
                        TextField("Enter city", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button(action: {
                            locationManager.searchPlaces(searchText)
                        }) {
                            Text("Search")
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack {
                        if !concertsViewModel.concertsInCurrentCity.isEmpty {
                            ForEach(concertsViewModel.concertsInCurrentCity.prefix(20)) { concert in
                                NavigationLink(destination: ConcertDetailPageView(concert: concert)) {
                                    ConcertCardView(concert: concert)
                                }
                            }
                        } else {
                            Text("No concerts available in your city.")
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .onAppear {
                        concertsViewModel.setup(locationManager: locationManager)
                    }
                }
            }
        }
    }
}
                         
struct IdentifiableLocation: Identifiable, Equatable{
    let id = UUID()
    let location: CLLocation
}

func convertToSetlist(concert: AppConcert) -> Setlist {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "dd-MM-yyyy"
    let formattedDate = dateFormatter.string(from: concert.dateTime)

    return Setlist(
        id: concert.setlistId,
        versionId: "1",
        eventDate: formattedDate,
        artist: Artist(name: concert.artistName),
        venue: Venue(
            name: concert.venueName,
            city: City(
                name: concert.location.components(separatedBy: ", ")[0],
                state: nil,
                stateCode: nil,
                country: Country(name: concert.location.components(separatedBy: ", ").last ?? "")
            )
        )
    )
}

struct ConcertCardView: View {
    let concert: AppConcert
    @State private var artistImageURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let imageURL = artistImageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .cornerRadius(10)
                } placeholder: {
                    ProgressView()
                        .frame(width: 100, height: 100)
                }
            } else {
                Image(systemName: "music.note")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(concert.artistName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                Text(concert.formattedDate)
                    .font(.subheadline)
                    .foregroundColor(Color.gray)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                Text(concert.venueName)
                    .font(.subheadline)
                    .foregroundColor(Color.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                Text(concert.location)
                    .font(.subheadline)
                    .foregroundColor(Color.black)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 5)
        .onAppear {
            fetchArtistImage()
        }
    }
    
    private func fetchArtistImage() {
        let artistName = concert.artistName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.spotify.com/v1/search?q=\(artistName)&type=artist"
        
        guard let accessToken = SpotifyManager.shared.accessToken else {
            print("Access token not available")
            return
        }
        
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error fetching artist image: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let artists = json["artists"] as? [String: Any],
               let items = artists["items"] as? [[String: Any]],
               let artist = items.first,
               let images = artist["images"] as? [[String: Any]],
               let imageURL = images.first?["url"] as? String {
                DispatchQueue.main.async {
                    self.artistImageURL = URL(string: imageURL)
                }
            }
        }.resume()
    }
}


struct Place: Identifiable {
    let id = UUID().uuidString
    private var mapItem: MKMapItem
    
    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
    }
    
    var name: String {
        self.mapItem.name ?? ""
    }
    
    var address: String{
        let placemark = self.mapItem.placemark
        var cityAndState = ""
        var address = ""
        
        cityAndState = placemark.locality ?? ""
        if let state = placemark.administrativeArea {
            cityAndState = cityAndState.isEmpty ? state : "\(cityAndState), \(state)"
        }
        
        address = placemark.subThoroughfare ?? ""
        if let street = placemark.thoroughfare{
            address = address.isEmpty ? street : "\(address) \(street)"
        }
        
        if address.trimmingCharacters(in: .whitespaces).isEmpty && !cityAndState.isEmpty{
            address = cityAndState
        } else{
            address = cityAndState.isEmpty ? address : "\(address), \(cityAndState)"
        }
        
        return address
    }
    
    var latitude: CLLocationDegrees {
        self.mapItem.placemark.coordinate.latitude
    }
    
    var longitude: CLLocationDegrees {
        self.mapItem.placemark.coordinate.longitude
    }
}

struct MapViewWrapper: UIViewRepresentable {
    @Binding var searchText: String
    @ObservedObject var locationManager: LocationManager
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        if let place = locationManager.selectedPlace {
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            annotation.title = place.name
            uiView.removeAnnotations(uiView.annotations)
            uiView.addAnnotation(annotation)
            
            let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
            uiView.setRegion(region, animated: true)
        } else {
            uiView.removeAnnotations(uiView.annotations)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWrapper
        
        init(_ parent: MapViewWrapper) {
            self.parent = parent
        }
    }
}
