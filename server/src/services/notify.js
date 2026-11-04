'use strict';
const { matchMaker } = require('@colyseus/core'), { C } = require('../db'), { now } = require('../util');
/* realtime push to a user's UserRoom(s) through Colyseus presence (works across processes when RedisPresence is used) */
const push = (uid, type, data) => { try { matchMaker.presence.publish('u:' + uid, { type, data }) } catch (e) { /* server not ready yet */ } };
async function notify(uid, title, body, kind, data) { const n = { uid, title, body, kind: kind || 'info', data: data || null, read: false, t: now() }; const r = await C.notifications.insertOne(n); push(uid, 'notif', Object.assign({ id: String(r.insertedId) }, n, { t: n.t.getTime() })); return n }
module.exports = { push, notify };
