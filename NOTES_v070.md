# NEXORA Flutter v0.7.0+11 (protocol 12)

## Merge
- Base: our `physics-natural` v0.6.4+10 (proto 9): `lib/game/physics/` world, rounded corners, no energy gain, 3D goals. **Physics constants, powers, accuracy unchanged.**
- Ported from `asbiulder/Nexora_godot` branch `nexora-physics-rebuild-20261115` (c0857b7..17f5fe7), excluding its `engine.dart` / `physics_config.dart` / `render.dart` / `data.dart` rewrite and its physics tests (impact boost up to 1.25x, +35% spin, square corners):
  - cups v3 + 9b22153 tournaments: `lib/online/cups.dart`, `cup_logic.dart`, `cup_alerts.dart`, `cup_reminders.dart`, `supabase/cups.sql`, `supabase/migrations/20261116_cups_plus.sql`, `supabase/tests/*`
  - 3e3ea31: only the `cup_cancel` fix (also in `migrations/20261117_cups_v070.sql`) and the settings/guest auth + manifest deep link
  - 17f5fe7: intro1 only (intro2/3 deleted) + `screens/auth_start.dart` (Login / Sign up / Guest after the intro)
  - 86c4a28 social profiles / player links; 97bef10 host pitch+ball sync (`s.fb`), rematch, turn rings (ported into our renderer)
  - launcher icon, flutter_local_notifications / timezone / share_plus + core library desugaring
- Not taken: their `android/keys` keystore handling and plain-text signing passwords in Gradle. Signing stays on `android/key.properties` (written by CI).

## Match on Flame (flame 1.38.2)
`MatchGame extends FlameGame`, shown through `GameWidget` (offline `screens/match.dart`, online `online/online_match.dart`). Component tree (`lib/game/flame/match_components.dart`):
- `FixedStepDriver` (-100): feeds Flame's frame dt to the engine; `Engine.update` accumulates and runs `lib/game/physics` in whole 1/240 s steps (online: the NetMatch controller does the same). No forge2d, nothing non-deterministic.
- `FrameClock` (-90): per-frame render state (interpolation alpha, net ripple, visual-only spin).
- `SoftCamera` (-80): critically damped, max 7 px drift toward the moving ball, frozen while aiming; input mapping (`toWorld`) uses the same offset.
- `BackgroundComponent` (0), `PitchSpace` (10; world transform) with `GoalNetsComponent`, `DropShadowsComponent`, `DiscsComponent` (+turn rings), `BallTrailComponent`, `BallComponent`, `GoalFramesComponent` (3D posts), `AimComponent` (arrow + physics trajectory preview), `ParticlesComponent`; `FlashComponent` (100).
- Display only: positions are interpolated with the accumulator's alpha; the ball's visual roll is low-passed and capped at 14 rad/s; the struck disc gets a visual twirl proportional to its launch speed (so it scales with the aim-arrow length), capped at 5 rad/s and damped; deeper soft black drop shadows under discs and ball.
- Tests: `test/flame_match_test.dart` (tree + paint order, Flame-driven match bit-identical to a headless engine fed the same frame times, bounded camera), physics determinism tests unchanged (`physics_natural_test.dart`, `parity_test.dart`).

## Tournaments
See `supabase/migrations/20261117_cups_v070.sql` header. Formats: single, best-of / first-to N, aggregate over N, real two-leg (leg 2 home side swapped, aggregate, optional away goals, then golden-goal or full decider). 30 s pre-match lineup after pressing Play (`lib/online/cup_lineup.dart`, `cup_ready` RPC). App-wide auto-move (`CupAlerts`). Global ranking (`cup_rankings`, `cup_ranking()`, `CupRankingScreen`).

## Limitations
- No FCM/APNs: a fully closed app only gets the pre-scheduled 10-minute local alarm; "draw done" / "match ready" need the app running (foreground: in-app + auto-move; background: local notification).
- Cash prizes are recorded and tracked only (`cup_payouts`, organizer marks paid). `pg_notify('cup_payout_pending')` is the hook for a future payment worker; no money moves.
- Disc/ball spin is visual only: the v0.6.4 physics has no spin term and was kept exactly as specified.
