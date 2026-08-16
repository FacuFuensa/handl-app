import Foundation

struct BackendUser: Sendable, Equatable {
    let id: UUID
    let email: String?
    var displayName: String
}

enum SignUpResult: Sendable {
    case signedIn(BackendUser)
    case needsEmailConfirmation
}

enum BackendError: LocalizedError {
    case friendly(String)

    var errorDescription: String? {
        switch self {
        case .friendly(let message): message
        }
    }
}

/// Every remote operation the app needs. `SupabaseBackend` talks to the real
/// project; `DemoBackend` is seeded in-memory data for previews, CI
/// screenshots, and unconfigured builds.
protocol Backend: Sendable {
    var isDemo: Bool { get }

    func restoreSession() async -> BackendUser?
    func signUp(email: String, password: String, displayName: String) async throws -> SignUpResult
    func signIn(email: String, password: String) async throws -> BackendUser
    func signOut() async

    func myHousehold() async throws -> Household?
    func createHousehold(name: String) async throws -> Household
    func joinHousehold(code: String) async throws -> Household
    func leaveHousehold(_ householdId: UUID) async throws
    func members(of householdId: UUID) async throws -> [Member]

    func services(in householdId: UUID) async throws -> [Service]
    func addService(_ payload: ServicePayload) async throws -> Service
    func updateService(id: UUID, _ update: ServiceUpdate) async throws -> Service
    func deleteService(id: UUID) async throws

    func updateDisplayName(_ name: String) async throws
}
