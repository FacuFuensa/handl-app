import Foundation

struct Household: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
    }
}

struct MemberProfile: Codable, Hashable, Sendable {
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct Member: Codable, Identifiable, Hashable, Sendable {
    let userId: UUID
    var profile: MemberProfile?

    var id: UUID { userId }
    var displayName: String {
        let name = profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? String(localized: "Member") : name
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profile
    }
}

enum ServiceCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case plumber, electrician, gas, ac, gardener, painter, locksmith
    case builder, cleaning, appliances, car, health, internet, other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceCategory(rawValue: raw) ?? .other
    }

    var symbol: String {
        switch self {
        case .plumber: "wrench.fill"
        case .electrician: "bolt.fill"
        case .gas: "flame.fill"
        case .ac: "snowflake"
        case .gardener: "leaf.fill"
        case .painter: "paintbrush.fill"
        case .locksmith: "key.fill"
        case .builder: "hammer.fill"
        case .cleaning: "sparkles"
        case .appliances: "refrigerator.fill"
        case .car: "car.fill"
        case .health: "cross.case.fill"
        case .internet: "wifi"
        case .other: "square.grid.2x2.fill"
        }
    }

    var label: String {
        switch self {
        case .plumber: String(localized: "Plumber")
        case .electrician: String(localized: "Electrician")
        case .gas: String(localized: "Gas")
        case .ac: String(localized: "Air conditioning")
        case .gardener: String(localized: "Garden")
        case .painter: String(localized: "Painter")
        case .locksmith: String(localized: "Locksmith")
        case .builder: String(localized: "Builder")
        case .cleaning: String(localized: "Cleaning")
        case .appliances: String(localized: "Appliances")
        case .car: String(localized: "Car")
        case .health: String(localized: "Health")
        case .internet: String(localized: "Internet & TV")
        case .other: String(localized: "Other")
        }
    }
}

struct Service: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var householdId: UUID
    var name: String
    var category: ServiceCategory
    var phone: String
    var whatsapp: Bool
    var notes: String
    var address: String

    enum CodingKeys: String, CodingKey {
        case id, name, category, phone, whatsapp, notes, address
        case householdId = "household_id"
    }

    /// Digits (plus a leading +) suitable for tel: links.
    var dialDigits: String {
        let allowed = Set("0123456789")
        var out = phone.hasPrefix("+") ? "+" : ""
        out += phone.filter { allowed.contains($0) }
        return out
    }

    /// wa.me requires digits only, no leading + or 00.
    var whatsappDigits: String {
        var d = phone.filter { $0.isNumber }
        if d.hasPrefix("00") { d.removeFirst(2) }
        return d
    }
}

struct ServicePayload: Codable, Sendable {
    var householdId: UUID
    var name: String
    var category: String
    var phone: String
    var whatsapp: Bool
    var notes: String
    var address: String

    enum CodingKeys: String, CodingKey {
        case name, category, phone, whatsapp, notes, address
        case householdId = "household_id"
    }
}

struct ServiceUpdate: Codable, Sendable {
    var name: String
    var category: String
    var phone: String
    var whatsapp: Bool
    var notes: String
    var address: String
}
