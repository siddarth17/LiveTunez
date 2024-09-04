import SwiftUI
import Foundation
import Combine
import Firebase

struct SpotifyArtist: Codable {
    let name: String
}

struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
}

struct SpotifySearchResults: Codable {
    struct Tracks: Codable {
        let items: [SpotifyTrack]
    }
    let tracks: Tracks
}


class SpotifyManager: ObservableObject {
    static let shared = SpotifyManager()
    
    private let clientID = Config.spotifyClientID
    private let clientSecret = Config.spotifyClientSecret
    private let redirectURI = Config.spotifyRedirectURI
    
    @Published var isAuthenticated = false
    @Published var isInitializationComplete = false
    @Published var accessToken: String?
    @Published var isShowingAuthSheet = false
    
    private var cancellables: Set<AnyCancellable> = []
    
    @Published var displayName: String = ""
    @Published var email: String = ""
    @Published var userImageURL: String?
    
    private var db = Firestore.firestore()
    private var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? ""
    }
    
    init() {
        loadAccessTokenFromFirebase { [weak self] success in
            DispatchQueue.main.async {
                self?.isAuthenticated = success
                self?.isInitializationComplete = true
            }
        }
    }

    func authorize(completion: @escaping (Bool) -> Void) {
        validateAccessToken { [weak self] isValid in
            if !isValid {
                guard let self = self, let url = URL(string: "https://accounts.spotify.com/authorize?client_id=\(self.clientID)&response_type=code&redirect_uri=\(self.redirectURI)&scope=playlist-modify-private") else {
                    print("Invalid URL for authorization")
                    completion(false)
                    return
                }
                
                UIApplication.shared.open(url) { success in
                    completion(success)
                }
            } else {
                completion(true)
            }
        }
    }

    func validateAccessToken(completion: @escaping (Bool) -> Void) {
        guard let accessToken = accessToken else {
            completion(false)
            return
        }

        let url = URL(string: "https://api.spotify.com/v1/me")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Error validating token: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }

            print("HTTP response status code: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                print("Access token is invalid or expired.")
                completion(false)
            } else {
                completion(true)
            }
        }.resume()
    }

    func handleRedirectURL(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard let code = extractCode(from: url) else {
            print("No code found in URL, cannot proceed with token exchange")
            completion(false)
            return
        }
        
        exchangeCodeForToken(code: code) { [weak self] success in
            DispatchQueue.main.async {
                self?.isAuthenticated = success
                self?.isShowingAuthSheet = !success
                print("Authentication \(success ? "succeeded" : "failed")")
                
                if success {
                    self?.fetchUserProfile()
                }
                completion(success)
            }
        }
    }
    
    func fetchUserProfile() {
        guard let accessToken = accessToken else {
            print("Access token not available")
            return
        }
        
        let urlString = "https://api.spotify.com/v1/me"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("Error fetching user profile: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let displayName = json["display_name"] as? String,
               let email = json["email"] as? String {
                DispatchQueue.main.async {
                    self?.displayName = displayName
                    self?.email = email
                    
                    if let images = json["images"] as? [[String: Any]], let imageURL = images.first?["url"] as? String {
                        self?.userImageURL = imageURL
                    } else {
                        self?.userImageURL = nil
                    }
                }
            }
        }.resume()
    }
    
    func unauthorize() {
        DispatchQueue.main.async { [weak self] in
            self?.accessToken = nil
            self?.displayName = ""
            self?.email = ""
            self?.isAuthenticated = false
        }
        removeAccessTokenFromFirebase()
    }
    
    private func waitForRedirect(completion: @escaping (Bool) -> Void) {
        guard let url = getRedirectURL() else {
            completion(false)
            return
        }
        
        handleRedirectURL(url) { success in
            completion(success)
        }
    }
        
    private func getRedirectURL() -> URL? {
        return URL(string: "livetunez://callback")
    }

    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForToken(code: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        request.httpBody = parameters.percentEncoded()
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else {
                completion(false)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let accessToken = json["access_token"] as? String,
               let refreshToken = json["refresh_token"] as? String {
                self?.accessToken = accessToken
                self?.saveAccessTokenToFirebase(accessToken, refreshToken: refreshToken)
                self?.isAuthenticated = true
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }
    
    func createPlaylist(name: String, completion: @escaping (String?) -> Void) {
        refreshAccessTokenIfNeeded { [weak self] success in
            if success, let accessToken = self?.accessToken {
                self?.performCreatePlaylist(name: name, accessToken: accessToken, completion: completion)
            } else {
                print("Failed to refresh token.")
                completion(nil)
            }
        }
    }
    
    private func refreshAccessTokenIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let accessToken = accessToken else {
            print("Access Token is nil, attempting to refresh...")
            refreshAccessToken(completion: completion)
            return
        }
        
        if !isAccessTokenValid(accessToken) {
            print("Access Token has expired, attempting to refresh...")
            refreshAccessToken(completion: completion)
        } else {
            completion(true)
        }
    }
    
    private func performCreatePlaylist(name: String, accessToken: String, completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.spotify.com/v1/me/playlists")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let parameters: [String: Any] = ["name": name, "public": false]
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error creating playlist: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 201 {
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    print("Error Response: \(responseString)")
                }
                completion(nil)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let playlistID = json["id"] as? String else {
                print("Failed to parse playlist creation response or no ID found")
                completion(nil)
                return
            }
            
            completion(playlistID)
        }.resume()
    }
    
    private func isAccessTokenValid(_ accessToken: String) -> Bool {
        let parts = accessToken.components(separatedBy: ".")
        guard parts.count == 3 else {
            print("Invalid access token format.")
            return false
        }
        
        let encodedPayload = parts[1]
        let paddedEncodedPayload = encodedPayload.padding(toLength: ((encodedPayload.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        
        guard let decodedPayloadData = Data(base64Encoded: paddedEncodedPayload),
              let payloadDictionary = try? JSONSerialization.jsonObject(with: decodedPayloadData, options: []) as? [String: Any],
              let expirationTimeInterval = payloadDictionary["exp"] as? TimeInterval else {
            print("Failed to decode access token payload.")
            return false
        }
        
        let expirationDate = Date(timeIntervalSince1970: expirationTimeInterval)
        let currentDate = Date()
        
        return currentDate < expirationDate
    }

    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        db.collection("devices").document(deviceID).getDocument { snapshot, error in
            if let error = error {
                print("Error loading refresh token from Firebase: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let refreshToken = data["refreshToken"] as? String else {
                print("Refresh token not available.")
                completion(false)
                return
            }
            
            guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
                completion(false)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let bodyParameters = [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": self.clientID,
                "client_secret": self.clientSecret
            ]
            
            request.httpBody = bodyParameters.percentEncoded()
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    print("Error refreshing access token: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.authorizeFromRefreshTokenFailure(completion: completion)
                    }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let newAccessToken = json["access_token"] as? String else {
                    print("Failed to parse access token from refresh response.")
                    DispatchQueue.main.async {
                        self?.authorizeFromRefreshTokenFailure(completion: completion)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self?.saveAccessTokenToFirebase(newAccessToken, refreshToken: refreshToken)
                    self?.accessToken = newAccessToken
                    print("New Access Token stored: \(newAccessToken)")
                    print("Access token refreshed successfully.")
                    completion(true)
                }
            }.resume()
        }
    }

    private func authorizeFromRefreshTokenFailure(completion: @escaping (Bool) -> Void) {
        print("Refresh token failed. Prompting user to re-authenticate.")
        
        accessToken = nil
        removeAccessTokenFromFirebase()
        
        authorize { success in
            completion(success)
        }
    }
    
    func searchTrackIDs(songNames: [String], artistName: String, completion: @escaping ([String]) -> Void) {
        let group = DispatchGroup()
        var trackIDs = [String]()

        for songName in songNames {
            group.enter()
            searchTrack(songName: songName, artistName: artistName) { trackID in
                if let trackID = trackID {
                    trackIDs.append(trackID)
                } else {
                    print("No track ID found for song: \(songName)")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(trackIDs)
        }
    }
    
    func validateAndAuthorize(completion: @escaping (Bool) -> Void) {
        guard isInitializationComplete else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.validateAndAuthorize(completion: completion)
            }
            return
        }
        
        if isAuthenticated {
            completion(true)
            return
        }
        
        validateAccessToken { [weak self] isValid in
            DispatchQueue.main.async {
                if isValid {
                    self?.isAuthenticated = true
                    completion(true)
                } else {
                    self?.authorize { success in
                        completion(success)
                    }
                }
            }
        }
    }

    func searchTrack(songName: String, artistName: String, completion: @escaping (String?) -> Void) {
        guard let accessToken = accessToken else {
            completion(nil)
            return
        }

        let normalizedSongName = normalize(songName: songName)
        let normalizedArtistName = normalize(songName: artistName)
        
        let queryWithArtist = "track:\(normalizedSongName) artist:\(normalizedArtistName)"
        let queryWithArtistReversed = "track:\(normalizedSongName) artist:\(reverseArtistName(normalizedArtistName))"
        let queryWithSongOnly = "track:\(normalizedSongName)"

        let detailedSearchQueries = [queryWithArtist, queryWithArtistReversed]
        
        performSpotifySearchWithPermutations(queries: detailedSearchQueries, accessToken: accessToken) { foundTrackID in
            if let trackID = foundTrackID {
                completion(trackID)
            } else {
                self.performSpotifySearch(query: queryWithSongOnly, accessToken: accessToken, limit: 10) { tracks in
                    if let track = tracks.first {
                        completion(track.id)
                    } else {
                        self.fallbackSearch(songName: normalizedSongName, artistName: artistName, accessToken: accessToken, completion: completion)
                    }
                }
            }
        }
    }

    func fallbackSearch(songName: String, artistName: String, accessToken: String, completion: @escaping (String?) -> Void) {
        let basicSearchQuery = "track:\(songName) artist:\(artistName)"
        performSpotifySearch(query: basicSearchQuery, accessToken: accessToken, limit: 10) { tracks in
            if let track = tracks.first {
                completion(track.id)
            } else {
                let songOnlyQuery = "track:\(songName)"
                self.performSpotifySearch(query: songOnlyQuery, accessToken: accessToken, limit: 10) { tracks in
                    completion(tracks.first?.id)
                }
            }
        }
    }

    func reverseArtistName(_ artistName: String) -> String {
        let components = artistName.split(separator: "&").map { String($0).trimmingCharacters(in: .whitespaces) }
        return components.reversed().joined(separator: " & ")
    }

    func performSpotifySearchWithPermutations(queries: [String], accessToken: String, completion: @escaping (String?) -> Void) {
        let group = DispatchGroup()
        var foundTrackID: String? = nil

        for query in queries {
            group.enter()
            performSpotifySearch(query: query, accessToken: accessToken, limit: 10) { tracks in
                if let track = tracks.first, foundTrackID == nil {
                    foundTrackID = track.id
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(foundTrackID)
        }
    }

    func performSpotifySearch(query: String, accessToken: String, limit: Int, completion: @escaping ([SpotifyTrack]) -> Void) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.spotify.com/v1/search?q=\(encodedQuery)&type=track&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error searching for track: \(error?.localizedDescription ?? "unknown error")")
                completion([])
                return
            }

            do {
                let searchResults = try JSONDecoder().decode(SpotifySearchResults.self, from: data)
                completion(searchResults.tracks.items)
            } catch {
                print("Failed to decode search results: \(error)")
                completion([])
            }
        }.resume()
    }


    func normalize(songName: String) -> String {
        // Regex to remove parentheses and non-alphanumeric characters except spaces and hyphens
        let regex = try! NSRegularExpression(pattern: "\\s*\\([^)]*\\)|[^\\w\\s-]", options: [])
        let range = NSRange(location: 0, length: songName.utf16.count)
        let simpleTitle = regex.stringByReplacingMatches(in: songName, options: [], range: range, withTemplate: "")
        return simpleTitle.trimmingCharacters(in: .whitespaces)
    }


    func findBestMatch(tracks: [SpotifyTrack], originalSongName: String, artistName: String) -> SpotifyTrack? {
        let normalizedOriginal = normalize(songName: originalSongName)
        let normalizedArtist = normalize(songName: artistName)
        
        return tracks.first { track in
            let normalizedTrackName = normalize(songName: track.name)
            let normalizedTrackArtists = track.artists.map { normalize(songName: $0.name) }.joined(separator: " & ")
            
            return normalizedTrackName == normalizedOriginal && (normalizedTrackArtists.contains(normalizedArtist) || normalizedTrackArtists.contains(reverseArtistName(normalizedArtist)))
        }
    }

    func similarityScore(between original: String, and candidate: String) -> Int {
        let originalWords = Set(original.lowercased().split(separator: " "))
        let candidateWords = Set(candidate.lowercased().split(separator: " "))
        return originalWords.intersection(candidateWords).count
    }

    func addTracksToPlaylist(playlistID: String, trackIDs: [String], completion: @escaping (Bool) -> Void) {
        guard let accessToken = accessToken, !trackIDs.isEmpty else {
            print("Access Token is nil or track IDs are empty when trying to add tracks")
            completion(false)
            return
        }

        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistID)/tracks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackURIs = trackIDs.map { "spotify:track:\($0)" }
        let parameters: [String: Any] = ["uris": trackURIs]
        request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                    completion(true)
                } else {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Failed to add tracks, HTTP Status: \(httpResponse.statusCode), Response: \(responseString)")
                    }
                    completion(false)
                }
            } else if let error = error {
                print("Error adding tracks to playlist: \(error.localizedDescription)")
                completion(false)
            } else {
                print("Unexpected error: HTTP response is not available.")
                completion(false)
            }
        }.resume()
    }
    
    private func saveAccessTokenToFirebase(_ accessToken: String, refreshToken: String) {
        let data: [String: Any] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken
        ]
        
        db.collection("devices").document(deviceID).setData(data) { error in
            if let error = error {
                print("Error saving access token to Firebase: \(error.localizedDescription)")
            } else {
                print("Access token saved to Firebase successfully")
            }
        }
    }
    
    private func loadAccessTokenFromFirebase(completion: @escaping (Bool) -> Void) {
        db.collection("devices").document(deviceID).getDocument { snapshot, error in
            if let error = error {
                print("Error loading access token from Firebase: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let data = snapshot?.data(),
                  let accessToken = data["accessToken"] as? String else {
                print("No access token found in Firebase")
                completion(false)
                return
            }

            self.accessToken = accessToken
            self.validateAccessToken { isValid in
                completion(isValid)
            }
        }
    }
    
    private func removeAccessTokenFromFirebase() {
        db.collection("devices").document(deviceID).updateData([
            "accessToken": FieldValue.delete(),
            "refreshToken": FieldValue.delete()
        ]) { error in
            if let error = error {
                print("Error removing access token from Firebase: \(error.localizedDescription)")
            } else {
                print("Access token removed from Firebase successfully")
            }
        }
    }
}

extension Dictionary {
    func percentEncoded() -> Data? {
        return map { key, value in
            let escapedKey = "\(key)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            let escapedValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
            return escapedKey + "=" + escapedValue
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@"
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "\(generalDelimitersToEncode)\(subDelimitersToEncode)")
        return allowed
    }()
}
