'use strict';
const { MongoClient } = require('mongodb');
const cfg = require('./config'), { bad } = require('./util');
const C = {}; let client;
async function connect() {
  client = new MongoClient(cfg.MONGO_URL, { maxPoolSize: 30 }); await client.connect(); const db = client.db(cfg.DB_NAME);
  for (const n of ['users', 'follows', 'likes', 'friends', 'dms', 'dm_messages', 'chat_global', 'notifications', 'matches', 'tournaments', 'locks']) C[n] = db.collection(n);
  await Promise.all([
    C.users.createIndex({ nameLower: 1 }), C.users.createIndex({ email: 1 }, { unique: true, sparse: true }), C.users.createIndex({ googleId: 1 }, { unique: true, sparse: true }), C.users.createIndex({ shortId: 1 }, { unique: true }), C.users.createIndex({ trophies: -1 }),
    C.follows.createIndex({ a: 1, at: -1 }), C.follows.createIndex({ b: 1, at: -1 }), C.friends.createIndex({ users: 1, status: 1 }), C.friends.createIndex({ to: 1, status: 1 }),
    C.dms.createIndex({ users: 1, lastAt: -1 }), C.dm_messages.createIndex({ pair: 1, at: -1 }), C.chat_global.createIndex({ at: -1 }),
    C.notifications.createIndex({ uid: 1, t: -1 }), C.notifications.createIndex({ uid: 1, read: 1 }), C.matches.createIndex({ createdAt: 1 }, { expireAfterSeconds: 60 * 86400 }),
    C.tournaments.createIndex({ status: 1, startsAt: 1 }), C.tournaments.createIndex({ officialKey: 1, status: 1 }), C.tournaments.createIndex({ createdBy: 1, status: 1 }),
    C.locks.createIndex({ until: 1 }, { expireAfterSeconds: 0 })]);
  return C }
/* Optimistic transaction on ONE document: fn mutates a draft copy; the write only lands if nobody changed the doc meanwhile (field v). Every other writer MUST bump v ($inc v). */
async function mutate(col, id, fn, tries = 8) {
  for (;;) { const doc = await col.findOne({ _id: id }); if (!doc) throw bad('Not found', 404); const draft = structuredClone(doc), out = await fn(draft); draft.v = (doc.v || 0) + 1;
    const r = await col.replaceOne({ _id: id, v: doc.v || 0 }, draft); if (r.matchedCount === 1) return out; if (--tries <= 0) throw bad('Server busy, try again', 409) } }
/* cluster-safe "run once" for schedulers */
async function withLock(name, ttlMs, fn) { const until = new Date(Date.now() + ttlMs);
  try { const r = await C.locks.findOneAndUpdate({ _id: name, until: { $lt: new Date() } }, { $set: { until } }, { upsert: true }); void r } catch (e) { return false /* duplicate key => another node holds it */ }
  await fn(); return true }
module.exports = { C, connect, mutate, withLock, close: () => client && client.close() };
