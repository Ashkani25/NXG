# UI audit — Milestone 1 (cleanup & simplification)

Branch `nexora-online-redesign`. Goal: one clear bottom nav (≤ 5 tabs), every feature reachable from **one obvious
home** (+ at most one shortcut), one Settings page, one set of empty/loading/error states, smooth on weak phones.
Game physics/tuning, Supabase schema and online logic are untouched.

## New navigation

Bottom dock (`Nx2Dock`, `lib/core/ui2/nx2_widgets.dart`) — 5 destinations:

| Tab | Route | Home of |
|---|---|---|
| Home | `/hub` | Profile HUD, ORACLE (mascot + "Ask ORACLE"), Settings (gear) |
| Social | `/social` | Feed & stories (Nova), Chats/Calls/Contacts & friends (Orbit), Communities (Social Station) |
| **PLAY** (raised centre) | `/rooms` | Quick play, new room, open rooms, **All games**, **Tournaments**, **Rankings** |
| Shop | `/world/nexora_exchange` | Items, featured, purchase history |
| Profile | `/world/personal_orbit` | Identity, **Rewards** (daily reward + missions), Wardrobe, My Space, Achievements, Stats, Activity |

Old routes still work (deep links, ORACLE intents, notifications) through `legacyRedirect()` in `lib/app/router.dart`:
`/rewards` → Profile › Rewards, `/world/nova_gallery|orbit_network|social_station` → `/social?tab=feed|chats|communities`.

## Duplicates found and decisions

| # | Duplicate / clutter | Where it was | Decision |
|---|---|---|---|
| 1 | Dock had **7** destinations (Chat+Media, ORACLE, Tournaments, GAME, Shop, Rewards, Profile) and no Home | dock | 5 tabs: Home, Social, PLAY, Shop, Profile |
| 2 | ORACLE: dock button + Home mascot long-press + Home ORACLE button + corner buddy | dock, Home | Home is its home (mascot + "Ask ORACLE"); corner buddy kept as the one shortcut (can be turned off in Settings). Dock button removed |
| 3 | Tournaments: dock + Home "Cups" tile + Home leagues card + Arcade card + per-game setup | dock, Home, Arcade | Home = PLAY tab link. Shortcut = Home "Leagues & Cups" card. Per-game setup entry kept (contextual: filtered to that game). Dock button, Home tile and Arcade card removed |
| 4 | Rankings: Home tile + Arcade › Records button | Home, Arcade | PLAY tab link only |
| 5 | Rewards: dock REWARDS page (= Missions + Achievements) duplicated Profile's Missions + Achievements tabs | dock, Profile | REWARDS page deleted; Profile › **Rewards** tab (renamed from Missions). `/rewards` redirects there |
| 6 | Daily reward claim in 4 places: Home tile, Shop wallet button, Missions tab, ORACLE hint | Home, Shop, Profile | Home = Profile › Rewards. Shortcut = Home "Today's reward is ready" card (only shown while claimable). Shop button removed |
| 7 | Shop: dock + Home "Shop" tile + Profile quick link + coin chip | Home, Profile | Dock tab. Shortcut = coin chip in the Home HUD. Tile and quick link removed (Wardrobe/My Space "get more" buttons kept: contextual) |
| 8 | Inventory: Home tile → Profile (same page as dock Profile) | Home | Removed (Profile › Wardrobe) |
| 9 | Friends: Home "Friends" tile → Orbit, Social hub "Friends" tab (actually Social Station), Profile "Friends" card → Orbit Contacts | Home, Social, Profile | Home = Social › Chats › **Contacts & friends**. Mislabelled "Friends" social tab renamed **Communities**. Home tile and Profile card removed |
| 10 | Nova Gallery, Orbit Network, Social Station each reachable from Home tiles, Home "All" sheet and the Social tab | Home | Only the Social tab (sub-tabs). Standalone routes redirect |
| 11 | Home "ONLINE" button (finger-soccer lobby) duplicated PLAY › Quick | Home | Removed |
| 12 | Home "NEXORA MENU" grid (8 tiles) + "All" sheet listing all worlds + Settings again | Home | Removed; Home keeps PLAY, Ask ORACLE, reward card, leagues/activity strip |
| 13 | Home search icon (navigation search over worlds/games) duplicated the dock and ORACLE navigation | Home | Removed (`hub_search.dart` deleted) |
| 14 | Settings: Home gear + Home "All" sheet + Profile quick link | Home, Profile | Home gear only |
| 15 | Arcade › Records tab duplicated Profile › Stats (each game tile already shows its record) | Arcade | Records tab removed; Arcade is one games grid titled "All games" |
| 16 | Arcade "Social Station tournaments" promo card | Arcade | Removed (Social › Communities) |
| 17 | Social tab stacked **three** navigation bars at the bottom (Nova/Orbit inner NavigationBar + Social switcher + dock) and a large section-title panel | Social | Social switcher moved under the top bar (`NxSubNav`); inner sections are one compact chip row at the top (`Nx2SectionBar`); section-title panels removed. One bar at the bottom: the dock |
| 18 | Nova: "new story" in top bar **and** "Your story" bubble; "New post" in empty state **and** FAB | Social › Feed | Story = "Your story" bubble; post = FAB |
| 19 | Social Station: "Create community" in empty state **and** "New community" FAB (overlapping) | Social › Communities | FAB only |
| 20 | Each list page drew its own spinner / empty / error layout (rooms, leaderboard, tournaments, inbox, chats, calls, friends, feed, communities…) | many | Shared `NxLoadingState`, `NxEmptyState`, `NxErrorState` (`lib/core/widgets/nx_states.dart`); `NovaEmptyState` and `SocialEmpty` now delegate to them |
| 21 | Profile title "PROFILE · PERSONAL ORBIT", Shop title "NEXORA EXCHANGE", Play title "ROOMS" did not match the dock labels | titles | Titles match the tab: PROFILE, SHOP, PLAY |

## Performance notes (weak phones)
- Dock: per-icon `ShaderMask` (one saveLayer each) replaced by tinted icons; whole dock in a `RepaintBoundary`.
- Profile tab bar: 18 px blurred shadow removed.
- Social: two fewer bars to lay out/paint per frame.

## Not changed
Game screens, physics/tuning, Supabase schema/RPCs, online/match logic, all art assets.

## Stage 2 — theme, one grouped Settings page

- **Theme mode** (Settings › Theme & graphics): System / Dark (default) / Light, switched live. Light = the same user
  art under a light veil, light panel fills, dark text (`NxThemeColors.light`, `NxColors.light`/`Nx2.light` tokens;
  `NexoraApp` flips them and rebuilds the tree). Accent colours used as text go through `Nx2.ink()` so they stay
  readable on light fills. **Games stay dark**: game host and online match pages force the dark theme, and
  `Nx2Panel`/`NxPill` follow the ambient theme brightness rather than the global flag.
- **Low graphics** (quality Low or Reduced motion) skips the blurred panel glow (`Nx2FramePainter.lowFx`).
- **Settings page** grouped: Account, Notifications (game invites → `InviteWatcher`, tournaments →
  `TournamentWatcher` incl. device reminders; off cancels scheduled ones), Privacy & data, Language, Theme & graphics,
  Sound & haptics, Accessibility (text size 85–130 % on top of the system size, high contrast, reduced motion),
  ORACLE (keep chats offline = no cloud model calls, corner buddy, speech bubbles, replay tour). No other page holds
  an app-wide preference (onboarding's first-run language pick and ORACLE voice commands aside).
- Test: `test/worlds/settings_test.dart`. Light screenshots: `flutter test test_render/menus_render_test.dart --dart-define=LIGHT=true`.
