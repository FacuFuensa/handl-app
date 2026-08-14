import Foundation

/// Seeded in-memory backend. Used by SwiftUI previews, CI screenshot runs
/// (-CasitaDemo launch argument) and as the fallback when a build ships
/// without Supabase configuration (a "Demo" banner makes that state visible).
actor DemoBackend: Backend {
    nonisolated let isDemo = true

    static let household = Household(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Our Home",
        inviteCode: "CASA42"
    )

    static let user = BackendUser(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        email: "tony@example.com",
        displayName: "Tony"
    )

    static let seedMembers: [Member] = [
        Member(userId: user.id, profile: MemberProfile(displayName: "Tony")),
        Member(
            userId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            profile: MemberProfile(displayName: "Carol")
        ),
    ]

    static let seedServices: [Service] = [
        demoService("Ray's Plumbing", .plumber, "+1 555 210 4433", "Fixed the bathroom leak in March. Cash only."),
        demoService("North Electric Co.", .electrician, "+1 555 210 5544", "Ask for Marcus."),
        demoService("Omar — Gas Fitter", .gas, "+1 555 210 6655", "Installed the living room heater. Licensed."),
        demoService("Bert's Gardening", .gardener, "+1 555 210 7766", "Comes every other Tuesday."),
        demoService("Cool Air Service", .ac, "+1 555 210 8877", "AC tune-up every spring."),
        demoService("KeyPro 24h Locksmith", .locksmith, "+1 555 210 9988", "They answer at night too."),
        demoService("Dr. Pace — Family Clinic", .health, "+1 555 210 1199", "Appointments by phone, 9 to 1."),
    ]

    private static func demoService(
        _ name: String, _ category: ServiceCategory, _ phone: String, _ notes: String
    ) -> Service {
        Service(
            id: UUID(),
            householdId: household.id,
            name: name,
            category: category,
            phone: phone,
            whatsapp: true,
            notes: notes,
            address: ""
        )
    }

    private var currentUser: BackendUser?
    private var storedHousehold: Household?
    private var storedServices: [Service]
    private var storedMembers: [Member]

    /// startSignedIn: true simulates a restored session (screenshots, fallback
    /// builds); false starts at the auth screen.
    init(startSignedIn: Bool = true) {
        currentUser = startSignedIn ? Self.user : nil
        storedHousehold = Self.household
        storedServices = Self.seedServices
        storedMembers = Self.seedMembers
    }

    func restoreSession() async -> BackendUser? { currentUser }

    func signUp(email: String, password: String, displayName: String) async throws -> SignUpResult {
        let user = BackendUser(id: UUID(), email: email, displayName: displayName)
        currentUser = user
        storedHousehold = nil
        return .signedIn(user)
    }

    func signIn(email: String, password: String) async throws -> BackendUser {
        let user = BackendUser(id: Self.user.id, email: email, displayName: Self.user.displayName)
        currentUser = user
        return user
    }

    func signOut() async { currentUser = nil }

    func myHousehold() async throws -> Household? { storedHousehold }

    func createHousehold(name: String) async throws -> Household {
        let new = Household(id: UUID(), name: name, inviteCode: "CASA42")
        storedHousehold = new
        storedServices = []
        storedMembers = [
            Member(
                userId: currentUser?.id ?? UUID(),
                profile: MemberProfile(displayName: currentUser?.displayName ?? "")
            )
        ]
        return new
    }

    func joinHousehold(code: String) async throws -> Household {
        guard code.uppercased() == Self.household.inviteCode else {
            throw BackendError.friendly(String(localized: "No household found with that code. Check it and try again."))
        }
        storedHousehold = Self.household
        storedServices = Self.seedServices
        storedMembers = Self.seedMembers
        return Self.household
    }

    func leaveHousehold(_ householdId: UUID) async throws {
        storedHousehold = nil
        storedServices = []
    }

    func members(of householdId: UUID) async throws -> [Member] { storedMembers }

    func services(in householdId: UUID) async throws -> [Service] {
        storedServices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addService(_ payload: ServicePayload) async throws -> Service {
        let service = Service(
            id: UUID(),
            householdId: payload.householdId,
            name: payload.name,
            category: ServiceCategory(rawValue: payload.category) ?? .other,
            phone: payload.phone,
            whatsapp: payload.whatsapp,
            notes: payload.notes,
            address: payload.address
        )
        storedServices.append(service)
        return service
    }

    func updateService(id: UUID, _ update: ServiceUpdate) async throws -> Service {
        guard let index = storedServices.firstIndex(where: { $0.id == id }) else {
            throw BackendError.friendly(String(localized: "That service no longer exists."))
        }
        var service = storedServices[index]
        service.name = update.name
        service.category = ServiceCategory(rawValue: update.category) ?? .other
        service.phone = update.phone
        service.whatsapp = update.whatsapp
        service.notes = update.notes
        service.address = update.address
        storedServices[index] = service
        return service
    }

    func deleteService(id: UUID) async throws {
        storedServices.removeAll { $0.id == id }
    }

    func updateDisplayName(_ name: String) async throws {
        currentUser?.displayName = name
    }
}
