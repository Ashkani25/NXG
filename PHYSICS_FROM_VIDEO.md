# Physics calibrated from the reference game recording (6 min, 24 fps, 720x1600)

Measured by tracking the ball (and moving discs) frame by frame. Pitch in the video: 562 px wide, ball diameter ~34 px,
disc diameter ~72 px, goal mouth ~193 px (0.34 of pitch width) - already matches the pitch geometry used here.
Video px -> game units: x ~1.37 (forest pitch). Values below are estimates (recording has dropped/duplicate frames, +-15 %).

| What | Reference video | Before | Now (www/js/game.js) |
|---|---|---|---|
| Ball max speed | ~1810 px/s (3.2 pitch widths/s) | cap 1890K | cap 1960K |
| Ball friction, low speed (100 px/s) | ~140 px/s^2 (soft glide) | ~550 | ~180 |
| Ball friction, 200-400 px/s | 350-750 px/s^2 | ~770-810 | ~375-710 |
| Ball friction, 600+ px/s | ~900 px/s^2 | ~860 | ~820 |
| Ball wall bounce (normal speed) | e ~.72 slow, ~.60 mid, ~.42 fast (>1000 px/s) | .91 -> .77 | .72 -> .42 (by normal speed) |
| Piece slide from ~1150 px/s | stops in ~2.2-2.7 s, long soft tail | 1.7 s, abrupt stop | ~2.3 s, soft tail |
| Max piece launch | ~1150-1300 px/s | ~1450 px/s | ~1290 px/s |

Tunables: `PF1, PF2, PV0` (pieces), ball friction in `sim()`, wall bounce `eN` in `walls()`, launch in `fire()`.

Not measured / unchanged: goal posts (kp), net/back-wall bounce, piece-wall bounce (.6), piece-piece bounce (EPP), HV (piece mass vs ball).
