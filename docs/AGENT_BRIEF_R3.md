# NEXORA round-3 brief (online migration) — read fully, then docs/AGENT_BRIEF.md for the core APIs

Project: /workspace/work/nexora (Flutter, package `nexora`). No Flutter SDK in sandbox: compile only via CI:
`/workspace/work/nexora_check.sh <yourname> "<regex of your paths>"` (shell, credentials [{"provider":"github"}], timeout 120; may promote to background — wait for it). Iterate until 0 errors in your paths and your tests pass. Run it at least once before you finish. Other agents work in parallel in the same tree: only edit your own paths; errors outside your regex are not yours.

## What changed vs round 1/2
- App is now ONLINE on the live Supabase project `eisstodgncimypdawisy` (URL https://eisstodgncimypdawisy.supabase.co; public anon key: see lib/online/supabase_client.dart / the Godot repo's src/net/supa.gd — public, OK to embed). Same accounts/tables as the Expo app and the Godot app — must interoperate (same RPC names/args, same wire formats).
- Extra packages already in pubspec.yaml: supabase_flutter, livekit_client, app_links, permission_handler. Add others only if essential and justify in your report.
- Existing online layer: lib/online/{link.dart (RoomLink, Expo-compatible wire), models.dart, supabase_client.dart, voice.dart}. CI on branch check-online-port is green with them.
- Live DB schema snapshot: /workspace/work/nexora/supabase/live_schema.sql (may be slightly stale; read-only live queries: `echo "SQL" | bash /workspace/work/sbq.sh` with credentials [{"provider":"supabase"}]).
- FOOTBALL SOURCE OF TRUTH is now the Godot version (newest, updated 2026-11-14): /workspace/work/godot_src (GDScript; SPEC.md explains the architecture; src/game = engine/match view/HUD, src/net = supabase/realtime/room_link/voice/discs, src/online = hub/lobby/ranks/tournaments/challenges/arena/online_match/online_result, src/screens, src/social, src/oracle; assets/g/** art). Port behaviour, physics constants, look and Persian texts exactly. The Expo port in lib/games/disc_football/core/ was done from the older RN code: reconcile it with src/game/engine.gd (e.g. heavier discs) — Godot wins on any difference.
- The game id is `finger_soccer` in the registry UI name "فوتبال انگشتی", implemented under lib/games/disc_football/ (old lib/games/finger_soccer/ gets removed by the football agent).

## Hard rules
- No fake features: unfinished → `OnlineOnlyNotice` / «به‌زودی». Never pretend something is online when it is not.
- DB changes: ADDITIVE ONLY (new tables/columns/functions; `create or replace` only for functions you add, never change an existing function's signature/behaviour used by Expo/Godot). Test every migration first inside `begin; ... rollback;` via /workspace/work/q.sh (credentials supabase). Apply for real only after the test passes and you verified existing Expo/Godot football RPCs still work. Save each migration under supabase/migrations/ and note it in your report (the main agent records DECISIONS).
- No secrets in the repo (anon key is public and fine). Do not push to master. Do not commit anything; nexora_check.sh handles CI pushes to check-* branches.
- Persian default + English via context.tx. Keep files < ~900 lines, explicit types, Flutter 3.27 APIs.
- Do not edit lib/app/router.dart or lib/main.dart unless your task says so; expose `List<RouteBase> xxxRoutes` in your area and say so in the report.
- If a step loops more than twice without progress, stop that step and report what blocked it.

## Report
Files created/changed, what is truly working online (verified how), what is not, migrations applied (name + verification), routes to wire, risks.
