# DECISIONS

| # | Decision | Why | Param |
|---|---|---|---|
| D1 | Offline-first full build: every world/game runs locally; online seams via `BackendGateway` and per-world `Repository` interfaces | Owner asked for a complete offline version to put online later | P17, P22 |
| D2 | Local storage = `shared_preferences` JSON (`LocalStore`) instead of Drift/Isar | No code generation available in the build pipeline; data volume is small; keys are namespaced so a Drift migration is mechanical | P22 (deviation) |
| D3 | Repo `Ashkani25/NXG` master replaced by NEXORA; old Disc Football kept on branch `backup-disc-football-2026-11-11` | Owner: "کامل پاک کن، جدید بساز" | — |
| D4 | Android platform folder generated in CI (`flutter create`) with branding/icon copied from `branding/` | No local Flutter SDK; keeps repo small | P02, P29 |
| D5 | Flutter pinned to 3.27.1 in CI | Reproducible builds | P01 |
| D6 | Games may render with Ticker+CustomPainter instead of Flame | Full control of deterministic loop; Flame stays available | P08 (allowed variant) |
| D7 | UNO renamed in UI to "NX Cards (UNO-style)", id stays `uno` | Trademark | P30 |
| D8 | Licensed national pucks never used; only original skins | Licensing | P30 |
| D9 | XP daily cap 3000 locally, mirrored by `award_xp()` SQL | Anti-farm; server will be authoritative online | P21 |
| D10 | Asset paths generated into `AppAssets` from `assets/` | Kit layout differs from earlier menu code | — |
| D11 | Live Supabase `eisstodgncimypdawisy` shared with Expo + Godot apps; Flutter is online-first with offline fallback | Owner: whole app fully online | 2026-11-12 |
| D12 | Football (`finger_soccer` id, code in lib/games/disc_football) ported from Godot repo asbiulder/Nexora_godot (newest); Godot wins over Expo on differences | Owner 2026-11-14 | — |
| D13 | DB migrations additive only, tested in begin/rollback first | Shared backend with Expo/Godot | — |
| D14 | `update_room(4 args, no defaults)` added as separate overload (20261114120000_update_room_mode.sql); old 3-arg untouched. Godot's 20261114000000_lobby_mode_change.sql must NOT be applied as written (defaults make 2/3-arg calls ambiguous) | Room mode change was broken for everyone | 2026-11-14 |
