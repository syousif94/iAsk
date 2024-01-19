//
//  Contacts.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/17/23.
//

import SwiftyContacts
import FuzzyFind
import UIKit
import ContactsUI
import SwiftUI


class SearchableContact: Searchable {
    
    let contact: CNContact
    
    @Search var givenName: String
    @Search var familyName: String
    @Search var nickName: String
    
    init(contact: CNContact) {
        self.contact = contact
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.nickName = contact.nickname
    }
}

enum ContactType: String, Codable {
    case email = "email"
    case phone = "phone"
    case address = "address"
}

typealias SortedSearchable<T: Searchable> = (T, [FuzzyFind.Alignment])

class ContactManager {
    
    static let shared = ContactManager()
    
    private var contacts: [SearchableContact]?
    
    private var nameToContact = [String: SearchableContact]()
    
    private var loadContactsTask: Task<[SearchableContact], Error>?
       
    func getContacts() async throws -> [SearchableContact]? {
       if let contacts = contacts {
           return contacts
       }
       
       if loadContactsTask == nil {
           loadContactsTask = Task {
               let contacts = try await fetchContacts()
               
               return contacts.map(SearchableContact.init)
           }
       }
        
        if let task = loadContactsTask {
            let contacts = try await task.value
            self.contacts = contacts
        }
        

       return contacts
    }
    
    func createContact(from args: CreateNewContactArgs) async -> CNContact? {
    
        guard let hasAccess = try? await checkAccess(),
              hasAccess else {
            return nil
        }
        
        let contact = CNMutableContact()
        
        let splitName = args.name.split(separator: " ")
        
        if let first = splitName.first {
            contact.givenName = String(first)
            let last = splitName.dropFirst().joined(separator: " ")
            if !last.isEmpty {
                contact.familyName = last
            }
        }
        else {
            return nil
        }
        
        if let email = args.email {
            let email = CNLabeledValue(label: CNLabelHome, value: email as NSString)
            contact.emailAddresses = [email]
        }
        
        if let number = args.number {
            let phone = CNLabeledValue(label: CNLabelPhoneNumberiPhone, value: CNPhoneNumber(stringValue: number))
            contact.phoneNumbers = [phone]
        }
        
        if let employer = args.employer {
            contact.organizationName = employer
        }

        return contact
    }
    
    func save(contact: CNContact) throws {
        try addContact(contact)
    }
    
    func loadContact(by identifier: String) async -> CNContact? {
        guard let hasAccess = try? await checkAccess(), hasAccess else {
            return nil
        }
        
        let store = CNContactStore()
        let keysToFetch = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        
        do {
            let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)
            return contact
        } catch {
            print("Error fetching contact with identifier: \(identifier)")
            return nil
        }
    }
    
    private func checkAccess() async throws -> Bool {
        let status = authorizationStatus()
        
        print("initial authorization status")
        
        if status == .authorized {
            print("authorized")
            return true
        }
        else if status == .notDetermined {
            print("not determined")
            let access = try await requestAccess()
            print("requested access")
            if access {
                print("access granted")
                return true
            }
        }
        
        return false
    }
    
    func searchLocalContacts(query: String) async throws -> [SortedSearchable<SearchableContact>] {
        guard let hasAccess = try? await checkAccess(),
              hasAccess,
              let contacts = try? await getContacts() else {
            return []
        }
        
        let results = contacts.search(query: query)
        
        return results
    }
    
    func getGoogleChoices(query: String, contactType: ContactType) async -> [ContactManager.Choice] {
        let personResponses = try? await Google.shared.searchContacts(query: query)
        
        guard let personResponses = personResponses else {
            return []
        }
        
        let choices: [ContactManager.Choice] = personResponses.flatMap { $0.toChoices(of: contactType) }
        
        return choices
    }
    
    func getLocalChoices(query: String, contactType: ContactType) async -> [Choice] {
//        guard let contacts = try? await searchLocalContacts(query: query) else {
//            return []
//        }
//        
        
        guard let contacts = try? fetchContacts(matchingName: query) else { return [] }
        
        let choices = contacts.flatMap { contact in
            var contactName = ""
            
            if contact.nickname.isEmpty {
                contactName = [contact.givenName, contact.familyName].joined(separator: " ")
            }
            else {
                contactName = contact.nickname
            }
            
            let choices: [Choice]
            
            if contactType == .email {
                
                choices = contact.emailAddresses.map { Choice(name: contactName, detail: "\($0.value as String) (\($0.label ?? ""))") }
                
            } else {
                
                choices = contact.phoneNumbers.map { Choice(name: contactName, detail: "\($0.value.stringValue) (\($0.label ?? ""))") }
                
            }
            
            return choices
        }
        
        return choices
    }
    
    func getChoices(query: String, contactType: ContactType) async -> [Choice] {
        async let localChoices = getLocalChoices(query: query, contactType: contactType)
        async let googleChoices = getGoogleChoices(query: query, contactType: contactType)
        
        let l = await localChoices
        let g = await googleChoices
        
        return (l + g).unique(by: \.detail)
    }
    
    struct Choice: Identifiable, Codable, Hashable {
        var id: String {
            return name + detail
        }
        
        let name: String
        let detail: String
    }
    
}

@propertyWrapper
struct Search {
    var wrappedValue: String
}

protocol Searchable {
    func matches(query: String) -> [FuzzyFind.Alignment]
}

extension Searchable {
    func matches(query: String) -> [FuzzyFind.Alignment] {
        let mirror = Mirror(reflecting: self)
        let searchableText = mirror.children.compactMap { child -> String? in
            guard let value = child.value as? Search else { return nil }
            return value.wrappedValue
        }
        
        let matches = fuzzyFind(queries: [query], inputs: [searchableText.joined(separator: " ")])
        return matches
    }
}

extension Array where Element: Searchable {
    func search(query: String) -> [SortedSearchable<Element>] {
        var matches = self.compactMap { searchable -> SortedSearchable<Element>? in
            let matches = searchable.matches(query: query)
            if matches.isEmpty {
                return nil
            }
            return (searchable, matches)
        }
        
        matches.sort { a, b in
            let aScore = a.1.first!.score
            let bScore = b.1.first!.score

            return aScore > bScore
        }
        
        return matches
    }
}

struct ContactEditView: UIViewControllerRepresentable {
    var contactId: String
    @Environment(\.presentationMode) var presentationMode
    var onContactDeleted: (() -> Void)?

    func makeUIViewController(context: Context) -> CNContactViewController {
        if let contact = try? fetchContact(withIdentifier: contactId, keysToFetch: [CNContactViewController.descriptorForRequiredKeys()]) {
            let contactViewController = CNContactViewController(for: contact)
            contactViewController.delegate = context.coordinator
            return contactViewController
        }
        else {
            let contactViewController = CNContactViewController(forNewContact: nil)
            contactViewController.delegate = context.coordinator
            return contactViewController
        }
    }
    
    func updateUIViewController(_ uiViewController: CNContactViewController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CNContactViewControllerDelegate {
        var parent: ContactEditView
        
        init(_ parent: ContactEditView) {
            self.parent = parent
        }
        
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            parent.presentationMode.wrappedValue.dismiss()
            
            if contact == nil {
                parent.onContactDeleted?()
            }
        }
    }
}
