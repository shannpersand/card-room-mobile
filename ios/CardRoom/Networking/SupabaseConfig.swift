import Foundation
import Supabase

/// Same Supabase project as the card-room web app (see its `.env`) — this app reads/writes the
/// exact same `rooms`/`players` rows, so a room code works interchangeably across both clients.
///
/// The anon/publishable key is meant to be embedded in client code (it's what the web app's
/// JS bundle already ships publicly); row-level security on the `rooms`/`players` tables is
/// what actually controls access, not secrecy of this key.
enum SupabaseConfig {
    static let url = URL(string: "https://wsrvsiyapvvsqxamooor.supabase.co")!
    static let anonKey = "sb_publishable_jHg3X0HjyY6z7cNV9315QQ_GggR11MT"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)
