import Contacts
import ContactsUI
import SwiftUI

/// The system contact picker, wrapped for SwiftUI.
///
/// The picker runs in a separate process: the app never requests Contacts
/// permission, never sees the address book, and only receives the one number
/// the user tapped. That is why there is no `CNContactStore` anywhere here.
///
/// Attach it as a `.background(...)` of the presenting view so its host
/// controller is inside the window hierarchy — presenting from a detached
/// controller silently fails. Presenting a UIKit modal this way (rather than
/// putting the picker inside a SwiftUI `.sheet`) also avoids the reported
/// sheet-inside-a-sheet bug where dismissing the picker takes the parent
/// form down with it.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// Called with the contact's display name and the phone number tapped.
    var onPick: (String, String) -> Void

    /// Every key we intend to READ must be listed. `displayedPropertyKeys`
    /// decides both what the contact card shows *and* which keys are fetched
    /// on the contact handed back. Reading an unfetched key raises
    /// CNPropertyNotFetchedException — an Objective-C exception Swift cannot
    /// catch, so it is a hard crash, and it only reproduces on a device with
    /// real contacts.
    private static let keys: [String] = [
        CNContactPhoneNumbersKey,
        CNContactGivenNameKey,
        CNContactMiddleNameKey,
        CNContactFamilyNameKey,
        CNContactNamePrefixKey,
        CNContactNameSuffixKey,
        CNContactNicknameKey,
        CNContactOrganizationNameKey,
    ]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        // Keep the coordinator's closures fresh; SwiftUI rebuilds this struct
        // on every state change but the coordinator is created once.
        let dismiss: () -> Void = { isPresented = false }
        context.coordinator.onPick = onPick
        context.coordinator.onFinish = dismiss

        guard isPresented, !context.coordinator.isShowing else { return }
        context.coordinator.isShowing = true

        // Apple: predicates only take effect before the picker is presented.
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = Self.keys
        // false → never return the whole contact, open its card instead, so
        // the user always sees which number they are choosing. People commonly
        // have a mobile and a landline saved together.
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        // Only a phone row comes back through the delegate. Built from the SDK
        // constant rather than a literal: much community code writes the
        // singular 'phoneNumber', which never matches and silently falls back
        // to the default behaviour.
        picker.predicateForSelectionOfProperty = NSPredicate(
            format: "key == %@", CNContactPhoneNumbersKey
        )
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // Swiping the sheet down fires no picker delegate callback at all —
        // contactPickerDidCancel is only sent when Cancel is tapped. Without
        // this the latch below stays set and the button never opens again.
        picker.presentationController?.delegate = context.coordinator

        // The host may not be in the window yet on the first layout pass.
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard host.view.window != nil else {
                coordinator.isShowing = false
                dismiss()
                return
            }
            host.present(picker, animated: true)
        }
    }

    /// Only the single-property callback is implemented on purpose: adding
    /// either plural variant silently switches the picker to multi-select.
    final class Coordinator: NSObject, CNContactPickerDelegate,
                             UIAdaptivePresentationControllerDelegate {
        var onPick: (String, String) -> Void = { _, _ in }
        var onFinish: () -> Void = {}
        var isShowing = false

        /// The picker dismisses itself; dismissing it here too breaks it.
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            finish()
        }

        /// Sent when the sheet is swiped away instead of cancelled.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finish()
        }

        func contactPicker(
            _ picker: CNContactPickerViewController,
            didSelect contactProperty: CNContactProperty
        ) {
            guard let phone = (contactProperty.value as? CNPhoneNumber)?.stringValue,
                  !phone.isEmpty
            else {
                finish()
                return
            }
            onPick(Self.displayName(for: contactProperty.contact), phone)
            finish()
        }

        private func finish() {
            isShowing = false
            onFinish()
        }

        /// Every read is gated on the key actually having been fetched.
        /// Falls back to the company name, which is how a plumber is often
        /// saved in the first place.
        static func displayName(for contact: CNContact) -> String {
            let descriptor = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
            if contact.areKeysAvailable([descriptor]),
               let formatted = CNContactFormatter.string(from: contact, style: .fullName),
               !formatted.isEmpty {
                return formatted
            }

            var parts: [String] = []
            if contact.isKeyAvailable(CNContactGivenNameKey) { parts.append(contact.givenName) }
            if contact.isKeyAvailable(CNContactFamilyNameKey) { parts.append(contact.familyName) }
            let personal = parts.filter { !$0.isEmpty }.joined(separator: " ")
            if !personal.isEmpty { return personal }

            if contact.isKeyAvailable(CNContactOrganizationNameKey),
               !contact.organizationName.isEmpty {
                return contact.organizationName
            }
            return ""
        }
    }
}
