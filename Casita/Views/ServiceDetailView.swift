import SwiftUI

struct ServiceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let service: Service
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    /// The list can update underneath us (edits); always show the live copy.
    private var live: Service {
        model.services.first { $0.id == service.id } ?? service
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CategoryBadge(category: live.category, size: 84)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text(live.name)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(live.category.label)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                }

                if !live.phone.isEmpty {
                    Text(live.phone)
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }

                VStack(spacing: 12) {
                    if !live.dialDigits.isEmpty {
                        BigButton(title: "Call", systemImage: "phone.fill", color: Theme.callGreen) {
                            if let url = URL(string: "tel:\(live.dialDigits)") {
                                openURL(url)
                            }
                        }
                    }
                    if live.whatsapp && !live.whatsappDigits.isEmpty {
                        BigButton(title: "WhatsApp", systemImage: "message.fill", color: Theme.whatsappTeal) {
                            if let url = URL(string: "https://wa.me/\(live.whatsappDigits)") {
                                openURL(url)
                            }
                        }
                    }
                }

                if !live.address.isEmpty {
                    infoCard(title: "Address", systemImage: "mappin.and.ellipse", text: live.address)
                }
                if !live.notes.isEmpty {
                    infoCard(title: "Notes", systemImage: "note.text", text: live.notes)
                }

                if let error = model.errorMessage {
                    InlineMessage(kind: .error, text: error)
                }

                Button {
                    confirmingDelete = true
                } label: {
                    if model.isBusy {
                        ProgressView()
                            .frame(minHeight: 44)
                    } else {
                        Text("Delete service")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.danger)
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
                .padding(.top, 16)
            }
            .padding(20)
            .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onAppear { model.errorMessage = nil }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
                    .font(.body.weight(.semibold))
            }
        }
        .sheet(isPresented: $showingEdit) { ServiceFormView(mode: .edit(live)) }
        .confirmationDialog(
            Text("Delete this service?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.deleteService(id: live.id) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func infoCard(title: LocalizedStringKey, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            } icon: {
                Image(systemName: systemImage)
            }
            .foregroundStyle(Theme.inkSecondary)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.08))
        )
    }
}
