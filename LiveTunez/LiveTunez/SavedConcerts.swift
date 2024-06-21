//
//  SavedConcerts.swift
//  LiveTunez
//
//  Created by Siddarth Rudraraju on 4/10/24.
//

import Foundation
import SwiftUI
import Combine
import Contacts
import ContactsUI

struct SavedConcertsView: View {
    @EnvironmentObject var concertsManager: ConcertsManager
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(concertsManager.savedConcerts.values), id: \.id) { concert in
                    NavigationLink(destination: ConcertDetailPageView(concert: concert)) {
                        ConcertCardView(concert: concert)
                    }
                }
                .onDelete(perform: deleteConcert)
            }
            .navigationBarTitle("Saved Concerts")
            .listStyle(PlainListStyle())
            .navigationBarItems(leading: EditButton())
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func deleteConcert(at offsets: IndexSet) {
        offsets.forEach { index in
            let concert = Array(concertsManager.savedConcerts.values)[index]
            concertsManager.unsaveConcert(concert)
        }
    }
}

struct ConcertDetailView: View {
    @EnvironmentObject var concertsManager: ConcertsManager
    @State private var isShowingContacts = false
    @State private var selectedContacts: [CNContact] = []
    @State private var selectedContactIdentifiers: [String] = []
    @State private var contacts: [CNContact] = []
    
    let concert: AppConcert
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(concert.eventTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(concert.artistName)
                    .font(.title)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading) {
                    Text("Venue: \(concert.venueName)")
                    Text("Date: \(dateFormatter.string(from: concert.dateTime))")
                    Text("Location: \(concert.location)")
                }
                .font(.body)
                
                Button(action: {
                    isShowingContacts = true
                }) {
                    Text("Add Contact")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .sheet(isPresented: $isShowingContacts) {
                    ContactPicker(selectedContacts: $selectedContacts) { contact in
                    }
                }
                
                if !selectedContacts.isEmpty {
                    Text("Going with:")
                        .font(.headline)
                    
                    ForEach(selectedContacts, id: \.identifier) { contact in
                        HStack {
                            Text(contact.givenName)
                            
                            Spacer()
                            
                            Button(action: {
                            }) {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitle(Text("Concert Details"), displayMode: .inline)
        .onAppear {
            selectedContactIdentifiers = concertsManager.savedConcerts[concert.id]?.contactIdentifiers ?? []
            fetchContacts()
        }
    }

    private func fetchContacts() {
        let keys = [CNContactGivenNameKey, CNContactIdentifierKey]
        let contactStore = CNContactStore()
        var validContacts: [CNContact] = []
        
        for identifier in selectedContactIdentifiers {
            do {
                let contact = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keys as [CNKeyDescriptor])
                validContacts.append(contact)
            } catch {
                print("Failed to fetch contact with identifier: \(identifier). Error: \(error.localizedDescription)")
            }
        }
        
        contacts = validContacts
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var selectedContacts: [CNContact]
    let onSelectContact: (CNContact) -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let contactPicker = CNContactPickerViewController()
        contactPicker.delegate = context.coordinator
        
        let navigationController = UINavigationController(rootViewController: contactPicker)
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        
        init(_ parent: ContactPicker) {
            self.parent = parent
        }
        
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onSelectContact(contact)
        }
    }
}

struct SetlistCardView: View {
    let concert: AppConcert
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(concert.artistName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(Color.black)
                .multilineTextAlignment(.leading)
            
            Text(concert.formattedDate)
                .font(.subheadline)
                .foregroundColor(Color.black)
                .multilineTextAlignment(.leading)
            
            Text(concert.venueName)
                .font(.caption)
                .foregroundColor(Color.black)
                .multilineTextAlignment(.leading)
            
            Text(concert.location)
                .font(.caption)
                .foregroundColor(Color.black)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}
