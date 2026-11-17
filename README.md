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
drive the simulator's keyboard from a script, so the interactive join screen was confirmed
visually once, and the rest was verified a stronger way: the exact same `Models`/`GameLogic`/
`Networking` source files were built as a standalone Swift Package executable and run against
the real Supabase project — joining a room the web app's dealer had created, decoding the hands
the *web* app's `dealGame()` actually dealt, hitting and standing, and then confirming on the
web client's own screen that its Action History showed those exact actions in real time. That's
what caught the `golf_ready` issue above; it also proves actual cross-client data compatibility,
not just "the Swift compiles."

### Not yet built
Golf (rules + UI), the lobby's game-mode picker (Blackjack is dealt unconditionally right now),
redeal/"Play Again", any other game mode, card-art assets, and theming. All of
`card-room/src/pages/Game.tsx` and `src/lib/games.ts`'s remaining logic needs a native
equivalent here — none of that TypeScript is reused, by design.

## Android

Not started yet. Will live in `android/` alongside `ios/` once there's a working Android SDK
install to build against.
