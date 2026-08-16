import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var confirmingSignOut = false
    @State private var savedName = false

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .font(.body)
                    Button {
                        Task {
                            savedName = await model.updateDisplayName(
                                displayName.trimmingCharacters(in: .whitespaces)
                            )
                        }
                    } label: {
                        if model.isBusy {
                            ProgressView()
                        } else if savedName {
                            Label {
                                Text("Saved")
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                            .foregroundStyle(Theme.callGreen)
                        } else {
                            Text("Save name")
                                .foregroundStyle(Theme.terracotta)
                        }
                    }
                    .disabled(model.isBusy || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("This is how your family sees you in the household.")
                }

                Section {
                    LabeledContent {
                        Text(model.user?.email ?? "")
                    } label: {
                        Text("Email")
                    }
                    Button {
                        confirmingSignOut = true
                    } label: {
                        Text("Sign out")
                            .foregroundStyle(Theme.danger)
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Account")
                }

                if let error = model.errorMessage {
                    Section {
                        InlineMessage(kind: .error, text: error)
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                } footer: {
                    Text("Handl \(appVersion)")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                displayName = model.user?.displayName ?? ""
                model.errorMessage = nil
            }
            .onChange(of: displayName) { _, _ in
                savedName = false
            }
            .confirmationDialog(
                Text("Sign out of Handl?"),
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await model.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
