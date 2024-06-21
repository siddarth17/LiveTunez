//
//  ContentView.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var spotifyManager: SpotifyManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            SavedConcertsView()
                .tabItem {
                    Label("Saved", systemImage: "heart.fill")
                }
        }
        .onAppear {
            spotifyManager.validateAndAuthorize { success in
                if !success {
                    print("Authentication failed")
                }
            }
        }
        .sheet(isPresented: $spotifyManager.isShowingAuthSheet) {
            SpotifyAuthView(spotifyManager: spotifyManager)
        }
    }
}

struct SpotifyAuthView: UIViewControllerRepresentable {
    var spotifyManager: SpotifyManager

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        spotifyManager.authorize { success in
            if success {
                DispatchQueue.main.async {
                    viewController.dismiss(animated: true, completion: nil)
                }
            } else {
            }
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(SpotifyManager.shared)
    }
}


