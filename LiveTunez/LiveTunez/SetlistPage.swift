//
//  SetlistPage.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import SwiftUI
import Foundation
import Combine
import EventKit

struct SetlistData: Codable {
    let id: String
    let versionId: String
    let eventDate: String
    let artist: Artist
    let venue: Venue
    let tour: Tour?
    let sets: Sets  
    let url: String
    let lastUpdated: String
}

struct Sets: Codable {
    let set: [SetData]
}

struct SetData: Codable, Hashable {
    let song: [Song]
    let encore: Int?
}

struct Song: Codable, Hashable {
    let name: String
    let cover: Cover?
    let info: String?
    let tape: Bool?

    struct Cover: Codable, Hashable {
        let mbid: String
        let name: String
        let sortName: String
        let disambiguation: String?
        let url: String
    }
}


struct Tour: Codable {
    let name: String
}

struct SetlistSearchResult: Codable {
    let setlist: [Setlist]
    let total: Int
    let page: Int
    let itemsPerPage: Int
}

struct Setlist: Codable, Identifiable {
    let id: String
    let versionId: String
    let eventDate: String
    let artist: Artist
    let venue: Venue
    
    enum CodingKeys: String, CodingKey {
        case id
        case versionId
        case eventDate
        case artist
        case venue
    }
}

struct Artist: Codable {
    let name: String
}

struct Venue: Codable {
    let name: String
    let city: City
}

struct City: Codable {
    let name: String
    let state: String?
    let stateCode: String?
    let country: Country
}

struct Country: Codable {
    let name: String
}

class ConcertDetailViewModel: ObservableObject {
    @Published var setlist: Setlist
    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var weatherDetails: WeatherDetails?
    @Published var setlistData: SetlistData?
    @Published var artistImageURL: URL? = nil

    struct WeatherDetails {
        let sunrise: Date
        let sunset: Date
        let temperature: Double
        let rainAmount: Double
        let humidity: Int
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }
    
    init(setlist: Setlist) {
        self.setlist = setlist
        fetchSetlistData()
        fetchArtistImage()
    }
    
    func fetchArtistImage() {
        guard let accessToken = SpotifyManager.shared.accessToken else {
            print("Access token not available")
            return
        }
        
        let artistName = setlist.artist.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.spotify.com/v1/search?q=\(artistName)&type=artist"
        guard let url = URL(string: urlString) else {
            print("Invalid URL for artist image fetch")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching artist image: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let artists = json["artists"] as? [String: Any],
               let items = artists["items"] as? [[String: Any]],
               let artist = items.first,
               let images = artist["images"] as? [[String: Any]],
               let imageURL = images.first?["url"] as? String {
                DispatchQueue.main.async {
                    self?.artistImageURL = URL(string: imageURL)
                }
            }
        }.resume()
    }
    
    func formattedDate() -> String {
        dateFormatter.string(from: setlist.eventDate.toDate() ?? Date())
    }
    
    func fetchWeatherDetails() {
        let city = setlist.venue.city.name
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(city) { [weak self] placemarks, error in
            if let error = error {
                print("Geocoding error: \(error.localizedDescription)")
                return
            }
            
            guard let placemark = placemarks?.first,
                  let location = placemark.location else { return }
            
            self?.latitude = location.coordinate.latitude
            print(location.coordinate.latitude)
            self?.longitude = location.coordinate.longitude
            
            self?.fetchWeatherData()
        }
    }
    
    private func fetchWeatherData() {
        let urlString = "https://api.openweathermap.org/data/3.0/onecall?lat=\(latitude)&lon=\(longitude)&exclude=minutely,hourly,daily,alerts&appid=\(Config.openWeatherMapAPIKey)&units=metric"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            
            do {
                let weatherResponse = try decoder.decode(WeatherResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.weatherDetails = WeatherDetails(
                        sunrise: weatherResponse.current.sunrise,
                        sunset: weatherResponse.current.sunset,
                        temperature: weatherResponse.current.temp,
                        rainAmount: weatherResponse.current.rain?.last1h ?? 0.0,
                        humidity: weatherResponse.current.humidity
                    )
                }
            } catch {
                print("Error decoding weather data: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func fetchSetlistData() {
        let urlString = "https://api.setlist.fm/rest/1.0/setlist/\(setlist.id)"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("cKKe9xoznjm0XD59guHo4YXBAYyBOcjSlLkk", forHTTPHeaderField: "x-api-key")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error fetching setlist data: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            do {
                let setlistData = try decoder.decode(SetlistData.self, from: data)
                DispatchQueue.main.async {
                    self?.setlistData = setlistData
                }
            } catch {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    print("Setlist not found for the given ID")
                    DispatchQueue.main.async {
                        self?.setlistData = nil
                    }
                }
                print("Error decoding setlist data: \(error)")
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .dataCorrupted(let context):
                        print(context)
                    case .keyNotFound(let key, let context):
                        print("Missing key: \(key) in context: \(context)")
                    case .typeMismatch(let type, let context):
                        print("Type mismatch: \(type) in context: \(context)")
                    case .valueNotFound(let type, let context):
                        print("Value not found: \(type) in context: \(context)")
                    @unknown default:
                        print("Unknown decoding error")
                    }
                }
            }

        }.resume()
    }
    
    func isConcertInFuture() -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        
        guard let concertDate = dateFormatter.date(from: setlist.eventDate) else {
            print("Failed to parse concert date from string: \(setlist.eventDate)")
            return false
        }
        
        return concertDate >= Date()
    }
    
    func importSetlistToSpotify() {
        
        SpotifyManager.shared.createPlaylist(name: "\(setlist.artist.name) - \(setlist.eventDate)") { playlistID in
            guard let playlistID = playlistID else {
                print("Failed to create playlist")
                return
            }
            
            
            SpotifyManager.shared.searchTrackIDs(
                songNames: self.setlistData?.sets.set.flatMap { $0.song.map { $0.name } } ?? [],
                artistName: self.setlist.artist.name
            ) { trackIDs in
                
                SpotifyManager.shared.addTracksToPlaylist(playlistID: playlistID, trackIDs: trackIDs) { success in
                    if success {
                        print("Playlist created and tracks added successfully.")
                    } else {
                        print("Failed to add tracks to the playlist.")
                    }
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        rootViewController.present(alert, animated: true, completion: nil)
    }

    private func openPlaylistInSpotify(playlistID: String) {
        let spotifyURL = URL(string: "spotify:playlist:\(playlistID)")
        if UIApplication.shared.canOpenURL(spotifyURL!) {
            UIApplication.shared.open(spotifyURL!, options: [:], completionHandler: nil)
        } else {
            let webURL = URL(string: "https://open.spotify.com/playlist/\(playlistID)")
            UIApplication.shared.open(webURL!, options: [:], completionHandler: nil)
        }
    }
    
    private func searchTrackIDs(songNames: [String]) -> [String] {
        var trackIDs: [String] = []
        let dispatchGroup = DispatchGroup()
        
        for songName in songNames {
            dispatchGroup.enter()
            searchTrack(songName: songName) { trackID in
                if let trackID = trackID {
                    trackIDs.append(trackID)
                } else {
                    print("No track ID found for song: \(songName)")
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.wait()
        return trackIDs
    }

    private func searchTrack(songName: String, completion: @escaping (String?) -> Void) {
        guard let accessToken = SpotifyManager.shared.accessToken else {
            completion(nil)
            return
        }
        
        let encodedSongName = songName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.spotify.com/v1/search?q=\(encodedSongName)&type=track&limit=1"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data else {
                completion(nil)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let tracks = json["tracks"] as? [String: Any],
               let items = tracks["items"] as? [[String: Any]],
               let trackID = items.first?["id"] as? String {
                completion(trackID)
            } else {
                completion(nil)
            }
        }.resume()
    }

    struct WeatherResponse: Codable {
        let current: CurrentWeather
        struct CurrentWeather: Codable {
            let sunrise: Date
            let sunset: Date
            let temp: Double
            let rain: Rain?
            let humidity: Int
            
            struct Rain: Codable {
                let last1h: Double

                enum CodingKeys: String, CodingKey {
                    case last1h = "1h"
                }
            }
        }
    }
}

extension String {
    func toDate(withFormat format: String = "dd-MM-yyyy") -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter.date(from: self)
    }
}

struct ConcertDetailPageView: View {
    @StateObject var viewModel: ConcertDetailViewModel
    @EnvironmentObject var concertsManager: ConcertsManager
    @State private var isSaved: Bool = false
    @State private var showingCalendarAlert = false
    @State private var selectedDate = Date()
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    init(setlist: Setlist) {
        _viewModel = StateObject(wrappedValue: ConcertDetailViewModel(setlist: setlist))
    }
    
    init(concert: AppConcert) {
        _viewModel = StateObject(wrappedValue: ConcertDetailViewModel(setlist: convertToSetlist(concert: concert)))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let imageURL = viewModel.artistImageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 300)
                            .clipped()
                    } placeholder: {
                        ProgressView()
                            .frame(height: 300)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.setlist.artist.name)
                        .font(.title)
                        .fontWeight(.bold)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Venue: \(viewModel.setlist.venue.name)")
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Date: \(viewModel.setlist.eventDate)")
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text("Location: \(viewModel.setlist.venue.city.name ), \(viewModel.setlist.venue.city.country.name)")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                
                
                HStack {
                    Spacer()
                    if viewModel.isConcertInFuture() {
                        Button(action: {
                            showingCalendarAlert = true
                        }) {
                            Text("Add Event to Calendar")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                        .sheet(isPresented: $showingCalendarAlert) {
                            VStack {
                                DatePicker("Select Date and Time", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                Button("Add to Calendar") {
                                    addEventToCalendar(at: selectedDate)
                                    showingCalendarAlert = false
                                }
                                .padding()
                            }
                        }
                    } else {
                        Button(action: {
                            validateAndHandleSpotifyImport()
                        }) {
                            Text("Import Setlist to Spotify")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    
                    Button(action: {
                        let concert = convertToAppConcert(setlist: viewModel.setlist)
                        if isSaved {
                            concertsManager.unsaveConcert(concert)
                            isSaved = false
                        } else {
                            concertsManager.saveConcert(concert)
                            isSaved = true
                        }
                    }) {
                        Text("Save                     Concert")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                    Spacer()
                }
                .padding()
                
                Divider()
            
                if !viewModel.isConcertInFuture(){
                    if let setlistData = viewModel.setlistData {
                        if setlistData.sets.set.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Setlist")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("Setlist data is unavailable for this concert.")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Setlist")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                ForEach(setlistData.sets.set, id: \.self) { set in
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(set.song, id: \.name) { song in
                                            Text(song.name)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Concert Details")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            let concert = convertToAppConcert(setlist: viewModel.setlist)
            isSaved = concertsManager.isConcertSaved(concert)
            viewModel.fetchSetlistData()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private func convertToAppConcert(setlist: Setlist) -> AppConcert {
        let dateTime = setlist.eventDate.toDate() ?? Date()
        let location = "\(setlist.venue.city.name), \(setlist.venue.city.country.name)"
        
        return AppConcert(
            id: UUID(),
            setlistId: setlist.id,
            artistName: setlist.artist.name,
            eventTitle: setlist.venue.name,
            dateTime: dateTime,
            venueName: setlist.venue.name,
            location: location,
            image: setlist.artist.name
        )
    }
    
    func validateAndHandleSpotifyImport() {
        SpotifyManager.shared.validateAccessToken { isValid in
            if isValid {
                DispatchQueue.main.async {
                    viewModel.importSetlistToSpotify()
                }
            } else {
                DispatchQueue.main.async {
                    // Open the authentication sheet in the browser
                    SpotifyManager.shared.authorize { success in
                        if success {
                            viewModel.importSetlistToSpotify()
                        }
                    }
                }
            }
        }
    }
    
    func showAlertToAuthenticate() {
        alertTitle = "Authentication Needed"
        alertMessage = "Please authenticate with Spotify to continue."
        showAlert = true
    }
    
    
    private func addEventToCalendar(at selectedDate: Date) {
        let eventStore = EKEventStore()
        
        eventStore.requestFullAccessToEvents { granted, error in
            if let error = error {
                print("Error requesting full calendar access: \(error.localizedDescription)")
                return
            }

            if granted {
                let event = EKEvent(eventStore: eventStore)
                event.title = viewModel.setlist.artist.name
                event.startDate = selectedDate
                event.endDate = selectedDate.addingTimeInterval(3600)  
                event.calendar = eventStore.defaultCalendarForNewEvents

                do {
                    try eventStore.save(event, span: .thisEvent)
                    DispatchQueue.main.async {
                    }
                } catch {
                    print("Error saving event to calendar: \(error.localizedDescription)")
                }
            } else {
                print("Full access to calendar denied")
            }
        }
    }

}


