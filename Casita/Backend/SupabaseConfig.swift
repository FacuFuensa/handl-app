import Foundation

struct SupabaseConfig: Sendable {
    let url: URL
    let anonKey: String

    /// Values arrive via Info.plist keys populated from the SUPABASE_URL /
    /// SUPABASE_ANON_KEY build settings (passed on the xcodebuild command line
    /// in CI). Empty in local/simulator builds — the app then runs DemoBackend.
    static func load() -> SupabaseConfig? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !urlString.isEmpty, !key.isEmpty,
            let url = URL(string: urlString)
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
