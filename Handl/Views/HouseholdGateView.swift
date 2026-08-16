import SwiftUI

/// Shown after sign-in when the user doesn't belong to a household yet:
/// create one, or join with the code a family member shared.
struct HouseholdGateView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCreate = false
    @State private var showingJoin = false
    @State private var confirmingSignOut = false

    private var greeting: Text {
        let name = model.user?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? Text("Hi!") : Text("Hi, \(name)")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    greeting
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("A household is where your family keeps its services and phone numbers. Create one, or join the one your family already made.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)

                optionCard(
                    symbol: "plus.circle.fill",
                    title: "Create a household",
                    subtitle: "Start fresh and invite your family with a code"
                ) {
                    showingCreate = true
                }

                optionCard(
                    symbol: "person.2.fill",
                    title: "Join with a code",
                    subtitle: "Type the 6-letter code someone shared with you"
                ) {
                    showingJoin = true
                }

                if model.isDemo {
                    DemoBanner()
                }

                Button {
                    confirmingSignOut = true
                } label: {
                    Text("Sign out")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingCreate) { CreateHouseholdSheet() }
        .sheet(isPresented: $showingJoin) { JoinHouseholdSheet() }
        .confirmationDialog(
            Text("Sign out of Handl?"),
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await model.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func optionCard(
        symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(Theme.terracotta)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Theme.terracotta.opacity(0.14)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

struct CreateHouseholdSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Give your household a name. Anything works — you can change it later.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                TextField("Home", text: $name)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(0.1))
                    )

                if let error = model.errorMessage {
                    InlineMessage(kind: .error, text: error)
                }

                if model.isBusy {
                    ProgressView()
                        .frame(minHeight: 56)
                } else {
                    BigButton(title: "Create household", systemImage: "house.fill") {
                        Task {
                            let finalName = name.trimmingCharacters(in: .whitespaces)
                            if await model.createHousehold(name: finalName.isEmpty ? String(localized: "Home") : finalName) {
                                dismiss()
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.background.ignoresSafeArea())
            .onAppear { model.errorMessage = nil }
            .navigationTitle("New household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct JoinHouseholdSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Ask your family member for the household code and type it here.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                TextField("CODE", text: $code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(minHeight: 64)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.ink.opacity(0.1))
                    )
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    }

                if let error = model.errorMessage {
                    InlineMessage(kind: .error, text: error)
                }

                if model.isBusy {
                    ProgressView()
                        .frame(minHeight: 56)
                } else {
                    BigButton(title: "Join household", systemImage: "person.2.fill") {
                        Task {
                            if await model.joinHousehold(code: code) {
                                dismiss()
                            }
                        }
                    }
                    .opacity(code.count == 6 ? 1 : 0.4)
                    .disabled(code.count != 6)
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.background.ignoresSafeArea())
            .onAppear { model.errorMessage = nil }
            .navigationTitle("Join household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
