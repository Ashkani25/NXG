'use strict';
const { Room, ServerError, matchMaker } = require('@colyseus/core'), { verifyToken } = require('../auth');
/* One private room per user (filterBy uid). Carries realtime pushes: notifications, DMs, tournament matchReady, and marks the user online. */
class UserRoom extends Room {
  maxClients = 6;
  async onAuth(client, options) { const uid = verifyToken(options && options.token); if (!uid || uid !== options.uid) throw new ServerError(401, 'Please sign in'); return { uid } }
  onCreate(o) { this.uid = o.uid; this.autoDispose = true; this.sub = (msg) => { if (msg && msg.type) this.broadcast(msg.type, msg.data) }; matchMaker.presence.subscribe('u:' + this.uid, this.sub) }
  async onJoin() { try { await matchMaker.presence.hincrby('online', this.uid, 1) } catch (e) { } }
  async onLeave() { try { const n = await matchMaker.presence.hincrby('online', this.uid, -1); if (n <= 0) await matchMaker.presence.hdel('online', this.uid) } catch (e) { } }
  onDispose() { try { matchMaker.presence.unsubscribe('u:' + this.uid, this.sub) } catch (e) { } }
}
module.exports = UserRoom;
