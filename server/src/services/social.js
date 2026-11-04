'use strict';
const { C } = require('../db'), { bad, clean, now, limit } = require('../util'), U = require('./users'), { notify, push } = require('./notify');
const pairId = (a, b) => [a, b].sort().join('_');
const isDup = e => e && e.code === 11000;
/* ---------- follow / like ---------- */
async function follow(me, id, on) { if (me === id) throw bad('Cannot follow yourself'); const target = await U.getUser(id), _id = me + '_' + id;
  if (on) { try { await C.follows.insertOne({ _id, a: me, b: id, at: now() }) } catch (e) { if (isDup(e)) return { ok: true }; throw e } await U.bump(me, { following: 1 }); await U.bump(id, { followers: 1 }); const m = await U.getUser(me); await notify(id, 'New follower', m.name + ' started following you', 'follow', { id: me }) }
  else { const r = await C.follows.deleteOne({ _id }); if (r.deletedCount) { await U.bump(me, { following: -1 }); await U.bump(id, { followers: -1 }) } } void target; return { ok: true } }
async function like(me, id) { if (me === id) throw bad('You cannot like yourself'); await U.getUser(id); const _id = me + '_' + id; let liked = false;
  try { await C.likes.insertOne({ _id, a: me, b: id, at: now() }); liked = true } catch (e) { if (!isDup(e)) throw e }
  if (liked) { await U.bump(id, { likes: 1 }); const m = await U.getUser(me); await notify(id, 'New like', m.name + ' liked your profile', 'like', { id: me }) } else { await C.likes.deleteOne({ _id }); await U.bump(id, { likes: -1 }) } return { liked } }
async function state(me, id) { const [f1, f2, l, u] = await Promise.all([C.follows.findOne({ _id: me + '_' + id }), C.follows.findOne({ _id: id + '_' + me }), C.likes.findOne({ _id: me + '_' + id }), U.getUser(id)]);
  return { following: !!f1, followedBy: !!f2, liked: !!l, followers: u.followers || 0, followingCount: u.following || 0, likes: u.likes || 0 } }
async function list(kind, id) { const q = kind === 'followers' ? { b: id } : { a: id }, rows = await C.follows.find(q).sort({ at: -1 }).limit(60).toArray(); const ids = rows.map(r => kind === 'followers' ? r.a : r.b);
  const us = await C.users.find({ _id: { $in: ids } }, { projection: { passHash: 0 } }).toArray(); const by = new Map(us.map(u => [u._id, u])); return ids.map(i => by.get(i)).filter(Boolean).map(U.pub) }
/* ---------- friends ---------- */
async function friendAction(me, id, op, createRoomFn) { if (me === id) throw bad('Invalid'); const _id = pairId(me, id), meU = await U.getUser(me); await U.getUser(id);
  if (op === 'add') { const e = await C.friends.findOne({ _id }); if (e) throw bad(e.status === 'accepted' ? 'Already friends' : 'Request already sent'); await C.friends.insertOne({ _id, users: [me, id], from: me, to: id, status: 'pending', at: now() }); await notify(id, 'Friend request', meU.name + ' wants to be your friend', 'friend', { id: me }); return { ok: true } }
  if (op === 'accept') { const r = await C.friends.updateOne({ _id, to: me, status: 'pending' }, { $set: { status: 'accepted' } }); if (!r.matchedCount) throw bad('No request'); await notify(id, 'Friend request accepted', meU.name + ' is now your friend', 'friend', { id: me }); return { ok: true } }
  if (op === 'decline' || op === 'remove') { await C.friends.deleteOne({ _id }); return { ok: true } }
  if (op === 'invite') { const e = await C.friends.findOne({ _id, status: 'accepted' }); if (!e) throw bad('You can only invite friends'); const r = await createRoomFn(me, { name: meU.name + "'s room", public: false }); await notify(id, 'Match invite', meU.name + ' invited you to play. Room ' + r.code, 'invite', { code: r.code }); return r }
  throw bad('Bad op') }
const friends = async me => { const rows = await C.friends.find({ users: me, status: 'accepted' }).toArray(), ids = rows.map(r => r.users.find(x => x !== me)); const us = await C.users.find({ _id: { $in: ids } }, { projection: { passHash: 0 } }).toArray(); return us.map(U.pub) };
const requests = async me => { const rows = await C.friends.find({ to: me, status: 'pending' }).toArray(); const us = await C.users.find({ _id: { $in: rows.map(r => r.from) } }, { projection: { passHash: 0 } }).toArray(); return us.map(U.pub) };
const suggestions = async me => { const u = await U.getUser(me), us = await C.users.find({ _id: { $ne: me }, trophies: { $gte: Math.max(0, u.trophies - 300), $lte: u.trophies + 300 } }, { projection: { passHash: 0 } }).limit(12).toArray(); return us.map(U.pub) };
/* ---------- direct messages ---------- */
async function dmSend(me, id, text) { text = clean(text, 140); if (!text || id === me) throw bad('Invalid message'); if (!limit('dm:' + me, 12, 15000)) throw bad('Slow down', 429); const [u] = await Promise.all([U.getUser(me), U.getUser(id)]), pair = pairId(me, id), at = now();
  const m = { pair, uid: me, name: u.name, avatar: u.avatar, team: u.team, level: u.level, trophies: u.trophies, text, at }; const r = await C.dm_messages.insertOne(m);
  await C.dms.updateOne({ _id: pair }, { $set: { users: [me, id].sort(), last: text, lastAt: at, lastFrom: me }, $inc: { ['unread.' + id]: 1 }, $setOnInsert: { ['unread.' + me]: 0 } }, { upsert: true });
  push(id, 'dm', { id: String(r.insertedId), from: me, name: u.name, text, t: at.getTime() }); return { ok: true } }
const dmHistory = async (me, id) => { await U.getUser(id); const rows = await C.dm_messages.find({ pair: pairId(me, id) }).sort({ at: -1 }).limit(50).toArray(); await C.dms.updateOne({ _id: pairId(me, id) }, { $set: { ['unread.' + me]: 0 } }); return rows.reverse().map(m => ({ id: String(m._id), text: m.text, t: m.at.getTime(), mine: m.uid === me, from: { id: m.uid, name: m.name, avatar: m.avatar, team: m.team, level: m.level, trophies: m.trophies } })) };
async function inbox(me) { const rows = await C.dms.find({ users: me }).sort({ lastAt: -1 }).limit(40).toArray(), ids = rows.map(r => r.users.find(x => x !== me)); const us = await C.users.find({ _id: { $in: ids } }, { projection: { passHash: 0 } }).toArray(), by = new Map(us.map(u => [u._id, u]));
  return rows.map(r => { const oid = r.users.find(x => x !== me), o = by.get(oid); return { ch: 'dm:' + oid, other: o ? U.pub(o) : null, last: r.last || '', lastAt: r.lastAt ? r.lastAt.getTime() : 0, unread: (r.unread && r.unread[me]) || 0, mine: r.lastFrom === me } }) }
const unreadDm = async me => { const rows = await C.dms.find({ users: me }).toArray(); return rows.reduce((n, r) => n + ((r.unread && r.unread[me]) || 0), 0) };
/* ---------- global chat ---------- */
const globalHistory = async me => { const rows = await C.chat_global.find().sort({ at: -1 }).limit(50).toArray(); return rows.reverse().map(m => ({ id: String(m._id), text: m.text, t: m.at.getTime(), mine: m.uid === me, from: { id: m.uid, name: m.name, avatar: m.avatar, team: m.team, level: m.level, trophies: m.trophies } })) };
/* ---------- notifications ---------- */
const notifList = async me => (await C.notifications.find({ uid: me }).sort({ t: -1 }).limit(40).toArray()).map(n => ({ id: String(n._id), title: n.title, body: n.body, kind: n.kind, read: n.read, t: n.t.getTime(), data: n.data }));
module.exports = { follow, like, state, list, friendAction, friends, requests, suggestions, dmSend, dmHistory, inbox, unreadDm, globalHistory, notifList, pairId };
