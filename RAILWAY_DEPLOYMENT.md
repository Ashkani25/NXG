# BERMUDA NXG - Railway Deployment Guide

## Overview

This guide will help you deploy the BERMUDA NXG multiplayer server on Railway.

## Prerequisites

1. [Railway Account](https://railway.app)
2. [GitHub Account](https://github.com) with this repository linked
3. MongoDB database (can use Railway's MongoDB plugin or MongoDB Atlas)

## Deployment Steps

### Step 1: Prepare the Backend Server

The server is located in `/server` directory. It includes:
- Colyseus for real-time multiplayer
- Express for REST API
- WebSocket support for game synchronization

### Step 2: Set Up Railway Project

1. Go to [Railway Dashboard](https://railway.app)
2. Click "New Project" → "Deploy from GitHub repo"
3. Select your BERMUDA NXG repository
4. Railway will auto-detect the Node.js project

### Step 3: Configure Environment Variables

In Railway project settings, add these environment variables:

```
# Server
PORT=2567
NODE_ENV=production

# Database (choose one)
# Option A: Railway MongoDB (use the connection URL from Railway's MongoDB plugin)
MONGO_URL=mongodb://...

# Option B: MongoDB Atlas
MONGO_URL=mongodb+srv://username:password@cluster.mongodb.net/bermudanxg

# Security (generate secure random strings)
JWT_SECRET=your-secure-jwt-secret-min-32-chars
TICKET_SECRET=your-secure-ticket-secret-min-32-chars
SESSION_SECRET=your-secure-session-secret

# CORS (comma-separated list of allowed origins)
CORS_ORIGIN=https://your-frontend-url.com,capacitor://localhost

# Optional: AI Assistant
# ANTHROPIC_API_KEY=sk-ant-...
# AI_MODEL=claude-sonnet-4-5
```

### Step 4: Configure Build & Start Commands

In Railway project settings:

**Build Command:**
```
npm install && npm run build
```

**Start Command:**
```
npm start
```

Or use a `Procfile`:
```
web: npm start
```

### Step 5: Configure Health Check

Railway needs a health check endpoint. The server already has `/health` endpoint configured.

In Railway → Project → Settings → Health:
- Path: `/health`
- Interval: 30 seconds

### Step 6: Deploy

Click "Deploy" and wait for the deployment to complete.

Once deployed, you'll get a public URL like:
```
https://bermuda-nxg-server.up.railway.app
```

## Updating Frontend for Your Railway URL

After deployment, update your frontend configuration:

1. Edit `public/assets/game-config.js`
2. Update `API_URL` and `WS_URL`:
```javascript
API_URL: 'https://your-railway-url.railway.app',
WS_URL: 'wss://your-railway-url.railway.app',
```

Or set environment variables in your frontend hosting.

## Server Features

The deployed server provides:

### REST API Endpoints
- `GET /health` - Health check
- `POST /auth/guest` - Guest login
- `POST /auth/register` - User registration
- `POST /auth/login` - User login
- `GET /rooms` - List public rooms
- `POST /rooms` - Create room
- `POST /rooms/join` - Join room
- And more...

### WebSocket (Colyseus) Rooms
- `queue` - Matchmaking queue
- `gameroom` - Game rooms (1v1, 2v2, 3v3)
- `match` - Active match relay
- `spectator` - Spectator mode
- `chat` - Global chat
- `user` - User notifications

## Troubleshooting

### Server Won't Start
1. Check logs in Railway dashboard
2. Verify environment variables are set correctly
3. Ensure MongoDB connection is working

### Players Can't Connect
1. Verify CORS_ORIGIN includes your frontend URL
2. Check WebSocket URL is correct (wss:// not ws:// for HTTPS)
3. Ensure firewall rules allow WebSocket connections

### Matchmaking Not Working
1. Check that the queue room is properly registered
2. Verify database connection for storing match data

## Scaling

Railway supports horizontal scaling, but note:
- Each Colyseus room instance is stateful
- Use Railway's sticky sessions or implement Redis for cross-instance state
- Matchmaking across instances requires shared state

## Monitoring

Enable these Railway features:
- Metrics dashboard
- Log aggregation
- Alert notifications

## Support

For issues with the server deployment, check:
1. Railway status page
2. Server logs in Railway dashboard
3. MongoDB connection status
