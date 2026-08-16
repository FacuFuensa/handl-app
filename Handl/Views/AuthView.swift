import SwiftUI

struct AuthView: View {
    private enum Mode { case signIn, signUp }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var canSubmit: Bool {
        guard trimmedEmail.contains("@"), trimmedEmail.contains("."), password.count >= 6 else {
            return false
        }
        if mode == .signUp {
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 14) {
                    if mode == .signUp {
                        field {
                            TextField("Your name", text: $name)
                                .textContentType(.name)
                        }
                    }
                    field {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    field {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }

                if let error = model.errorMessage {
                    InlineMessage(kind: .error, text: error)
                }
                if let info = model.infoMessage {
                    InlineMessage(kind: .info, text: info)
                }

                if model.isBusy {
                    ProgressView()
                        .frame(minHeight: 56)
                } else {
                    BigButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        systemImage: mode == .signIn ? "arrow.right.circle.fill" : "person.badge.plus"
                    ) {
                        Task { await submit() }
                    }
                    .opacity(canSubmit ? 1 : 0.4)
                    .disabled(!canSubmit)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = mode == .signIn ? .signUp : .signIn
                        model.errorMessage = nil
                        model.infoMessage = nil
                    }
                } label: {
                    Text(mode == .signIn ? "Don't have an account? Create one" : "Already have an account? Sign in")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.terracotta)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                if model.isDemo {
                    DemoBanner()
                }
            }
            .padding(24)
            .frame(maxWidth: 500)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Theme.terracottaFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .accessibilityHidden(true)
            Text("Handl")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Your home's services and phone numbers, shared with your family")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    private func field(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.1))
            )
    }

    private func submit() async {
        switch mode {
        case .signIn:
            await model.signIn(email: trimmedEmail, password: password)
        case .signUp:
            await model.signUp(
                email: trimmedEmail,
                password: password,
                name: name.trimmingCharacters(in: .whitespaces)
            )
        }
    }
}
