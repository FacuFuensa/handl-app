import SwiftUI

struct ServiceFormView: View {
    enum Mode {
        case add
        case edit(Service)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    @State private var name: String
    @State private var category: ServiceCategory
    @State private var phone: String
    @State private var whatsapp: Bool
    @State private var notes: String
    @State private var address: String

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _category = State(initialValue: .plumber)
            _phone = State(initialValue: "")
            _whatsapp = State(initialValue: true)
            _notes = State(initialValue: "")
            _address = State(initialValue: "")
        case .edit(let service):
            _name = State(initialValue: service.name)
            _category = State(initialValue: service.category)
            _phone = State(initialValue: service.phone)
            _whatsapp = State(initialValue: service.whatsapp)
            _notes = State(initialValue: service.notes)
            _address = State(initialValue: service.address)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name — e.g. Raúl the plumber", text: $name)
                        .font(.body)
                } header: {
                    Text("Who is it?")
                }

                Section {
                    categoryGrid
                } header: {
                    Text("Category")
                }

                Section {
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.body)
                    Toggle("They use WhatsApp", isOn: $whatsapp)
                } header: {
                    Text("Phone")
                } footer: {
                    Text("Include the country code so WhatsApp works, e.g. +54 11 5555 1234")
                }

                Section {
                    TextField("Address (optional)", text: $address)
                        .font(.body)
                    TextField("Notes (optional) — prices, schedules, who recommended them…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                } header: {
                    Text("More details")
                }

                if let error = model.errorMessage {
                    Section {
                        InlineMessage(kind: .error, text: error)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onAppear { model.errorMessage = nil }
            .navigationTitle(isEditing ? "Edit service" : "New service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isBusy {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .font(.body.weight(.semibold))
                        .disabled(!canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
            ForEach(ServiceCategory.allCases) { option in
                Button {
                    category = option
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                        Text(option.label)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .foregroundStyle(category == option ? .white : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(category == option ? Theme.terracottaFill : Theme.terracotta.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == option ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)

        let success: Bool
        switch mode {
        case .add:
            success = await model.addService(
                name: trimmedName, category: category, phone: trimmedPhone,
                whatsapp: whatsapp, notes: trimmedNotes, address: trimmedAddress
            )
        case .edit(let service):
            success = await model.updateService(
                id: service.id, name: trimmedName, category: category, phone: trimmedPhone,
                whatsapp: whatsapp, notes: trimmedNotes, address: trimmedAddress
            )
        }
        if success {
            dismiss()
        }
    }
}
