# Flame layer (Stage F1)

NEXORA's physics games run on the [Flame](https://flame-engine.org) engine through one shared
layer in `lib/games/core/flame/` (import `package:nexora/games/core/flame/nx_flame.dart`).
The pure-Dart engines in each game's `core/` stay deterministic and Flame-free; Flame owns the
frame loop, the render surface and the effects.

## NxFlameHost (`nx_flame_host.dart`)

A `FlameGame` that:

- turns Flame's variable frame dt into **fixed simulation steps** (`step`, default 1/120 s):
  accumulator, big-frame clamp (`maxFrameDt` 0.05 s), hard cap (`maxStepsPerFrame` 8) that drops
  the backlog instead of spiralling on a slow phone. `advance(dt)` is pure and unit-tested.
- calls `onStep(step)` for each fixed step, then `onFrame(dt)` once per frame (clamped dt, or the
  raw dt with `rawFrameDt: true` for engines that clamp it themselves).
- keeps `clock` (sum of raw frame dt; stops while paused), `accumulator`, `totalSteps`, `alpha`.
- draws the game's existing `CustomPainter` (`host.painter`) through `NxPainterLayer` on the same
  logical-pixel canvas a `CustomPaint` had, so visuals are unchanged. Swap the painter in `build()`
  (theme changes just work).
- has a transparent background (Flutter widgets / table art behind it show through) and pauses
  when the app is backgrounded (`pauseWhenBackgrounded`).

Usage:

```dart
late final NxFlameHost host = NxFlameHost(
  step: 1 / 120,
  onStep: (double s) => world.tick(),      // deterministic core
  onFrame: (double dt) => uiTimers(dt),    // bots, banners, HUD notifiers
  fxConfig: NxFxConfig.of(fancyEffects: launch.fancyEffects, reducedMotion: launch.reducedMotion),
);
// build():
host.painter = MyScenePainter(...);
Stack(children: [GestureDetector(child: GameWidget<NxFlameHost>(game: host)), ...hudWidgets]);
```

Gestures, HUD, banners and dialogs stay Flutter widgets stacked over the `GameWidget`.

## NxFx (`nx_fx.dart`)

Render-only effects on top of the painter (`host.fx`), in screen pixels:

- `burst(at, ...)` — confetti strips (spin + flip, gravity) or round sparks; goal / win.
- `ring(at, color)` — small spark ring + expanding stroke; pocketing / hard hits.
- `fireTrail(x, y, vx, vy, strength, dt, slot:)` — real animated fire behind a fast body:
  flickering particles that rise, lick sideways, shrink and cool white-yellow → orange → red,
  additive blend, drawn in ONE `drawRawAtlas` call from a soft radial sprite.
- `fireBurst(at)` — a short fountain of fire for celebrations.

Budget: `NxFxConfig.maxParticles` (220 fancy / 72 low) caps everything alive; fancyEffects off
spawns ~40% of the particles and uses a 32-slot fire pool (96 fancy); **reducedMotion spawns
nothing**. The fire pool is preallocated typed arrays + colour LUTs + one Paint (no per-frame
allocation); bursts allocate only when spawned (Flame `ParticleSystemComponent`). Effects use
their own RNG and never touch a simulation.

## Games on Flame (F1)

| Game | Loop | Painter | Flame FX |
| --- | --- | --- | --- |
| Finger soccer (`bm_view.dart`) | `onFrame(raw dt)` → `BmEngine.frame` (engine keeps its own 1/240 s accumulator, untouched) | `BmPainter` | fire on fast ball (>1400 u/s) and fastest disc (>1750), confetti + fire on goal and on win |
| Billiards (`billiards_game.dart`) | `onStep(1/120)` → `world.tick()` while rolling; bot / cue / banner in `onFrame` | `PoolScenePainter` (table art stays a widget below) | fire on fast cue ball / object ball, spark ring on every pocket, confetti + fire on win |
| Carrom (`carrom_view.dart`) | `onStep(1/120)` → `CrController.simStep()`; `CrController.frame(dt)` for timers/bot/HUD (`tick()` kept for tests) | `CrPainter` (keeps its shake/flash/impact sparks) | fire behind a hard striker, spark ring per pocket (replaces the old pocket burst), confetti + fire on queen cover and win |

The animated GIF balls (NX Spin / NX Final, ids 36/37) still pick their frame from the wall clock
(`host.clock` = the old Ticker's elapsed time) with the GIF's own frame duration; that path is
unchanged.

## F2 candidates (not migrated yet)

- Ludo (`ludo_game.dart`) — token hops / captures: `NxFx.ring`, win `burst`.
- Snakes & Ladders (`snl_game.dart`) — climb / slide effects, win confetti.
- Backgammon (`backgammon_game.dart`) — dice roll + bear-off effects.
- UNO (`uno_game_view.dart`) — card play bursts, UNO call, win.
- Quiz / Mafia — celebration effects only (mostly static UI; keep Flutter, add `NxFx` overlay).
