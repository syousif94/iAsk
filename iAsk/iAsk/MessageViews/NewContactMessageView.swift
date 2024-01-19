//
//  NewContactMessageView.swift
//  iAsk
//
//  Created by Sammy Yousif on 1/10/24.
//

import SwiftUI
import Contacts
import SwiftyContacts

struct NewContactMessageView: View {
    
    var message: Message
    
    @Environment(\.colorScheme) var colorScheme
    
    @State var showContactView = false
    @State var contactId: String? = nil
    
    @State var showCreateContactAlert = false
    
    @State var showDeleteContactAlert = false
    
    @State var answering: Bool = true
    
    @State var name: String = ""
    @State var number: String = ""
    @State var email: String = ""
    @State var employer: String = ""
    
    enum JsonKeys: String, CaseIterable {
        case name
        case number
        case email
        case employer
    }
    
    func showEditContact() {
        Task {
            if let id = message.systemIdentifier {
                if let contact = await ContactManager.shared.loadContact(by: id) {
                    DispatchQueue.main.async {
                        self.contactId = contact.identifier
                        self.showContactView = true
                    }
                }
                else {
                    print("could not find contact")
                    DispatchQueue.main.async {
                        self.showCreateContactAlert = true
                    }
                }
            }
        }
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 20) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 32))
                    .padding(.leading)
                    
                VStack(alignment: .leading, spacing: 0) {
                    if !name.isEmpty {
                        Text(name)
                            .font(.headline)
                    }
                    
                    if !employer.isEmpty {
                        Text(employer)
                            .padding(.top, 2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !number.isEmpty {
                        Text(number)
                            .padding(.top, 2)
                    }
                    if !email.isEmpty {
                        Text(email)
                            .padding(.top, 2)
                    }
                    
                    
                }
                .alert(isPresented: $showCreateContactAlert) {
                    Alert(
                        title: Text("This contact does not exist."),
                        message: Text("Do you want to create it?"),
                        primaryButton: .default(Text("Yes")) {
                            Task {
                                let call = FunctionCallResponse()
                                call.name = message.record.functionCallName!
                                call.arguments = message.record.functionCallArgs!
                                
                                if let args = try? call.toArgs(CreateNewContactArgs.self),
                                   let contact = await ContactManager.shared.createContact(from: args)
                                {
                                    do {
                                        try ContactManager.shared.save(contact: contact)
                                        message.systemIdentifier = contact.identifier
                                        await message.save()
                                        DispatchQueue.main.async {
                                            print(contact)
                                            self.contactId = contact.identifier
                                            self.showContactView = true
                                        }
                                    }
                                    catch {
                                        
                                    }
                                }
                            }
                        },
                        secondaryButton: .cancel() {
                            
                        }
                    )
                }
            }
            .padding()
            .padding(.trailing)
            .background(Color(hex:"#000000", alpha: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                showEditContact()
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom)
        .onReceive(message.$content.debounce(for: 0.016, scheduler: DispatchQueue.main)) { text in
            for key in JsonKeys.allCases {
                if let extracted = extractJSONValue(from: String(text), forKey: key.rawValue) {
                    switch key {
                    case .name:
                        self.name = extracted
                    case .number:
                        self.number = extracted
                    case .email:
                        self.email = extracted
                    case .employer:
                        self.employer = extracted
                    }
                }
            }
        }
        .sheet(isPresented: $showContactView) {
            NavigationStack {
                ContactSheetView(contactId: $contactId)
                    .toolbar(content: {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button(action: {
                                showDeleteContactAlert = true
                            }) {
                                Text("Delete")
                                    .foregroundStyle(.red)
                            }
                            Spacer()
                            Button("Done") {
                                showContactView = false
                            }
                        }
                    })
                    .alert(isPresented: $showDeleteContactAlert) {
                        Alert(
                            title: Text("Delete this contact?"),
                            primaryButton: .destructive(Text("Yes"),
                                                        action: {
                                                            showContactView = false
                                                            if let contactId = contactId,
                                                               let contact = try? fetchContact(withIdentifier: contactId) {
                                                                try? deleteContact(contact)
                                                            }
                                                        }),
                            secondaryButton: .cancel() {
                                
                            }
                        )
                    }
            }
        }
    }
}

struct ContactSheetView: View {
    @Binding var contactId: String?
    
    var body: some View {
        if let contactId = contactId {
            ContactEditView(contactId: contactId)
        }
    }
}
