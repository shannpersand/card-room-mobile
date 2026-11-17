import Foundation

/// Wraps an optional value so Swift's synthesized `Encodable` never silently omits it.
///
/// Supabase's PostgREST PATCH endpoint treats an **absent** JSON key as "don't touch this
/// column" but an explicit JSON `null` as "set it to NULL" — and Swift's default `Encodable`
/// synthesis for a plain `T?` property always omits the key when the value is `nil` (confirmed
/// directly: `JSONEncoder().encode(Wrapper(x: nil as String?))` produces `{}`, not
/// `{"x":null}`). Every update struct in this app whose `nil` is meant to clear a nullable
/// column (`current_turn`, `golf_knocked_by`, …) must use this instead of a bare `T?`, or the
/// write silently no-ops and the column keeps its stale previous value. Found via a real bug:
/// `GolfService.endTurn`'s round-reveal (`current_turn: nil`) never actually took effect.
struct NullableField<T: Encodable>: Encodable {
    let value: T?

    init(_ value: T?) { self.value = value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}
