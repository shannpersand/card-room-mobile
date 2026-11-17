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
- `Models/` — `Card`, `Player`, `Room`, `GeneratedGameConfig`, `SavedGame`: Swift structs that
  mirror `card-room/src/types.ts` field-for-field, so they decode the exact JSON shape already
  sitting in Supabase. **Keep these in sync by hand** if the web app's schema changes — there's
  no shared source of truth between the TypeScript and Swift definitions.
- `Networking/SupabaseConfig.swift` — points at the same Supabase project as the web app (same
  URL + anon/publishable key — safe to embed; row-level security, not key secrecy, is what
  actually gates access). Uses the official
  [supabase-swift](https://github.com/supabase/supabase-swift) package via Swift Package
  Manager for REST + Realtime, rather than hand-rolling HTTP/WebSocket calls.
- `Networking/RoomService.swift` — `fetchRoom(code:)`, `fetchPlayers(roomId:)`, and a
  `roomChannel(roomId:)` starting point for wiring up Realtime subscriptions (not yet wired to
  a live subscription loop — that's the next piece to build).
- `Views/JoinRoomView.swift` — proof-of-concept screen: type a code, confirm it resolves to a
  real room over the network. This is the one thing to manually test first once Xcode is set up
  (create a room on the web app, type its code in here, confirm it finds it).

### Not yet built
Everything past "find the room": the actual game-room screen, realtime hand/turn sync, the
lobby/dealer settings flow, game rules (Blackjack/Golf) reimplemented in Swift, theming. All of
`card-room/src/pages/Game.tsx` and `src/lib/games.ts`'s logic needs a native equivalent here —
none of that TypeScript is reused, by design.

## Android

Not started yet. Will live in `android/` alongside `ios/` once there's a working Android SDK
install to build against.
