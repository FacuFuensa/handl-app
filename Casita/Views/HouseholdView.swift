import SwiftUI

struct HouseholdView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingLeave = false

    private var inviteMessage: String {
        String(localized: "Join our home in Casita! Household code: \(model.household?.inviteCode ?? "")")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Text("Share this code with your family so they can join:")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Text(model.household?.inviteCode ?? "")
                            .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.terracotta)
                            .frame(maxWidth: .infinity)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Household code"))

                        ShareLink(item: inviteMessage) {
                            HStack(spacing: 10) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.headline)
                                Text("Share code")
                                    .font(.system(.headline, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .background(Theme.terracottaFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Theme.card)
                } header: {
                    Text("Invite your family")
                }

                Section {
                    ForEach(model.members) { member in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundStyle(Theme.terracotta)
                            Text(member.displayName)
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(Theme.ink)
                            if member.userId == model.user?.id {
                                Text("You")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.ink.opacity(0.08)))
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    Text("Members")
                }

                Section {
                    if let error = model.errorMessage {
                        InlineMessage(kind: .error, text: error)
                            .listRowBackground(Color.clear)
                    }
                    Button {
                        confirmingLeave = true
                    } label: {
                        if model.isBusy {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Text("Leave household")
                                .foregroundStyle(Theme.danger)
                                .frame(minHeight: 44)
                        }
                    }
                    .disabled(model.isBusy)
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onAppear { model.errorMessage = nil }
            .navigationTitle(model.household?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .task { await model.loadMembers() }
            .confirmationDialog(
                Text("Leave this household? You can rejoin later with the code."),
                isPresented: $confirmingLeave,
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    Task {
                        if await model.leaveHousehold() {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
