'use strict';
const { Room, matchMaker } = require('@colyseus/core'), { verifyToken } = require('../auth'), { C } = require('../db'), U = require('../services/users'), MM = require('../services/match'), { ServerError } = require('@colyseus/core');
/* Ranked matchmaking queue. One singleton room: players join with their JWT, the server pairs them by trophies (window widens 25/sec) and sends a seat reservation for a fresh 'match' room. */
class QueueRoom extends Room {
  maxClients = 2000;
  onCreate() { this.waiting = new Map(); this.autoDispose = false; this.clock.setInterval(() => this.pair().catch(e => console.error('queue', e)), 1000); this.onMessage('cancel', c => c.leave()) }
  async onAuth(client, options) { const uid = verifyToken(options && options.token); if (!uid) throw new ServerError(401, 'Please sign in'); const u = await C.users.findOne({ _id: uid }, { projection: { trophies: 1, banned: 1 } }); if (!u || u.banned) throw new ServerError(403, 'Not allowed'); return { uid, trophies: u.trophies } }
  onJoin(client, options, auth) { const a = auth || client.auth; for (const [sid, w] of this.waiting) if (w.uid === a.uid) { w.client.leave(); this.waiting.delete(sid) } this.waiting.set(client.sessionId, { uid: a.uid, trophies: a.trophies, joinedAt: Date.now(), client }); client.send('queued', { players: this.waiting.size }) }
  onLeave(client) { this.waiting.delete(client.sessionId) }
  async pair() { const list = [...this.waiting.values()].sort((x, y) => x.joinedAt - y.joinedAt), used = new Set();
    for (const me of list) { if (used.has(me.uid)) continue; let best = null, bd = 1e9;
      for (const o of list) { if (o === me || used.has(o.uid) || o.uid === me.uid) continue; const diff = Math.abs(o.trophies - me.trophies), wait = (Date.now() - Math.min(me.joinedAt, o.joinedAt)) / 1000, allow = 200 + 25 * wait; if (diff <= allow && diff < bd) { best = o; bd = diff } }
      if (!best) continue; used.add(me.uid); used.add(best.uid); const host = Math.random() < .5 ? [me, best] : [best, me];
      try { const made = await MM.create({ a: host[0].uid, b: host[1].uid, ranked: true }); for (const w of [me, best]) { w.client.send('matched', MM.viewFor(made.doc, w.uid, made.reservations[w.uid])); this.waiting.delete(w.client.sessionId) } }
      catch (e) { console.error('pairing failed', e); used.delete(me.uid); used.delete(best.uid) } } }
}
module.exports = QueueRoom;
