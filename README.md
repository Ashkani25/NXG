# BERMUDA NXG - Online Multiplayer Football Game

![BERMUDA NXG](https://img.shields.io/badge/version-2.0.0-blue)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Web-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

A complete online multiplayer football (soccer) game with support for 1v1, 2v2, and 3v3 matches.

## 🎮 Features

### Multiplayer
- **1v1, 2v2, 3v3 Matches** - Play with friends or randoms
- **Public Rooms** - Browse and join available games
- **Private Rooms** - Create rooms with 6-digit codes
- **Matchmaking** - Quick match queue by skill
- **Spectator Mode** - Watch ongoing matches

### Gameplay
- Real-time turn-based gameplay
- Physics-based ball movement
- Multiple fields and teams
- Goals and scoring system
- Match timer (3-10 minutes)

### Progression
- XP and Level system
- Coins and Gems
- Trophy ranking
- Daily rewards
- Achievements

### Social
- Friends list
- Direct messages
- In-room chat
- Online status

## 🏗️ Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | Vue 3 + Vite |
| Mobile | Capacitor (Android) |
| Backend | Node.js + Express |
| Realtime | Colyseus (WebSocket) |
| Database | MongoDB |
| Hosting | Railway |

## 📁 Project Structure

```
bermuda-nxg/
├── src/                    # Vue frontend source
│   ├── pages/             # Vue pages
│   ├── stores/             # Pinia stores
│   └── router/             # Vue router
├── server/                 # Backend server
│   ├── src/
│   │   ├── rooms/         # Colyseus rooms
│   │   ├── services/       # Business logic
│   │   └── *.js           # Server files
│   └── database/           # Database schema
├── public/                 # Public assets
├── android/                # Android project
└── www/                    # Game engine (HTML5)
```

## 🚀 Quick Start

### Prerequisites
- Node.js 20+
- MongoDB (local or Atlas)
- npm or yarn

### Backend Setup

```bash
cd server
npm install
cp .env.example .env  # Edit with your values
npm start
```

### Frontend Development

```bash
npm install
npm run dev
```

### Build Android APK

```bash
npm run android:build
```

## 📦 Deployment

### Railway (Backend Server)

See [RAILWAY_DEPLOYMENT.md](RAILWAY_DEPLOYMENT.md) for detailed instructions.

Quick steps:
1. Create Railway project from GitHub
2. Set environment variables
3. Deploy

### GitHub Actions (Android)

The repository includes GitHub Actions workflow that automatically builds the Android APK on push to main/master branches.

APK artifacts are available in the Actions tab.

## 🎯 API Endpoints

### Authentication
- `POST /auth/guest` - Guest login
- `POST /auth/register` - User registration
- `POST /auth/login` - User login

### Rooms
- `GET /rooms` - List public rooms
- `POST /rooms` - Create room
- `POST /rooms/join` - Join room

### Matchmaking
- `POST /matchmaking/join` - Join queue
- `POST /matchmaking/cancel` - Leave queue

### Social
- `GET /friends` - Friend list
- `POST /friends/:id/add` - Send friend request
- `GET /dm` - Direct messages

## 🔌 WebSocket Rooms

| Room | Purpose |
|------|---------|
| `queue` | Matchmaking |
| `gameroom` | Game lobby |
| `match` | Active match |
| `spectator` | Watch matches |
| `chat` | Global chat |
| `user` | Notifications |

## 📱 Game Controls

### Touch
- **Drag back** from disc to aim
- **Release** to shoot
- Power based on drag length

### Turn
- 15 seconds per turn
- Score goals to win
- 5 minute matches (configurable)

## 🏆 Ranking System

| League | Trophy Range |
|--------|-------------|
| Bronze | 0 - 499 |
| Silver | 500 - 999 |
| Gold | 1000 - 1799 |
| Platinum | 1800 - 2799 |
| Diamond | 2800 - 3999 |
| Master | 4000 - 5999 |
| Legend | 6000+ |

## 🔒 Security

- JWT authentication
- Rate limiting
- Server-authoritative game state
- Input validation
- Anti-cheat measures

## 📄 License

MIT License - see LICENSE file

## 👥 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to branch
5. Open a Pull Request

## 📞 Support

For issues or questions:
- Open a GitHub issue
- Check the [wiki](wiki-link) for documentation

---

**BERMUDA NXG** - Play Online, Win Together!
