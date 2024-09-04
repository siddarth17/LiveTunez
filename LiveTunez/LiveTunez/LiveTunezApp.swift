//
//  LiveTunezApp.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct MyApp: App {
    @StateObject var concertsManager = ConcertsManager()
    @StateObject var locationManager = LocationManager()
    @StateObject var spotifyManager = SpotifyManager.shared
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(concertsManager)
                .environmentObject(locationManager)
                .environmentObject(spotifyManager)
                .onOpenURL { url in
                    if url.scheme == "livetunez" {
                        SpotifyManager.shared.handleRedirectURL(url) { success in
                        }
                    }
                }
        }
    }
}

struct MainAppView: View {
    @EnvironmentObject var concertsManager: ConcertsManager
    @EnvironmentObject var spotifyManager: SpotifyManager

    var body: some View {
        ContentView()
    }
}

struct MyApp_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainAppView()
                .environmentObject(ConcertsManager())
                .environmentObject(LocationManager())
                .environmentObject(SpotifyManager.shared)  
        }
    }
}
