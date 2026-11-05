'use strict';
const http = require('http');
const path = require('path');
const express = require('express');
const cors = require('cors');
const { Server } = require('@colyseus/core');
const { WebSocketTransport } = require('@colyseus/ws-transport');

const cfg = require('./config');
const { supabase } = require('./supabase');
const api = require('./api');
const T = require('./services/tournaments');

// Import rooms
const GameRoom = require('./rooms/GameRoom');
const MatchRoom = require('./rooms/MatchRoom');
const QueueRoom = require('./rooms/QueueRoom');
const SpectatorRoom = require('./rooms/SpectatorRoom');
const ChatRoom = require('./rooms/ChatRoom');
const UserRoom = require('./rooms/UserRoom');

async function main() {
  const app = express();
  
  // Trust proxy for proper IP detection
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  
  // CORS configuration
  app.use(cors({ 
    origin: cfg.CORS_ORIGIN.includes('*') ? true : cfg.CORS_ORIGIN,
    credentials: true
  }));
  
  // JSON body parser
  app.use(express.json({ limit: '32kb' }));
  
  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ 
      status: 'ok', 
      version: '2.0.0',
      uptime: process.uptime(),
      timestamp: Date.now()
    });
  });
  
  // Serve static files from parent dist folder (web version)
  const distPath = path.join(__dirname, '..', '..', 'dist');
  app.use(express.static(distPath));
  
  // API routes
  app.use('/', api);
  
  // 404 handler
  app.use((req, res) => {
    // For API routes, return JSON 404
    if (req.path.startsWith('/')) {
      res.status(404).json({ error: 'Not found' });
    } else {
      // For other routes, serve index.html (SPA support)
      res.sendFile(path.join(distPath, 'index.html'));
    }
  });
  
  // Error handler
  app.use((err, req, res, next) => {
    const s = err.status || 500;
    if (s >= 500) console.error('[Server Error]', err);
    res.status(s).json({ error: s >= 500 ? 'Server error' : err.message });
  });
  
  // Create HTTP server
  const server = http.createServer(app);
  
  // Create Colyseus server with WebSocket transport
  const gameServer = new Server({
    transport: new WebSocketTransport({
      server,
      pingInterval: 5000,
      pingMaxRetries: 3,
      maxPayload: 1024 * 1024 // 1MB max message
    })
  });
  
  // Register rooms
  gameServer.define('queue', QueueRoom);
  gameServer.define('match', MatchRoom);
  gameServer.define('gameroom', GameRoom);
  gameServer.define('spectator', SpectatorRoom);
  gameServer.define('chat', ChatRoom);
  gameServer.define('user', UserRoom).filterBy(['uid']);
  
  // Start server
  await gameServer.listen(cfg.PORT);
  console.log('[BERMUDA NXG] Server started on port ' + cfg.PORT);
  console.log('[BERMUDA NXG] Environment: ' + (cfg.PROD ? 'PRODUCTION' : 'DEVELOPMENT'));
  console.log('[BERMUDA NXG] Database: Supabase');
  
  // Graceful shutdown
  const stop = async () => {
    console.log('[BERMUDA NXG] Shutting down...');
    try {
      await gameServer.gracefullyShutdown(false);
    } catch (e) {}
    process.exit(0);
  };
  
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  
  console.log('[BERMUDA NXG] Ready for connections');
}

main().catch(e => {
  console.error('[BERMUDA NXG] Failed to start:', e);
  process.exit(1);
});