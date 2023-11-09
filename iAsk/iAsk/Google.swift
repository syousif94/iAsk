//
//  Google.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/18/23.
//

import Foundation
import GoogleSignIn

let startGoogleSignInNotification = NotificationPublisher<Void>()

class Google {
    static let shared = Google()
    
    var user: GIDGoogleUser? {
        return GIDSignIn.sharedInstance.currentUser
    }
    
    init()  {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if error != nil || user == nil {
                print("no google user")
            } else {
                print("google user", user!)
            }
        }
    }
    
    func signIn(controller: ViewController) async throws {
        DispatchQueue.main.async {
            Task {
                
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller, hint: nil, additionalScopes: ["https://mail.google.com/", "https://www.googleapis.com/auth/contacts", "https://www.googleapis.com/auth/contacts.other.readonly"])
                
                let user = result.user
                
                print(user.profile, user.accessToken.tokenString)
            }
        }
        
    }
    
    func searchContacts(query: String) async throws -> [PersonResponse] {
        let urlString = "https://people.googleapis.com/v1/otherContacts:search?query=\(query)&readMask=names,emailAddresses,phoneNumbers"
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        
        var request = URLRequest(url: url)
        
        request.setValue("Bearer \(user?.accessToken.tokenString ?? "")", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        do {
            let persons = try JSONDecoder().decode([PersonResponse].self, from: data)

            return persons
        } catch {
            throw error
        }
    }
}

extension Google.PersonResponse {
    func toChoices(of type: ContactType) -> [ContactManager.Choice] {
        switch type {
        case .address:
            return []
        case.email:
            return person.emailAddresses.compactMap { ContactManager.Choice(name: person.names[0].displayName, detail: $0.value) }
        case.phone:
            return person.phoneNumbers.compactMap { ContactManager.Choice(name: person.names[0].displayName, detail: $0.value) }
        }
    }
}


extension Google {
    struct PersonResponse: Codable {
        let person: Person
    }
    
    struct Person: Codable {
        let emailAddresses: [EmailAddress]
        let phoneNumbers: [PhoneNumber]
        let etag: String
        let names: [Name]
        let resourceName: String
    }
    
    struct PhoneNumber: Codable {
        let metadata: Metadata
        let value: String
    }

    struct EmailAddress: Codable {
        let metadata: Metadata
        let value: String
    }

    struct Metadata: Codable {
        let primary: Int
        let source: Source
        let sourcePrimary: Int
    }

    struct Source: Codable {
        let id: String
        let type: String
    }

    struct Name: Codable {
        let displayName: String
        let displayNameLastFirst: String
        let familyName: String
        let givenName: String
        let metadata: Metadata
        let unstructuredName: String
    }
}
