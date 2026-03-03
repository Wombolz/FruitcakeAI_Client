//
//  ContactsTool.swift
//  FruitcakeAi
//
//  On-device FoundationModels tool for looking up Apple Contacts.
//  Used by OnDeviceAgent when the backend is unreachable.
//  Requires NSContactsUsageDescription in Info.plist.
//

import Foundation
import FoundationModels
import Contacts

@available(macOS 26.0, iOS 26.0, *)
struct ContactsTool: Tool {

    let name = "lookupContact"
    let description = "Look up a person's phone number, email address, or other contact info from Apple Contacts. Use when the user asks about a person's contact details."

    @Generable
    struct Arguments {
        @Guide(description: "Full or partial name of the person to look up (e.g. 'John', 'Sarah Smith')")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        let store = CNContactStore()

        // Request permission
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else {
            return "Contacts access was denied. Please grant access in Settings > Privacy & Security > Contacts."
        }

        let query = arguments.name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return "Please provide a name to search for."
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)

        let contacts: [CNContact]
        do {
            contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        } catch {
            return "Could not search contacts: \(error.localizedDescription)"
        }

        if contacts.isEmpty {
            return "No contacts found matching \"\(query)\"."
        }

        let lines = contacts.map { contact -> String in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let org   = contact.organizationName.isEmpty ? "" : "  (\(contact.organizationName))"
            let phones = contact.phoneNumbers
                .map { "\($0.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? ""): \($0.value.stringValue)" }
                .joined(separator: ", ")
            let emails = contact.emailAddresses
                .map { "\($0.value as String)" }
                .joined(separator: ", ")

            var parts = ["\(name)\(org)"]
            if !phones.isEmpty { parts.append("📞 \(phones)") }
            if !emails.isEmpty { parts.append("✉️ \(emails)") }
            return parts.joined(separator: "\n  ")
        }

        return "Found \(contacts.count) contact\(contacts.count == 1 ? "" : "s"):\n\n" +
               lines.joined(separator: "\n\n")
    }
}
