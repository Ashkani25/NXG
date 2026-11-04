'use strict';
const http = require('http'), express = require('express'), cors = require('cors'), { Server } = require('@colyseus/core'), { WebSocketTransport } = require('@colyseus/ws-transport');
const cfg = require('./config'), db = require('./db'), api = require('./api'), T = require('./services/tournaments');
async function main() {
  await db.connect();
  const app = express(); app.set('trust proxy', 1); app.disable('x-powered-by');
  app.use(cors({ origin: cfg.CORS_ORIGIN.includes('*') ? true : cfg.CORS_ORIGIN })); app.use(express.json({ limit: '32kb' }));
  app.use('/', api);
  app.use((req, res) => res.status(404).json({ error: 'Not found' }));
  app.use((err, req, res, next) => { const s = err.status || 500; if (s >= 500) console.error(err); res.status(s).json({ error: s >= 500 ? 'Server error' : err.message }) });
  const server = http.createServer(app), game = new Server({ transport: new WebSocketTransport({ server, pingInterval: 5000, pingMaxRetries: 3 }) });
  game.define('queue', require('./rooms/QueueRoom')); game.define('match', require('./rooms/MatchRoom')); game.define('gameroom', require('./rooms/GameRoom')); game.define('chat', require('./rooms/ChatRoom')); game.define('user', require('./rooms/UserRoom')).filterBy(['uid']);
  await game.listen(cfg.PORT); console.log('[BERMUDA NXG] server on :' + cfg.PORT);
  const every = (name, ms, fn) => setInterval(() => db.withLock(name, ms - 2000, fn).catch(e => console.error(name, e)), ms).unref();
  every('tour-tick', 60000, () => T.tick()); every('tour-seed', 3600000, () => T.seedOfficial()); T.seedOfficial().catch(console.error);
  const stop = async () => { try { await game.gracefullyShutdown(false) } catch (e) { } await db.close(); process.exit(0) }; process.on('SIGINT', stop); process.on('SIGTERM', stop);
}
main().catch(e => { console.error(e); process.exit(1) });
