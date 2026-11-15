# NEXORA physics v0.6.4 ("physics-natural")

Branch `physics-natural` (pushed as `nexora-physics`), base `65d3121` (v0.6.3+9). Version 0.6.4+10, net proto 8 -> 9.

## What changed

**New unified physics world** (`lib/game/physics/`) replaces the v0.6.3 `_simS` solver entirely for the default
`stars` profile (the old `_simS/_subS/_hitS/_wallsS/_cornerS/_nudgeS/_spinS` code and `kTuneStars` are deleted).
`classic` (RN/Godot interop, picked by `pickProfile` only when a legacy peer is present) and the `godot` fixture-parity
profile keep their own legacy code paths untouched.

| module | role |
|---|---|
| `physics_config.dart` | every tunable (`kPhys`) + `PieceAttrs`, `statLerp` |
| `body.dart` | `Body` / `Goal` (moved out of engine.dart, re-exported), per-piece attrs, rolling-matrix helper |
| `friction.dart` | exact flow of dv/dt = -roll - damp*v per substep (substep-independent), clean sleep below vSleep |
| `collision_detector.dart` | swept time-of-impact: circle-circle, circle vs one-sided segment, post circle, concave corner arc |
| `collision_resolver.dart` | mass-based impulses, attribute-modified restitution, Coulomb tangential friction, rail impact boost with hard caps, slop+percent positional correction (sleeping bodies immovable) |
| `boundary_collision.dart` | real geometry: rails = segments, corners = rail + rail + concave arc, posts = circles, goal nets = segments; containment fallback |
| `physics_world.dart` | fixed 240 Hz step -> adaptive substeps (<= 4 px travel) -> event-driven CCD (earliest impact first, up to 12 events/substep) -> 3 correction passes -> ball roll; corner bank; disc goal-eject rule |
| `shooting.dart` | pull -> launch speed curve, power multiplier, attribute application |
| `trajectory_simulator.dart` | aim preview: clones the bodies and runs the SAME `PhysicsWorld.step` until the shooter's first contact / rail bounce |

Engine (`engine.dart`): stars geometry from the art (rails = the art's own lines), wider/deeper goals, per-team
attributes applied at reset and at every shot, world events -> sounds/particles/goal check, `aimPrediction()`, no
camera kick / screen shake / goal shake in stars. Renderer (`render.dart`): art at full size with no shaded border or
inset shadow, rounded corner cushions drawn exactly where the physics corners are, 3D goals (upright posts whose bases
are the collision circles, crossbar, back frame, roof/side netting), trajectory-preview dots + contact ring + outgoing
directions, no screen/goal shake. Ball rendering is unchanged (rotation follows the interpolated distance travelled;
no squash: `sq` is never set in stars). Interpolation unchanged (prev -> current physics state, alpha = acc/step); a
sleeping body has px == x so it never moves on screen.

Piece attributes (1..10, `DiscStats` + `teamPhysFor(id)` in data.dart, deterministic from the team id so online peers
agree): power (launch x0.70..1.30 + striking restitution bonus + rail boost factor), mass (x0.80..1.25 of the base disc
mass, independent of power), collision strength (+-0.04 e as striker), impact resistance (+-0.03 e as struck),
control (damping x0.92..1.08), rotational inertia (rail friction x1.15..0.85). Power/accuracy still come from the disc
catalog / `teamStatsFor` as before.

## Final parameters (`kPhys`)

| group | value | why |
|---|---|---|
| step / substep | 1/240 s, <= 4 px per substep, <= 16 substeps, <= 12 CCD events, 3 correction passes, 14 steps/frame cap | fixed step = render-rate independent; CCD + 4 px keeps contacts exact |
| sizes | disc r 49 (unchanged), ball r 24.2 (21.6 x 1.12, owner), post r 9, corner arc r 80 | arc > disc radius so every body meets a smooth corner |
| goals | half mouth 136 (was 124), depth 74 (was 58) | owner: a bit larger and deeper; ball (r 24.2) fits fully |
| masses | disc 3.0 x (0.80..1.25 by mass stat), ball 1.0 | heavy discs vs light ball (as v0.6.3's 3:1) |
| friction disc | damp 2.0 /s, roll 220 px/s^2, control x0.92..1.08 | full shot ~1.3-1.5 k px in ~1.6 s, weak ~0.1-0.2 k px in < 1 s |
| friction ball | damp 1.6 /s, roll 165 px/s^2 | ball rolls a little freer than a disc |
| sleep | 5 px/s | below it the velocity is set to exactly 0 |
| speed cap | 3800 px/s (all bodies, all rebounds) | no runaway |
| shot | base 2700 px/s, curve 0.06 + 0.94 p^1.5, power x0.70..1.30 | full pull: 1890 (power 1) .. 3510 px/s (power 10; v0.6.3 max was 3500) |
| contacts | e disc-disc 0.80, disc-ball 0.88, inelastic below 15 px/s, mu 0.04, e clamp 0.55..0.95 | standard billiard-like contacts, no micro-bounces |
| correction | slop 0.3 px, 80 % of the rest per pass | invisible, no pop |
| rails | e disc 0.60, ball 0.64, post 0.62, net 0.35; Coulomb mu 0.08 (x inertia attr) | controlled energy loss, mirror-like angles |
| impact boost | + 0.10 x powerFactor(0.7..1.3) x cos(incidence) x normal speed; out <= 0.95 x in, <= 3800 | direct hits rebound 0.71..0.77 by power, can never gain energy |
| corners | arc e 0.55, mu x0.5; bank 700 px/s^2 within r + 40 px of both rails | bodies slide round and out; nothing rests or vibrates in a corner |
| goal rule | slow disc (< 190 px/s) inside a goal walked out at 343 px/s | kept from v0.6 |

## Before (v0.6.3) / after (v0.6.4) - headless sweeps

Before: `tool/snap/sweep_v063_test.dart` at 65d3121 (retired in this branch). After: `tool/snap/sweep_v064_test.dart`.
Pitch: before 735 x 1416 play area (inset 4 px), after 829.2 x 1424 (the art's own lines, default pitch).

| measurement | v0.6.3 | v0.6.4 |
|---|---|---|
| disc power 7 full / 60 % / 25 % pull: launch px/s | 3057 / 1625 / 626 | 2970 / 1476 / 527 |
| ... path px | 1297 / 628 / 190 | 1296 / 589 / 166 |
| ... time to rest s | 1.50 / 1.23 / 0.82 | 1.62 / 1.32 / 0.87 |
| disc power 10 full / 60 % / 25 %: path px (time s) | 1475 (1.55) / 736 (1.30) / 227 (0.87) | 1469 (1.60) / 714 (1.40) / 206 (0.93) |
| power 1 full / 60 % / 25 %: path px | (power 1 = 0.62 x power 10) | 782 / 344 / 90 |
| full-pull glide power 1..10 (px) | - | 782, 868, 953, 1039, 1125, 1211, 1296, 1349, 1403, 1469 |
| disc hits still ball head-on: disc keeps / ball x disc speed | 10.3 % / 1.43 | 53.3 % / 1.40 (true 3:1 impulse, e .88) |
| 50 % offset hit: disc keeps / ball x disc | 40.6 % / 1.24 | 66.6 % / 1.22 |
| disc-disc head-on (equal): struck takes / momentum kept | - | 89.4 % / 99.1 % |
| ball 2000 px/s hits still disc: disc leaves at | 9.5 % | 45.8 % (ball bounces back at 702 px/s) |
| free ball 4000 / 1500 / 600 px/s: path px (time s) | 2137 (2.02) / 752 (1.52) / 229 (0.98) | 1825 (1.98) / 758 (1.70) / 250 (1.18) |
| rail, ball, 90 deg: speed kept | 84.4 % | 73.5 % (pf 1.0; 70.5..76.5 % for power factor 0.7..1.3) |
| rail, ball, 45 deg: normal / along-rail kept / angle out | 84.4 / 95.3 % / 41.5 deg | 70.6 / 86.3 % / 39.3 deg |
| rail, ball, 15 deg: speed kept / angle out | 94.7 % / 13.3 deg | 94.1 % / 10.5 deg |
| rail, disc, 90 / 45 deg speed kept | 89.2 / 92.7 % | 70.4 / 77.4 % |
| corners (ball): stuck / exit straight back | 0 / 0 (forced slide) | 0 / 24 of 120 exits (physical: only near-diagonal hits come back) |
| corners: bodies at rest inside the corner zone | parked ball nudged out 4/4 | 0 (ball 180 + disc 168 corner shots); pocket-placed bodies eased out 8/8 |
| ball spin per 60 fps frame at 4000 px/s | capped 23 deg (eased spin, decorative) | none in physics; renderer rotates by distance / r |
| squash on a full-power hit | ball +1.66 % | 0 |
| resting cluster drift over 2 s | 0.26 px | 0.000000 px |

## Tests

* `flutter test`: **61 / 61 passed** (Flutter 3.50.0 / Dart 3.14.0, linux-arm64 sandbox), including the new
  `test/physics_natural_test.dart` (23 tests) and the unchanged netcode lockstep test (bit-identical host/client).
* `flutter analyze`: 0 errors, 0 warnings, 66 infos - identical count to the v0.6.3 base (65d3121 also reports 66 infos).
* Retired (superseded contracts of the removed solver): `test/physics_v061_test.dart`, `test/physics_v063_test.dart`,
  `test/stars_physics_test.dart` (its default-profile and AI determinism checks moved into physics_natural_test),
  `tool/snap/sweep_v063_test.dart`. Updated: `disc_stats_test` (power curve now 0.70..1.30), `formation_test`
  (`kPhys.discR`), `proto_guard_test` (proto 9).

## Known limitations

* Exact-diagonal corner shots come straight back (contact normal of the arc points straight back); every other
  angle slides round the arc and out along a rail. This follows the "outgoing angle from the contact normal" rule.
* The corner bank is a deliberate rule (a raised corner): it adds a little speed to a body touching a corner so it
  never rests there.
* The aim preview shows the path without the accuracy deviation (that is rolled at release), and its length still
  scales with the accuracy stat. Its contact point is checked against the real shot to within one physics step.
* Visual checks (3D goals, corner cushions, full-size art) were not screenshotted on a device in this sandbox.
* Mixed rooms with RN/Godot peers still play the legacy `classic` physics (protocol interop).
