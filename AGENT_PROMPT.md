# MASTER PROMPT FOR THE AI AGENT — BERMUDA NXG (Firebase + Capacitor Android)

You are a senior full-stack + mobile engineer. Your job: take this repository from "code written, never run against a real Firebase project" to a
**tested, lag-free, bug-free Android release (AAB + APK)** of the game **BERMUDA NXG** (online disc-football, 5-minute matches, unlimited goals).
Work autonomously, in the phases below (start with Phase 0 — Clean Slate; it contains two mandatory confirmation gates), and do NOT stop until every acceptance criterion at the end is demonstrably met (show command output / screenshots as proof).
Never fake anything: no mock players, no fake online counts, no hard-coded leaderboards, no placeholder "coming soon" that pretends to work.
If something truly cannot be done (e.g. voice chat), the UI must say so honestly (already the case).

## 0. Ground rules
* App name everywhere: **BERMUDA NXG** (Android label, splash, titles, notifications, store listing). Android applicationId: `com.bermuda.nxg`.
* Backend = **Colyseus (realtime) + Express (REST) + MongoDB**, in `server/`. No Firebase, no Supabase anywhere.
* Clients are untrusted. Coins, gems, xp, trophies, inventory, shop, chests, tournaments, rooms, queue pairing and match settlement are changed ONLY by the server (`server/src/services/*`).
* Keep the existing UI/design (blue/green stadium theme, sprites in `www/assets/nx`, icons in `www/assets/ui2`). Do not redesign. Fix bugs, don't restyle.
* Every change must keep `npm run test:logic` and your own new tests green.
* Commit after every phase with a clear message.

## 0.5 Phase 0 — CLEAN SLATE (do this BEFORE Phase A)
The owner wants a fresh start: this repository is the ONLY project that stays on the machine. Deleting is irreversible, so follow this protocol exactly.
1. Keep-list (NEVER delete): this repository; build tooling and global caches — Node.js/npm/nvm, JDK 17, Android Studio + SDK/NDK/platform-tools/AVDs, Gradle (`~/.gradle`), Capacitor CLI, Docker, git, Python, system folders, personal documents that are not code projects, SSH keys, the release keystore (`*.jks`).
2. Find every OTHER code project (folders with `package.json`, `capacitor.config.*`, `android/`, `firebase.json`, `.git`, `docker-compose.yml`, `build.gradle`, old NEXORA / Supabase / Firebase copies, old zips of them) under the user's home/workspace/dev folders.
3. DRY RUN: write `CLEANUP_PLAN.md` (`path | type | size | last modified`) + the keep-list. STOP. Delete nothing until the owner replies exactly `CONFIRM DELETE`.
4. After confirmation: make ONE compressed backup outside the repo (`~/bermuda_old_backup_<date>.tar.gz`), then delete only the approved paths (system trash when possible), log them in `CLEANUP_LOG.md`, remove stale `node_modules`/`.gradle`/`build` of the deleted projects.
5. Remove leftover Firebase/Supabase client state: `firebase logout` (if installed), delete `~/.config/configstore/firebase-tools.json`, any `google-services.json`, `GoogleService-Info.plist`, `.firebaserc`, `serviceAccount*.json`, and env vars `GOOGLE_APPLICATION_CREDENTIALS`, `FIREBASE_TOKEN`, `SUPABASE_*`. Cloud projects of other services are deleted only after the owner replies `DELETE CLOUD PROJECTS: <names>`.
6. Verify the keep-list tools still run (`node -v`, `java -version`, `adb --version`, `docker --version`, `npx cap --version`) and that this repo still builds.
7. Start the NEW infrastructure named **BERMUDANXG**: Docker compose project `bermudanxg`, MongoDB database `bermudanxg`, domain/subdomain for the API (e.g. `api.<owner-domain>`).

## 0.9 Visual identity already implemented (do not redesign, only fix bugs)
* Boot = intro video `www/assets/intro.mp4` (tap to skip after 1.2 s, 9 s safety timeout; verify autoplay with sound on device, fall back to muted).
* ONE UI ("NX v8", end of `css/app.css`): blue glass cards, glossy blue buttons, 3D card carousel on Home (swipe/arrows, centre card = PLAY ONLINE), page-flip transitions (`flipin`, `cardin`), bottom bar HOME / PROFILE / WALLET / SHOP / LEAGUES, NX ring + crown avatar. Art lives in `www/assets/nx2/` (logo, 3D icons `i_*`, card art `c_*`, glyph icons `g_*`, `ring.webp`) and `www/assets/ui/bg_nx.jpg`.
* Team tiles are 3 per row with 74 px logos; scoreboard logos overflow the frame. Wallet screen shows real balances, daily reward and quests.

## 1. Repository map (read these first)
```
www/                      Capacitor web root (the real app)
  index.html              loads vendor/colyseus.js then js/*.js
  js/config.js            NEXORA_CONFIG: BACKEND:'colyseus', API_URL, WS_URL, MATCH_SECONDS:300, OAUTH flag + NexoraPrices
  js/game.js              physics + rendering (window.NexoraGame). Timed mode cfg.matchTime, golden goal, G.syncClock(sec) from the server clock
  js/backend-colyseus.js  client adapter => window.NexoraBackend (REST + Colyseus rooms). Falls back to js/backend.js (offline) when API_URL is empty
  js/screens-a.js (home/auth/shop/profile/settings) screens-b.js (daily/quests/league/friends/room) screens-c.js (rooms lobby, chats, NX Coach, tournaments, profile sheet) flow.js (matchmaking, match flow)
server/                   THE BACKEND (Node 20, plain CommonJS)
  src/index.js            Express + Colyseus bootstrap, schedulers (tournament tick/seed) guarded by Mongo locks
  src/api.js              all REST routes (JWT)   src/auth.js JWT + seat tickets + Google id-token verify   src/db.js Mongo + optimistic mutate()
  src/lib.js              pure logic (xp, trophies, brackets) — tested   src/services/* economy, social, match (report/settle/forfeit), rooms, tournaments, ai, notify
  src/rooms/              QueueRoom (ranked matchmaking) MatchRoom (relay + clock + forfeit) GameRoom (custom rooms, code) ChatRoom (global) UserRoom (pushes + presence)
  test/                   logic.test.js, auth.test.js   Dockerfile docker-compose.yml .env.example
scripts/vendor-colyseus.js  copies colyseus.js browser bundle into www/vendor
```
Realtime flow: client joins `queue` (JWT) -> server pairs by trophies -> `matched` message carries a **seat reservation** + match info -> client `consumeSeatReservation` -> `match` room (only holders of the server-signed ticket can join) relays shot/settled/goal/timeout/emote. Results go to `POST /match/report` (server computes rewards, cross-checks both reports, marks disputes). Custom rooms: `POST /rooms` / `/rooms/join` return a reservation for `gameroom`; host `start` -> both get a `match` reservation. Tournament `ready` creates the match when both players pressed Play and pushes `matchReady` through `UserRoom`.

## 2. Phase A — Infrastructure
1. Install Node 20+, Docker, JDK 17, Android Studio (SDK 35). Provision a VPS (Ubuntu 22/24, 2 vCPU/2 GB is enough to start) with a DNS name `api.<domain>`.
2. `cd server && cp .env.example .env`; set strong `JWT_SECRET` and `TICKET_SECRET` (`openssl rand -hex 48`), `CORS_ORIGIN` (Capacitor origins `https://localhost`, `capacitor://localhost` + your web origin), `GOOGLE_CLIENT_ID` (Web client id from Google Cloud console), `ANTHROPIC_API_KEY`, `AI_MODEL` (verify the model id in Anthropic docs).
3. `docker compose up -d --build` (server + MongoDB 7). Put **Caddy or nginx** in front for TLS and WebSocket upgrade (`wss://api.<domain>` -> :2567). Example Caddyfile: `api.example.com { reverse_proxy 127.0.0.1:2567 }`. Back up Mongo (`mongodump` cron) and enable the firewall (only 80/443/22).
4. Scale-out note: single process is fine for the first thousands of players. For several processes you MUST add Redis (`RedisPresence` + `RedisDriver` from `@colyseus/redis-presence` / `@colyseus/redis-driver`) and run the ranked `queue` room on exactly one process, otherwise players on different processes never meet. Document the chosen setup.
5. In `www/js/config.js` set `API_URL: 'https://api.<domain>'`, `OAUTH: true` once Google works. `npm install && npm run vendor:colyseus`.

## 3. Phase B — Server verification (write the tests, fix every bug you find)
`cd server && npm install && npm test` must pass. Then add integration tests (jest/node:test + `mongodb-memory-server` or a throwaway Mongo container + the real `colyseus.js` client) for:
* auth: guest, register (duplicate email 409), login wrong password 401, Google (mock verify), guest->email link, delete account, rate limits.
* economy: daily twice rejected, quests progress/claim, shop buy (not enough coins, already owned), parallel double-spend (2 simultaneous buys must not go negative — `mutate()` is optimistic, verify retries), chests, equip locked item.
* social: follow/unfollow idempotent counters never negative, like toggle, friend request/accept/remove, DM send/unread/read, global chat rate limit, notifications + realtime push to `UserRoom`.
* matchmaking: two clients in `queue` get `matched` with different seats; trophy window widening; cancel; user cannot join someone else's `match` room (ticket check); a third client cannot join.
* match: report too-short win rejected, duplicate report rejected, both reports agree -> settle once, disagreement -> `disputed` (no trophies), forfeit after leave, bot daily cap (15), Elo math, room reopens after friendly match (`matchDone`).
* rooms: create/join by code/full/leave, ready, update settings (host only), start -> both get `start` with working reservations, host leaves closes room, public list excludes locked/private.
* tournaments: cup with 4/5/8/16, league 3/4/6/8, fee charge/refund, cancel when < min players, `ready` both sides -> match + `matchReady` push, walkover at `roundEnds`, payouts exactly once, max 2 active per creator.
* AI: limit 40/day, graceful error when key missing, stubbed Anthropic call.
Security review: Helmet + request size limits, input validation on every route (names, texts, ids), NoSQL-injection safe (never pass raw `req.body` objects into queries — only strings), CORS allow-list, brute-force limiter on `/auth/*` (already in memory — move to Redis if multi-process), profanity filter for names/chat, **report/block user** feature (new route + UI) because Play Store requires UGC moderation, admin ban flag (`banned`) tooling.

## 4. Phase C — Client against the real server
`npm run serve`, test with two browser profiles: auth, home/shop/profile (server data only), ranked match end-to-end (identical final score both sides, 5:00 clock synced by `clock` messages, golden goal, forfeit, reconnect within 15 s), rooms + room chat, global chat + DMs (live push), follow/like/friends, NX Coach, tournaments (create, join with 4+ accounts, play rounds, table/bracket update, payout notification). Fix every console error. Add a global error boundary (toast) and a visible "reconnecting…" banner when the WebSocket drops (`room.onLeave` codes). Implement the missing guest-upgrade UI (`B.auth.link`) and the followers/following screens polish if needed.

## 5. Phase D — Gameplay quality (no lag)
60 fps target on a mid-range Android WebView (profile with `chrome://inspect`). Keep physics constants in `js/game.js` unless playtesting proves otherwise. Reuse arrays, cap devicePixelRatio at 2, pause rendering when hidden, auto-lower graphics if frame time > 20 ms, detach listeners on match end (`ch.close()` already leaves the Colyseus room), no heap growth over 30 consecutive matches. Network messages are tiny; measure RTT with a ping message to the match room and show it in the match header.

## 6. Phase E — Android (exact path)
```bash
npm install && npm run vendor:colyseus
npx cap add android && bash scripts/patch-android.sh      # appId com.bermuda.nxg, appName BERMUDA NXG
# Google sign-in: Google Cloud console -> OAuth client IDs: Web (used as GOOGLE_CLIENT_ID on the server) + Android (package com.bermuda.nxg + SHA-1 of debug AND release keystores)
# configure @capgo/capacitor-social-login with the WEB client id so it returns an ID token that the server verifies at POST /auth/google
# AndroidManifest: INTERNET permission only (add RECORD_AUDIO only if voice is implemented); android:screenOrientation="portrait"; usesCleartextTraffic=false (server is wss/https)
# launcher icon + splash from www/assets/ui/logo.webp, background #030a1a; keep-awake during matches; Keyboard resize mode "body"
npm run android:sync && cd android && ./gradlew assembleDebug          # app/build/outputs/apk/debug/app-debug.apk
keytool -genkeypair -v -keystore bermuda-nxg-release.jks -alias bermuda -keyalg RSA -keysize 2048 -validity 10000   # never commit it
# signingConfigs via gradle.properties, then:
./gradlew bundleRelease     # AAB (Play Store)   app/build/outputs/bundle/release/app-release.aab
./gradlew assembleRelease   # signed APK
adb install -r app/build/outputs/apk/debug/app-debug.apk && adb logcat | grep -i -E "chromium|capacitor|bermuda"
```
R8/minify on, keep Capacitor rules. Play Console: Data safety (account, chat content, device ids), content rating, privacy-policy URL, account-deletion URL (in-app delete exists), UGC policy (report/block). Test the intro video (assets/intro.mp4) autoplay with sound on real devices; fall back to muted.

## 7. Phase F — Test matrix
Devices: one low-end (2–3 GB) + one modern; Android 8/11/14; airplane-mode launch (clear message, bot practice works). Flows on two real devices: ranked win/loss/forfeit, room match, tournament round, DM both ways, follow/like, shop/daily/quests, settings persistence, sign-out/in, delete account. Edge cases: app killed mid-match (opponent wins after the grace period), double taps (NX.busy), clock skew, RTL (Persian/Arabic) names, keyboard over chat input, hardware back button (closes modals / confirms leaving a match), server restart during a match (clients must show a reconnect/forfeit decision, never freeze).

## 8. Acceptance criteria (show evidence for each)
1. `docker compose up` on the VPS is healthy behind TLS; `GET /health` ok; `npm test` + integration tests green.
2. Two real devices complete a ranked 5-minute match with identical score, server-side trophy change, no desync/crash.
3. Rooms, global chat + DMs (live), follow/like/friends, NX Coach, cups and leagues work end-to-end with real data and no mock data in client code paths.
4. 55+ fps average in a match on the low-end device, no ANR, cold start < 3 s (excluding the intro video).
5. Release AAB + signed APK produced and installable; name/icon/splash = BERMUDA NXG.
6. `RELEASE_NOTES.md`: what was fixed, what remains (voice chat, in-app purchases, push notifications, Redis scale-out if not done), exact rebuild/deploy commands.

## 9. Deliberately NOT done yet
Voice chat (WebRTC + TURN), in-app purchases (`features.billing=false`), push notifications (FCM), password-reset email (needs SMTP — add nodemailer + `/auth/reset`), email verification, Redis scale-out, admin dashboard, localization files, tablet layouts, Spin wheel and Achievements screens from the red mock-up (not implemented, omitted from the UI instead of faking them).

Start with Phase 0 and report after each phase (done / failing / next).
