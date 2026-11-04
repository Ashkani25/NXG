'use strict';
const { Room, ServerError } = require('@colyseus/core'), L = require('../lib'), { verifyTicket } = require('../auth'), { clean, limit } = require('../util'), U = require('../services/users'), MM = require('../services/match'), { C } = require('../db');
/* Custom room with a 5-letter code (public list or private). Host + 1 guest, ready flags, settings, room chat, host starts -> both receive a seat reservation for a MatchRoom. */
class GameRoom extends Room {
  maxClients = 2;
  onCreate(o) { this.code = o.code; this.hostId = o.hostId; this.view = { id: o.code, code: o.code, name: o.name, public: !!o.public, status: 'open', host: o.hostPub, guest: null, ready: { host: false, guest: false }, settings: o.settings, matchId: null };
    this.setMetadata({ code: o.code, name: o.name, public: !!o.public, hostPub: o.hostPub, settings: o.settings }); this.setPrivate(!o.public);
    this.onMessage('ready', (c, v) => { if (c.userData.role === 'guest') this.view.ready.guest = !!v; else this.view.ready.host = !!v; this.sync() });
    this.onMessage('update', (c, p) => { if (c.userData.role !== 'host' || this.view.status !== 'open' || !p) return; const v = this.view; if ('name' in p) v.name = clean(p.name, 24) || v.name; if ('public' in p) v.public = !!p.public; if ([180, 300, 420, 600].includes(+p.matchTime)) v.settings.matchTime = +p.matchTime; if (L.FIELDS.includes(p.field)) v.settings.field = p.field; v.ready = { host: false, guest: false }; this.setMetadata({ code: this.code, name: v.name, public: v.public, hostPub: v.host, settings: v.settings }); this.setPrivate(!v.public); this.sync() });
    this.onMessage('chat', (c, t) => { t = clean(t, 140); if (!t || !limit('rc:' + c.userData.uid, 8, 10000)) return; this.broadcast('chat', { id: Date.now() + '' + Math.random(), text: t, t: Date.now(), from: c.userData.pub }) });
    this.onMessage('start', async c => { try { if (c.userData.role !== 'host') throw new Error('Only the host can start'); const v = this.view; if (!v.guest) throw new Error('Waiting for a second player'); if (!v.ready.guest) throw new Error('Your opponent is not ready'); if (v.status === 'playing') return; v.status = 'playing';
      const made = await MM.create({ a: v.host.id, b: v.guest.id, friendly: true, roomCode: this.code, roomId: this.roomId, settings: v.settings }); v.matchId = made.matchId; this.sync();
      for (const cl of this.clients) cl.send('start', MM.viewFor(made.doc, cl.userData.uid, made.reservations[cl.userData.uid])) } catch (e) { this.view.status = 'open'; c.send('error', { message: e.message }) } }) }
  async onAuth(client, options) { const uid = verifyTicket(options && options.ticket, 'gameroom:' + this.code); if (!uid) throw new ServerError(403, 'Invalid room ticket'); const u = await C.users.findOne({ _id: uid }, { projection: { passHash: 0 } }); if (!u) throw new ServerError(404, 'No such player'); return { uid, pub: U.pub(u) } }
  onJoin(client, options, auth) { const a = auth || client.auth, role = a.uid === this.hostId ? 'host' : 'guest'; client.userData = { uid: a.uid, role, pub: a.pub }; if (role === 'guest') { this.view.guest = a.pub; this.view.ready.guest = false; this.lock() } else this.view.host = a.pub; this.sync() }
  onLeave(client) { const r = client.userData && client.userData.role; if (r === 'host') { this.broadcast('closed', {}); this.disconnect() } else if (r === 'guest') { this.view.guest = null; this.view.ready = { host: false, guest: false }; this.view.status = 'open'; this.view.matchId = null; this.unlock(); this.sync() } }
  matchDone() { this.view.status = 'open'; this.view.matchId = null; this.view.ready = { host: false, guest: false }; this.sync() }
  sync() { this.broadcast('state', this.view) }
}
module.exports = GameRoom;
