# NEXORA – project notes

Open `www/index.html` (or run `npx cap sync android` and build). Everything lives in `www/`.

- `
- `supabase/schema.sql` – database schema + RLS + RPCs (hand-written, run & fix before use).
- `www/js/backend.js` – offline single-player backend (no fake users or data). `www/js/backend-supabase.js` – Supabase adapter skeleton.
- `www/js/config.js` – switch `BACKEND: 'local' | 'supabase'`, keys, leagues, rewards, tournaments.
- Physics tuning lives at the top of `www/js/game.js` (`HV`, `PF1`, `PF2`, `EPP`, `PCAP`, launch speed in `fire()`).
- Trails: `TR` (one per ball, 13) and `FA` (one accent per pitch, 14) in `www/js/game.js`.
- Old v4 single-file game is kept as `index_v4_backup.html`.

- Teams: `CATS` in `www/js/game.js`; badge images in `www/assets/teams/<cat><NN>.webp` (old ones in `_archive/teams_old`).
- Balls: 26 (`b0..b25.png` + `s0..s25.webp` in `www/assets/balls`), names in `BALLN`, trails in `TR`.

## v6 (visual polish)
- Ball never leaves the ground (no hop); nicer lighting + motion-blur spin in `renderBall()` (`js/game.js`).
- Pitch scale: `const FS=1.12` near the top of `js/game.js` (1 = old size). Pieces/ball keep their size, so there is more room.
- Pieces have visible thickness (dark side layers drawn under each piece in `sprite()`), plus a soft vignette (`#vig`, css).
- 3D home screen: `js/fx3d.js` (gyro/pointer parallax + coverflow on mode cards) and the "v6" blocks at the end of `css/app.css`.
