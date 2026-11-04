'use strict';
const { Room, ServerError } = require('@colyseus/core'), { verifyTicket } = require('../auth'), { C } = require('../db'), MM = require('../services/match');
/* One 2-player match. Physics run on the clients (relay), the server owns: who may join, the 5:00 clock, forfeits, and the final result (via services/match.js). */
const RELAY = ['shot', 'settled', 'goal', 'timeout', 'emote', 'ready', 'pause'];
class MatchRoom extends Room {
  maxClients = 2;
  async onCreate(options) { this.matchId = options.matchId; this.match = await C.matches.findOne({ _id: this.matchId }); if (!this.match) throw new Error('match doc missing'); this.setPrivate(true); this.joined = new Set(); this.startedAt = 0; this.left = new Set();
    for (const k of RELAY) this.onMessage(k, (c, m) => { if (k === 'emote' && typeof m === 'string' && m.length > 24) return; this.broadcast(k, m, { except: c }) });
    this.clock.setInterval(() => { if (this.startedAt) this.broadcast('clock', { left: Math.max(0, this.match.settings.matchTime - (Date.now() - this.startedAt) / 1000) }) }, 4000); this.autoDispose = true }
  onAuth(client, options) { const uid = verifyTicket(options && options.ticket, 'match:' + this.matchId); if (!uid || !this.match.players.includes(uid)) throw new ServerError(403, 'Not your match'); return { uid } }
  onJoin(client, options, auth) { const uid = (auth || client.auth).uid; client.userData = { uid }; this.joined.add(uid); if (this.joined.size === 2 && !this.startedAt) { this.startedAt = Date.now(); this.broadcast('peer', { t: this.startedAt }) } }
  async onLeave(client, consented) { const uid = client.userData && client.userData.uid; if (!uid) return;
    if (!consented) { try { await this.allowReconnection(client, 15); return } catch (e) { /* did not come back */ } }
    const doc = await C.matches.findOne({ _id: this.matchId }, { projection: { settled: 1, reports: 1 } }); if (doc && !doc.settled) { this.broadcast('leave', { uid }, { except: client }); this.clock.setTimeout(() => MM.forfeit(this.matchId, uid).catch(console.error), 12000) } }
}
module.exports = MatchRoom;
