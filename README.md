# Card Room — Mobile

Fully native iOS (Swift/SwiftUI) and Android (Kotlin, planned) companion apps for
[card-room](../card-room), the web app. Both clients talk to the **same Supabase project**
directly — a room created on the web app can be joined from here by its 4-character code, and
vice versa, since they all just read/write the same `rooms`/`players` tables.

This is a sibling repo to `card-room`, not a folder inside it — separate git history, separate
toolchains (Xcode/Gradle vs. Vite), but built against the exact same backend schema.

## Why fully native (not Capacitor/React Native)

`card-room` already ships a Capacitor-wrapped build of its web app for exactly this purpose.
This project is a *second*, independent path: real SwiftUI/Jetpack Compose UIs with no webview,
chosen deliberately over reusing the web app's code for the native feel/performance tradeoff —
see the card-room `TODO.md` for that discussion if it's still there.

## iOS

### Prerequisites
- **Full Xcode** (not just the Command Line Tools) from the App Store — needed to build,
  run in the simulator, or even generate the `.xcodeproj` itself.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen` (this also
  requires full Xcode to be installed first).

### First-time setup
```sh
cd ios
xcodegen generate
open CardRoom.xcodeproj
```
`CardRoom.xcodeproj` is generated from `project.yml` and is gitignored — never edit it by hand;
edit `project.yml` and re-run `xcodegen generate` instead (do this again any time you add a new
source file folder, change the bundle id, or add a dependency).

### What's here so far
A full, playable Blackjack round-trip: join a room created on the web app (or vice versa), see
the live player list in a Lobby screen, have the dealer deal, and play Hit/Stand turns with
realtime sync — verified end-to-end against the real Supabase project (see "How this was
verified" below), not just that it compiles.

- `Models/` — `Card`, `Player`, `Room`, `GeneratedGameConfig`, `SavedGame`: Swift structs that
  mirror `card-room/src/types.ts` field-for-field, so they decode the exact JSON shape already
  sitting in Supabase. **Keep these in sync by hand** if the web app's schema changes — there's
  no shared source of truth between the TypeScript and Swift definitions. One deliberate
  exception: `Player.golfReady` decodes leniently (defaults to `false` if the column is
  missing) rather than failing the whole row — see the inline comment for why; the short
  version is the web app's JS client never validates row shape at runtime, so a pending
  migration degrades silently there, while Swift's `Codable` is strict by default and would
  otherwise hard-crash this app on a database that hasn't had every `supabase-schema.sql`
  migration applied. **This surfaced a real, still-outstanding issue**: the live project is
  missing the `golf_ready` column — run the migration in `card-room/supabase-schema.sql`
  (`ALTER TABLE public.players ADD COLUMN IF NOT EXISTS golf_ready boolean NOT NULL DEFAULT
  false;`) to fix it there too, since it also silently affects the web app's Golf pre-game peek
  feature in production.
- `GameLogic/Deck.swift` — `createDeck()`, `blackjackValue()`, `nextPlayer(in:after:)`: ported
  from `card-room/src/lib/deck.ts`. Must stay behaviorally identical to the TS version or the
  two clients would disagree about deck composition or who won.
- `Networking/SupabaseConfig.swift` — points at the same Supabase project as the web app (same
  URL + anon/publishable key — safe to embed; row-level security, not key secrecy, is what
  actually gates access). Uses the official
  [supabase-swift](https://github.com/supabase/supabase-swift) package via Swift Package
  Manager for REST + Realtime, rather than hand-rolling HTTP/WebSocket calls.
- `Networking/PlayerSession.swift` — `UserDefaults`-backed equivalent of the web app's
  `localStorage` `cardroom_player_id`/`cardroom_room_code`, plus `FunName.generate()` (same
  three word lists as `src/lib/names.ts`, so placeholder names read identically on both
  clients).
- `Networking/RoomService.swift` — `joinOrRejoin(code:playerName:)` (mirrors `joinRoom()` in
  `src/pages/Landing.tsx`: inserts a new player or reuses this device's existing seat),
  `sendHeartbeat`, `logAction` (best-effort, capped-at-30 `action_log` append, same as the web
  app's), and `roomChannel(roomId:)`.
- `Networking/LobbyService.swift` / `GameService.swift` — the Blackjack-only slice of
  `src/lib/games.ts`'s `dealGame()` and `src/pages/Game.tsx`'s `drawFromDeck`/`stand`/dealer
  auto-reveal. **Golf is not ported** — only Blackjack deals/plays right now.
- `ViewModels/RoomViewModel.swift` — the realtime-synced state of one joined room session
  (shared by both `LobbyView` and `GameView`, since they're really two perspectives on the same
  subscription): subscribes to `rooms` UPDATE and `players` INSERT/UPDATE/DELETE via
  supabase-swift's Realtime v2 API, runs the 10s heartbeat, and exposes the Lobby/Game actions.
- `Views/` — `JoinRoomView` (real join, not just a lookup), `LobbyView` (player list + the
  dealer's "Deal Blackjack" button), `GameView` (hands, turn indicator, Hit/Stand, round
  results), `CardView` (a plain native placeholder — no card-art assets ported from the web
  bundle yet), and `RootView`, which switches between the three purely off state (room `state`
  flipping to `.playing` is what moves you from Lobby to Game, not a navigation push).

### How this was verified
No UI-automation tool (no Accessibility permission for AppleScript, no `idb`) was available to
drive the simulator's keyboard from a script. First pass: the exact same `Models`/`GameLogic`/
`Networking` source files were built as a standalone Swift Package executable and run against
the real Supabase project — joining a room the web app's dealer had created, decoding the hands
the *web* app's `dealGame()` actually dealt, hitting and standing, and confirming on the web
client's own screen that its Action History showed those exact actions in real time. That caught
the `golf_ready` issue above, and proves real cross-client data compatibility — but it only
exercises the service layer, not the actual SwiftUI view tree, which let a real view-layer bug
ship unnoticed (see below). Second pass, added after that: `JoinRoomView` has a `#if DEBUG`-only
hook that auto-joins a room code from the `CARDROOM_AUTOJOIN_CODE` environment variable on
launch —
```sh
SIMCTL_CHILD_CARDROOM_AUTOJOIN_CODE=<code> xcrun simctl launch booted com.cardroom.app
```
drives the *real* compiled app (not a CLI stand-in) through Join → Lobby → Game, screenshotted
at each step, with the web app dealing from the other side. Compiled out of release builds
entirely; harmless if the env var is never set.

Two real bugs were caught and fixed this way, neither of which the service-layer-only CLI test
could have caught:
- **`RootView` held the shared `RoomViewModel` in plain `@State`, not `@ObservedObject`.**
  `LobbyView`/`GameView` both correctly re-rendered on realtime updates (they use
  `@ObservedObject`), but `RootView`'s own `if room.state == .playing { GameView } else {
  LobbyView }` branch never re-evaluated when `state` changed internally — only `@State`
  reassigning the optional itself (nil → an instance) triggers a re-render, not a mutation
  *inside* an already-held reference. Symptom: the Lobby's player list updated live just fine,
  but dealing from the web app never flipped the iOS app over to the Game screen. Fixed by
  moving the `if` into a small child view that holds `vm` as `@ObservedObject`.
- **`rooms.code` was `char(4)` (fixed-length/"bpchar")**, not an iOS bug at all but only
  reachable *through* iOS: a plain PostgREST `SELECT` always returned the correct 4-character
  value, but Realtime's logical-replication-based change feed delivered only the first
  character — consistent with `bpchar`'s OID occasionally getting confused with Postgres's
  unrelated 1-byte `"char"` internal type in replication tooling. Fixed at the schema level in
  `card-room/supabase-schema.sql` (`code` is now plain `text`); no app code on either client
  needed to change.

Golf's verification (see next section) caught a third, more serious one:
- **Swift's synthesized `Encodable` silently drops a `nil` optional field instead of encoding
  `null`** — confirmed directly: `JSONEncoder().encode(Wrapper(x: nil as String?))` produces
  `{}`, not `{"x":null}`. PostgREST's PATCH endpoint treats an *absent* key as "don't touch this
  column" but an explicit `null` as "set it to NULL", so every update struct with a plain `T?`
  field meant to clear a nullable column (`current_turn`, `golf_knocked_by`) was a silent no-op
  whenever it actually needed to write `null`. Caught because Golf's round-end reveal
  (`GolfService.endTurn` setting `current_turn` back to `nil` once play wraps around to whoever
  knocked) just never took effect — the turn indicator stayed stuck on the last player forever.
  Fixed with a reusable `NullableField<T>: Encodable` wrapper (`Networking/NullableField.swift`)
  that always encodes an explicit `null`; every `T?` update field that can legitimately mean
  "clear this column" now uses it instead of a bare `T?`. This was a latent bug in the Blackjack
  code too (`hit`/`stand`'s `current_turn` writes), just never hit by anything that actually
  passed `nil` through those paths in testing.

### Golf
Full feature parity with the web app's Golf mode: pre-game 2-peek phase with a dealer-gated
"Start Game" (ghosted until everyone's peeked), draw-from-deck-or-discard, swap-or-discard,
Knock!/End Turn (ghosted until the drawn card's resolved, same as the web app), and round
results sorted lowest-score-wins with the knocker labeled. `GameLogic/Deck.swift` ports
`golfHandValue`/`createGolfJokers` from `src/lib/deck.ts`; `Networking/GolfService.swift` ports
the "--- Golf ---" section of `src/pages/Game.tsx`. Hardcodes the built-in preset's scoring
rules (`zeroRank: Q`, `pairsCancel: false`) rather than reading a per-room config — this app
doesn't implement the web app's AI-custom-game designer at all, so there's nothing else to read
them from.

Verified two ways: a real-device screenshot of the pre-game peek screen (correct deck math,
correct peek budget, correctly ghosted Start button) via the `CARDROOM_AUTOJOIN_CODE` hook, and
a full logic round-trip using the CLI-executable technique above, extended into a small
multi-command driver (`join`/`peek`/`draw-deck`/`swap`/`discard-drawn`/`end-turn`/`knock`) so it
could be interleaved step-by-step with a Playwright-driven web dealer — peek, start, draw, swap,
discard, knock, and the final reveal, cross-checked against the web client's own screen the
whole way (matching Action History text, matching final scores computed independently by each
client from the same hands). That's what caught the `NullableField` bug above.

### Not yet built
The lobby's deal flow only offers Blackjack and Golf (matching `ENABLED_GAME_IDS` on the web
app) — redeal/"Play Again", any other game mode, card-art assets, and theming are still
missing. All of
`card-room/src/pages/Game.tsx` and `src/lib/games.ts`'s remaining logic needs a native
equivalent here — none of that TypeScript is reused, by design.

## Android

Not started yet. Will live in `android/` alongside `ios/` once there's a working Android SDK
install to build against.
