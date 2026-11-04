# BERMUDA NXG — Online Multiplayer Football Game

## Project Overview
**Project Name:** BERMUDA NXG (also known as NEXORA)
**Type:** Full Online Multiplayer Football Game with Offline Mode
**Core Gameplay:** Disc Football (pogs/penny-flip style) - turn-based with physics
**Target Platforms:** Android, Web (responsive)

---

## Technology Stack

### Backend & Real-time
- **Colyseus** (v0.16+) — Authoritative multiplayer server, rooms, matchmaking
- **Express.js** — REST API, authentication, HTTP endpoints
- **Railway** — Production hosting for multiplayer server
- **Supabase** — PostgreSQL database, authentication, persistent storage

### Frontend
- **Vue 3** + Vite — UI framework
- **Pinia** — State management
- **Vue Router** — Navigation
- **Capacitor** — Android mobile wrapper

### Infrastructure
- **GitHub** — Source code management, GitHub Actions CI/CD
- **WebSocket (WSS)** — Real-time communication

---

## Game Modes

| Mode | Players | Teams | Duration |
|------|---------|-------|----------|
| 1v1 | 2 | 1 vs 1 | 5 minutes |
| 2v2 | 4 | 2 vs 2 | 5 minutes |
| 3v3 | 6 | 3 vs 3 | 5 minutes |

---

## System Architecture

### 1. Multiplayer Room System

**Room Types:**
- `lobby` — Main lobby for matchmaking queue
- `game_room` — Private/public rooms for custom matches (1-6 players)
- `match` — Active match with authoritative physics relay
- `spectator` — View-only access to active matches
- `chat` — Global chat room
- `user` — Personal notification/DM room

**Room Features:**
- Private rooms with 6-character code (e.g., "ABC123")
- Public room browser with filtering
- Host management (kick, start, settings)
- Ready system
- Player slots (2/4/6 based on mode)
- Field/ball selection by host
- Spectator mode (read-only, no game input)

### 2. Matchmaking

- Quick Match queue for 1v1, 2v2, 3v3
- Skill-based pairing (trophy range)
- Queue cancellation
- Auto-match creation when no room available

### 3. Authentication (Supabase Auth)

- Username-based registration/login
- Guest mode (temporary, upgradeable)
- Session persistence
- JWT tokens for API authentication

### 4. Database Schema (Supabase PostgreSQL)

**Core Tables:**
- `users` — profiles, stats, progression
- `matches` — match history with results
- `rooms` — active room metadata
- `friends` — friend relationships
- `messages` — direct messages
- `tournaments` — tournament definitions
- `leagues` — league standings
- `challenges` — daily/weekly challenges
- `rewards` — reward transactions

### 5. Economy System

- **Coins** — match rewards, daily login
- **Gems** — premium currency
- **XP** — progression, level-up rewards
- **Trophies** — ranked match ranking
- **Daily Rewards** — 7-day cycle
- **Challenges** — daily/weekly missions

### 6. Social System

- Friend list with online status
- Friend requests (add/accept/decline)
- Direct messages (DM)
- In-room chat
- Block/report users
- Invite friends to room

### 7. Tournament System

- Create tournament (knockout format)
- Register players
- Auto-bracket generation
- Match scheduling
- Results recording
- Winner determination

### 8. League System

- Seasonal leagues (Bronze → Legend)
- Weekly matches
- Points-based ranking
- Promotion/relegation

---

## API Endpoints

### Authentication
- `POST /auth/register` — Create account
- `POST /auth/login` — Login
- `POST /auth/guest` — Guest login
- `GET /auth/session` — Current session

### Profile
- `GET /me` — Current user profile
- `PATCH /me` — Update profile
- `GET /users/:id` — Public profile
- `GET /users/search` — Find users

### Rooms
- `GET /rooms` — List public rooms
- `POST /rooms` — Create room
- `POST /rooms/join` — Join room
- `POST /rooms/leave` — Leave room

### Matchmaking
- `POST /matchmaking/join` — Join queue
- `POST /matchmaking/cancel` — Cancel queue

### Matches
- `POST /matches/report` — Report match result
- `GET /matches/history` — Match history

### Social
- `GET /friends` — Friend list
- `POST /friends/:id/add` — Send friend request
- `POST /friends/:id/accept` — Accept request
- `GET /messages` — Direct messages
- `POST /messages` — Send message

### Economy
- `GET /economy/daily` — Daily rewards status
- `POST /economy/claim` — Claim daily reward
- `GET /leaderboard` — Top players

---

## Colyseus Room Messages

### GameRoom (Lobby/Room)
- `chat` — Send chat message
- `ready` — Toggle ready status
- `start` — Host starts match
- `leave` — Leave room
- `update` — Update room settings (host only)

### MatchRoom (Active Game)
- `shot` — Player shot data
- `settled` — Ball settled after shot
- `goal` — Goal scored
- `emote` — Player emote
- `ready` — Player ready for next round

### QueueRoom (Matchmaking)
- `cancel` — Leave queue

---

## Game State Synchronization

**Server-Authoritative:**
- Match timer (countdown from 300 seconds)
- Final score and result
- XP/trophy rewards
- Match registration

**Client-Authoritative (Validated):**
- Shot power and angle
- Ball position (validated by server)
- Collision detection

---

## Security Measures

- JWT token authentication
- Rate limiting on all endpoints
- Input validation and sanitization
- Server-side result validation
- Anti-cheat: duplicate goal prevention
- Session management: prevent duplicate logins
- Reconnection with reconnection tokens

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    RAILWAY SERVER                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │  Colyseus   │  │   Express   │  │   Health    │       │
│  │  (WS/WSS)   │  │   (HTTP)   │  │   Check     │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
│         │                │                               │
│         └────────────────┴───────────────────────────────│
│                          │                               │
└──────────────────────────┼───────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │  Supabase   │          │   Clients   │
       │  PostgreSQL │          │  (Android, │
       │  Auth       │          │   Web)      │
       └─────────────┘          └─────────────┘
```

---

## Development Phases

### Phase 1: Foundation
- Project audit
- SPEC.md documentation
- Supabase setup (database, auth)
- Railway deployment configuration

### Phase 2: Backend Core
- Colyseus server with rooms
- REST API endpoints
- Database schema
- Authentication

### Phase 3: Multiplayer Rooms
- GameRoom for 1v1/2v2/3v3
- Room creation/joining
- Ready system
- Match start

### Phase 4: Match Synchronization
- Real-time state sync
- Shot validation
- Goal detection
- Score tracking

### Phase 5: Matchmaking
- Queue system
- Skill-based pairing
- Auto-match creation

### Phase 6: Spectator Mode
- Watch active matches
- Read-only state sync

### Phase 7: Economy & Progression
- XP/Level system
- Coins/Gems
- Trophies and ranks
- Daily rewards
- Challenges

### Phase 8: Social
- Friends system
- Direct messages
- In-room chat
- Block/report

### Phase 9: Tournaments & Leagues
- Tournament creation
- Bracket management
- League standings
- Season system

### Phase 10: Android APK
- Capacitor setup
- Full build
- GitHub Actions CI/CD

---

## Acceptance Criteria

1. ✅ Server runs on Railway (public URL)
2. ✅ 2/4/6 players can connect to same match
3. ✅ Real-time sync of ball, players, score
4. ✅ Room creation with unique code
5. ✅ Matchmaking queue works
6. ✅ Spectator mode functional
7. ✅ Disconnect/reconnect handled
8. ✅ Results saved to database
9. ✅ Android APK builds successfully
10. ✅ Full offline mode preserved
