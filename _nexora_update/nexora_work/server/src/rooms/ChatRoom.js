'use strict';
const { Room, ServerError } = require('@colyseus/core'), { verifyToken } = require('../auth'), { C } = require('../db'), { clean, limit, now } = require('../util');
/* Global chat (singleton). Messages are validated, rate-limited, stored in Mongo and broadcast. History is served by REST GET /chat/global. */
class ChatRoom extends Room {
  maxClients = 3000;
  onCreate() { this.autoDispose = false; this.onMessage('say', async (c, text) => { const u = c.userData; text = clean(text, 140); if (!text || !limit('chat:' + u.uid, 6, 8000)) return; const at = now(), m = { uid: u.uid, name: u.name, avatar: u.avatar, team: u.team, level: u.level, trophies: u.trophies, text, at }; const r = await C.chat_global.insertOne(m);
    this.broadcast('msg', { id: String(r.insertedId), text, t: at.getTime(), from: { id: u.uid, name: u.name, avatar: u.avatar, team: u.team, level: u.level, trophies: u.trophies } }) }) }
  async onAuth(client, options) { const uid = verifyToken(options && options.token); if (!uid) throw new ServerError(401, 'Please sign in'); const u = await C.users.findOne({ _id: uid }); if (!u || u.banned) throw new ServerError(403, 'Not allowed'); return { uid, name: u.name, avatar: u.avatar, team: u.team, level: u.level, trophies: u.trophies } }
  onJoin(client, options, auth) { client.userData = auth || client.auth }
}
module.exports = ChatRoom;
