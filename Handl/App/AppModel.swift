import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading, signedOut, noHousehold, failed, ready
    }

    var phase: Phase = .loading
    var user: BackendUser?
    var household: Household?
    var services: [Service] = []
    var members: [Member] = []
    var errorMessage: String?
    var infoMessage: String?
    var isBusy = false

    let backend: Backend
    let isDemo: Bool

    init(backend: Backend? = nil) {
        if let backend {
            self.backend = backend
        } else if ProcessInfo.processInfo.arguments.contains("-HandlDemo") {
            self.backend = DemoBackend(startSignedIn: true)
        } else if let config = SupabaseConfig.load() {
            self.backend = SupabaseBackend(config: config)
        } else {
            // No Supabase config in this build — visible demo fallback.
            self.backend = DemoBackend(startSignedIn: true)
        }
        self.isDemo = self.backend.isDemo
    }

    // MARK: Lifecycle

    func start() async {
        phase = .loading
        user = await backend.restoreSession()
        guard user != nil else {
            phase = .signedOut
            return
        }
        await loadHousehold()
    }

    func loadHousehold() async {
        do {
            if let found = try await backend.myHousehold() {
                household = found
                services = try await backend.services(in: found.id)
                phase = .ready
            } else {
                household = nil
                services = []
                phase = .noHousehold
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    /// Foreground / pull-to-refresh: never surfaces errors, never flips phase.
    func refreshQuietly() async {
        guard phase == .ready, let household else { return }
        if let fresh = try? await backend.services(in: household.id) {
            services = fresh
        }
    }

    // MARK: Auth

    func signIn(email: String, password: String) async {
        await perform {
            self.user = try await self.backend.signIn(email: email, password: password)
            await self.loadHousehold()
        }
    }

    func signUp(email: String, password: String, name: String) async {
        await perform {
            let result = try await self.backend.signUp(
                email: email, password: password, displayName: name
            )
            switch result {
            case .signedIn(let user):
                self.user = user
                await self.loadHousehold()
            case .needsEmailConfirmation:
                self.infoMessage = String(localized: "Almost done! Open the confirmation email we sent you, then come back and sign in.")
            }
        }
    }

    func signOut() async {
        await backend.signOut()
        user = nil
        household = nil
        services = []
        members = []
        phase = .signedOut
    }

    // MARK: Household

    @discardableResult
    func createHousehold(name: String) async -> Bool {
        await perform {
            let created = try await self.backend.createHousehold(name: name)
            self.household = created
            self.services = []
            self.phase = .ready
        }
    }

    @discardableResult
    func joinHousehold(code: String) async -> Bool {
        await perform {
            let joined = try await self.backend.joinHousehold(
                code: code.trimmingCharacters(in: .whitespaces).uppercased()
            )
            self.household = joined
            self.services = try await self.backend.services(in: joined.id)
            self.phase = .ready
        }
    }

    @discardableResult
    func leaveHousehold() async -> Bool {
        guard let household else { return false }
        return await perform {
            try await self.backend.leaveHousehold(household.id)
            self.household = nil
            self.services = []
            self.members = []
            self.phase = .noHousehold
        }
    }

    func loadMembers() async {
        guard let household else { return }
        if let fresh = try? await backend.members(of: household.id) {
            members = fresh
        }
    }

    // MARK: Services

    @discardableResult
    func addService(name: String, category: ServiceCategory, phone: String,
                    whatsapp: Bool, notes: String, address: String) async -> Bool {
        guard let household else { return false }
        return await perform {
            let payload = ServicePayload(
                householdId: household.id,
                name: name,
                category: category.rawValue,
                phone: phone,
                whatsapp: whatsapp,
                notes: notes,
                address: address
            )
            let created = try await self.backend.addService(payload)
            self.services.append(created)
            self.sortServices()
        }
    }

    @discardableResult
    func updateService(id: UUID, name: String, category: ServiceCategory, phone: String,
                       whatsapp: Bool, notes: String, address: String) async -> Bool {
        await perform {
            let update = ServiceUpdate(
                name: name,
                category: category.rawValue,
                phone: phone,
                whatsapp: whatsapp,
                notes: notes,
                address: address
            )
            let updated = try await self.backend.updateService(id: id, update)
            if let index = self.services.firstIndex(where: { $0.id == id }) {
                self.services[index] = updated
            } else {
                self.services.append(updated)
            }
            self.sortServices()
        }
    }

    @discardableResult
    func deleteService(id: UUID) async -> Bool {
        await perform {
            try await self.backend.deleteService(id: id)
            self.services.removeAll { $0.id == id }
        }
    }

    // MARK: Profile

    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        await perform {
            try await self.backend.updateDisplayName(name)
            self.user?.displayName = name
        }
    }

    // MARK: Helpers

    private func sortServices() {
        services.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    private func perform(_ work: () async throws -> Void) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
