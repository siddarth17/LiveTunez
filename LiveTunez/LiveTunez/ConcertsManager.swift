//
//  ConcertsManager.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 5/25/24.
//

import Foundation
import SwiftUI
import Combine
import Contacts
import Firebase
import UIKit

class ConcertsManager: ObservableObject {
    @Published var savedConcerts: [UUID: AppConcert] = [:]
    private var db = Firestore.firestore()
    private var deviceID: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? ""
    }

    init() {
        loadSavedConcertsFromFirebase()
    }

    func saveConcert(_ concert: AppConcert) {
        if !isConcertAlreadySaved(concert) {
            var updatedConcert = concert
            updatedConcert.isSaved = true
            savedConcerts[concert.id] = updatedConcert
            saveConcertToFirebase(concert: updatedConcert)
        }
    }

    func unsaveConcert(_ concert: AppConcert) {
        savedConcerts[concert.id] = nil
        deleteConcertFromFirebase(concert: concert)
    }

    func isConcertSaved(_ concert: AppConcert) -> Bool {
        return savedConcerts[concert.id] != nil
    }

    private func isConcertAlreadySaved(_ concert: AppConcert) -> Bool {
        return savedConcerts.values.contains { savedConcert in
            savedConcert.artistName == concert.artistName && savedConcert.venueName == concert.venueName
        }
    }

    private func saveConcertToFirebase(concert: AppConcert) {
        let concertData: [String: Any] = [
            "id": concert.id.uuidString,
            "setlistId": concert.setlistId,
            "artistName": concert.artistName,
            "eventTitle": concert.eventTitle,
            "dateTime": concert.dateTime,
            "venueName": concert.venueName,
            "location": concert.location,
            "image": concert.image,
            "isSaved": concert.isSaved,
            "contactIdentifiers": concert.contactIdentifiers
        ]
        
        db.collection("devices").document(deviceID).collection("concerts").document(concert.id.uuidString).setData(concertData) { error in
            if let error = error {
                print("Error saving concert to Firebase: \(error.localizedDescription)")
            } else {
                print("Concert saved to Firebase successfully: \(concert.artistName)")
            }
        }
    }
    
    private func deleteConcertFromFirebase(concert: AppConcert) {
        db.collection("devices").document(deviceID).collection("concerts").document(concert.id.uuidString).delete() { error in
            if let error = error {
                print("Error removing concert from Firebase: \(error.localizedDescription)")
            } else {
                print("Concert removed from Firebase successfully: \(concert.artistName)")
            }
        }
    }
    
    private func loadSavedConcertsFromFirebase() {
        db.collection("devices").document(deviceID).collection("concerts").getDocuments { snapshot, error in
            if let error = error {
                print("Error loading concerts from Firebase: \(error.localizedDescription)")
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No saved concerts found in Firebase")
                return
            }
            
            var loadedConcerts: [UUID: AppConcert] = [:]
            
            for document in documents {
                let data = document.data()
                
                guard let id = UUID(uuidString: data["id"] as? String ?? ""),
                      let setlistId = data["setlistId"] as? String,
                      let artistName = data["artistName"] as? String,
                      let eventTitle = data["eventTitle"] as? String,
                      let dateTime = (data["dateTime"] as? Timestamp)?.dateValue(),
                      let venueName = data["venueName"] as? String,
                      let location = data["location"] as? String,
                      let image = data["image"] as? String,
                      let isSaved = data["isSaved"] as? Bool,
                      let contactIdentifiers = data["contactIdentifiers"] as? [String] else {
                    print("Invalid concert data in Firebase: \(document.documentID)")
                    continue
                }
                
                let concert = AppConcert(id: id, setlistId: setlistId, artistName: artistName, eventTitle: eventTitle, dateTime: dateTime, venueName: venueName, location: location, image: image, isSaved: isSaved, contactIdentifiers: contactIdentifiers)
                loadedConcerts[id] = concert
            }
            
            DispatchQueue.main.async {
                self.savedConcerts = loadedConcerts
            }
        }
    }
}
