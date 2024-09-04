//
//  SearchView.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import Foundation
import SwiftUI
import Combine
import Firebase

class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [Setlist] = []
    @Published var recentSearches: [String] = []
    @Published var isClearVisible: Bool = false
    
    private var cancellables: Set<AnyCancellable> = []
    private var db = Firestore.firestore()
    private var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? ""
    }
    
    init() {
        loadRecentSearches()
    }
    
    func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            isClearVisible = false
            return
        }
        
        isClearVisible = true
        updateRecentSearches()
        
        let urlString = "https://api.setlist.fm/rest/1.0/search/setlists?artistName=\(searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("cKKe9xoznjm0XD59guHo4YXBAYyBOcjSlLkk", forHTTPHeaderField: "x-api-key")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: SetlistSearchResult.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    print("Error: \(error.localizedDescription)")
                }
            }, receiveValue: { [weak self] result in
                self?.searchResults = result.setlist
            })
            .store(in: &cancellables)
    }
    
    func updateRecentSearches() {
        if !searchText.isEmpty && !recentSearches.contains(searchText) {
            recentSearches.insert(searchText, at: 0)
            if recentSearches.count > 10 {
                recentSearches.removeLast()
            }
            saveRecentSearches()
        }
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        isClearVisible = false
    }
    
    func removeRecentSearch(at offsets: IndexSet) {
        recentSearches.remove(atOffsets: offsets)
        saveRecentSearches()
    }
    
    func saveRecentSearches() {
        db.collection("devices").document(deviceID).collection("searches").document("recentSearches").setData(["searches": recentSearches]) { error in
            if let error = error {
                print("Error saving recent searches to Firebase: \(error.localizedDescription)")
            } else {
                print("Recent searches saved to Firebase successfully")
            }
        }
    }
    
    func loadRecentSearches() {
        db.collection("devices").document(deviceID).collection("searches").document("recentSearches").getDocument { snapshot, error in
            if let error = error {
                print("Error loading recent searches from Firebase: \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data(),
                  let searches = data["searches"] as? [String] else {
                print("No recent searches found in Firebase")
                return
            }
            
            DispatchQueue.main.async {
                self.recentSearches = searches
                print("Recent searches loaded from Firebase")
            }
        }
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBarView(
                    searchText: $viewModel.searchText,
                    isClearVisible: $viewModel.isClearVisible,
                    onCommit: {
                        isSearchFieldFocused = false
                        viewModel.performSearch()
                    },
                    onClear: {
                        viewModel.clearSearch()
                        presentationMode.wrappedValue.dismiss()
                    },
                    placeholder: "Search for artists"
                )
                .padding()
                .focused($isSearchFieldFocused)
                
                if !viewModel.recentSearches.isEmpty && viewModel.searchText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Searches")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.recentSearches, id: \.self) { search in
                            HStack {
                                Text(search)
                                    .onTapGesture {
                                        viewModel.searchText = search
                                        viewModel.performSearch()
                                    }
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    if let index = viewModel.recentSearches.firstIndex(of: search) {
                                        viewModel.recentSearches.remove(at: index)
                                        viewModel.saveRecentSearches()
                                    }
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                } else if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        VStack {
                            ForEach(viewModel.searchResults) { setlist in
                                NavigationLink(destination: ConcertDetailPageView(setlist: setlist)) {
                                    SearchResultCardView(setlist: setlist)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Search")
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFieldFocused = true
                }
            }
        }
    }
}

struct SearchResultCardView: View {
    let setlist: Setlist
    @State private var artistImageURL: URL?
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
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
                Text(setlist.artist.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text(setlist.eventDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                Text(setlist.venue.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text("\(setlist.venue.city.name), \(setlist.venue.city.country.name)")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading)
            
            Spacer()
        }
        .padding(10)
        .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
        .cornerRadius(10)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.3), radius: 5, x: 0, y: 2)
        .onAppear {
            fetchArtistImage()
        }
    }
    
    private func fetchArtistImage() {
        let artistName = setlist.artist.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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

struct SearchBarView: View {
    @Binding var searchText: String
    @Binding var isClearVisible: Bool
    var onCommit: () -> Void
    var onClear: () -> Void
    var placeholder: String
    
    var body: some View {
        HStack {
            CustomUITextField(text: $searchText, placeholder: placeholder, onCommit: onCommit)
                .frame(height: 40)
                .padding(7)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            if isClearVisible {
                Button(action: onClear) {
                    Image(systemName: "multiply.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
