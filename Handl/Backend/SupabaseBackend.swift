import Foundation
import Supabase

final class SupabaseBackend: Backend {
    let isDemo = false
    private let client: SupabaseClient

    init(config: SupabaseConfig) {
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }

    // MARK: Auth

    func restoreSession() async -> BackendUser? {
        guard let session = try? await client.auth.session else { return nil }
        return await backendUser(from: session.user)
    }

    func signUp(email: String, password: String, displayName: String) async throws -> SignUpResult {
        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            guard let session = response.session else { return .needsEmailConfirmation }
            return .signedIn(await backendUser(from: session.user))
        } catch {
            throw Self.friendly(error)
        }
    }

    func signIn(email: String, password: String) async throws -> BackendUser {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            return await backendUser(from: session.user)
        } catch {
            throw Self.friendly(error)
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    private func backendUser(from user: User) async -> BackendUser {
        let name = (try? await fetchDisplayName(user.id)) ?? ""
        return BackendUser(id: user.id, email: user.email, displayName: name)
    }

    private func fetchDisplayName(_ id: UUID) async throws -> String {
        struct Row: Decodable { let display_name: String }
        let row: Row = try await client.from("profiles")
            .select("display_name")
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return row.display_name
    }

    // MARK: Household

    func myHousehold() async throws -> Household? {
        let rows: [Household] = try await client.rpc("my_household").execute().value
        return rows.first
    }

    func createHousehold(name: String) async throws -> Household {
        let rows: [Household] = try await client
            .rpc("create_household", params: ["p_name": name])
            .execute()
            .value
        guard let household = rows.first else {
            throw BackendError.friendly(String(localized: "Could not create the household. Try again."))
        }
        return household
    }

    func joinHousehold(code: String) async throws -> Household {
        let rows: [Household]
        do {
            rows = try await client
                .rpc("join_household", params: ["p_code": code])
                .execute()
                .value
        } catch {
            throw Self.friendly(error)
        }
        guard let household = rows.first else {
            throw BackendError.friendly(String(localized: "No household found with that code. Check it and try again."))
        }
        return household
    }

    func leaveHousehold(_ householdId: UUID) async throws {
        let uid = try await client.auth.session.user.id
        try await client.from("household_members")
            .delete()
            .eq("household_id", value: householdId)
            .eq("user_id", value: uid)
            .execute()
    }

    func members(of householdId: UUID) async throws -> [Member] {
        try await client.from("household_members")
            .select("user_id, profile:profiles(display_name)")
            .eq("household_id", value: householdId)
            .execute()
            .value
    }

    // MARK: Services

    func services(in householdId: UUID) async throws -> [Service] {
        try await client.from("services")
            .select()
            .eq("household_id", value: householdId)
            .order("name")
            .execute()
            .value
    }

    func addService(_ payload: ServicePayload) async throws -> Service {
        try await client.from("services")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateService(id: UUID, _ update: ServiceUpdate) async throws -> Service {
        try await client.from("services")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteService(id: UUID) async throws {
        try await client.from("services")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: Profile

    func updateDisplayName(_ name: String) async throws {
        let uid = try await client.auth.session.user.id
        struct Patch: Encodable { let display_name: String }
        try await client.from("profiles")
            .update(Patch(display_name: name))
            .eq("id", value: uid)
            .execute()
    }

    // MARK: Error mapping

    private static func friendly(_ error: Error) -> Error {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return BackendError.friendly(String(localized: "Wrong email or password."))
            case .userAlreadyExists, .emailExists:
                return BackendError.friendly(String(localized: "There is already an account with that email. Try signing in."))
            case .weakPassword:
                return BackendError.friendly(String(localized: "The password is too short. Use at least 6 characters."))
            case .validationFailed:
                return BackendError.friendly(String(localized: "That email address doesn't look right."))
            default:
                return BackendError.friendly(authError.message)
            }
        }
        if (error as? URLError) != nil {
            return BackendError.friendly(String(localized: "No connection. Check your internet and try again."))
        }
        return error
    }
}
