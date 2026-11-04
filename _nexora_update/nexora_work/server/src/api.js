'use strict';
const express = require('express'), { matchMaker } = require('@colyseus/core'), L = require('./lib'), cfg = require('./config'), { C, mutate } = require('./db'), { bad, clean, limit } = require('./util'),
  A = require('./auth'), U = require('./services/users'), E = require('./services/economy'), S = require('./services/social'), MM = require('./services/match'), R = require('./services/rooms'), T = require('./services/tournaments'), AI = require('./services/ai');
const r = express.Router(), h = fn => (req, res, next) => Promise.resolve(fn(req, res)).then(v => res.json(v === undefined ? { ok: true } : v)).catch(next), needIp = (req, key, n, ms) => { if (!limit(key + ':' + req.ip, n, ms)) throw bad('Too many attempts, wait a minute', 429) };
const session = u => ({ token: A.signToken(u._id), user: { id: u._id, email: u.email || null, guest: !!u.guest } });
const online = async () => { try { return await matchMaker.presence.hlen('online') } catch (e) { return 0 } };
const emailOk = e => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) && e.length <= 120;
/* ----- auth ----- */
r.post('/auth/guest', h(async (req) => { needIp(req, 'auth', 20, 60000); const u = U.newUser({ guest: true, name: req.body.name }); await C.users.insertOne(u); return session(u) }));
r.post('/auth/register', h(async (req) => { needIp(req, 'auth', 20, 60000); const email = clean(req.body.email, 120).toLowerCase(), pw = String(req.body.password || ''); if (!emailOk(email)) throw bad('Enter a valid email'); if (pw.length < 6 || pw.length > 72) throw bad('Password must be 6-72 characters');
  const u = U.newUser({ email, passHash: await A.hash(pw), name: req.body.name }); try { await C.users.insertOne(u) } catch (e) { if (e.code === 11000) throw bad('This email is already registered', 409); throw e } return session(u) }));
r.post('/auth/login', h(async (req) => { needIp(req, 'auth', 20, 60000); const email = clean(req.body.email, 120).toLowerCase(), u = await C.users.findOne({ email }); if (!u || !u.passHash || !(await A.same(String(req.body.password || ''), u.passHash))) throw bad('Wrong email or password', 401); if (u.banned) throw bad('Account suspended', 403); return session(u) }));
r.post('/auth/google', h(async (req) => { needIp(req, 'auth', 20, 60000); const g = await A.verifyGoogle(String(req.body.idToken || '')); let u = await C.users.findOne({ googleId: g.googleId }) || (g.email && await C.users.findOne({ email: g.email.toLowerCase() }));
  if (u && !u.googleId) { await C.users.updateOne({ _id: u._id }, { $set: { googleId: g.googleId }, $inc: { v: 1 } }) } if (!u) { u = U.newUser({ email: g.email && g.email.toLowerCase(), googleId: g.googleId, name: g.name }); await C.users.insertOne(u) } return session(u) }));
r.post('/auth/link', A.requireUser, h(async (req) => { const email = clean(req.body.email, 120).toLowerCase(), pw = String(req.body.password || ''); if (!emailOk(email) || pw.length < 6) throw bad('Enter a valid email and a password of 6+ characters');
  try { await mutate(C.users, req.uid, async u => { if (!u.guest) throw bad('Already an account'); u.email = email; u.passHash = await A.hash(pw); u.guest = false }) } catch (e) { if (e.code === 11000) throw bad('This email is already registered', 409); throw e } return { ok: true } }));
r.delete('/auth/account', A.requireUser, h(async (req) => { const id = req.uid; await Promise.all([C.users.deleteOne({ _id: id }), C.notifications.deleteMany({ uid: id }), C.follows.deleteMany({ $or: [{ a: id }, { b: id }] }), C.likes.deleteMany({ $or: [{ a: id }, { b: id }] }), C.friends.deleteMany({ users: id }), C.dms.deleteMany({ users: id })]); return { ok: true } }));
r.get('/health', (req, res) => res.json({ ok: true, t: Date.now() }));
r.use(A.requireUser);
/* ----- profile ----- */
r.get('/me', h(async req => U.me(req.user)));
r.patch('/me', h(async req => { const b = req.body || {}, set = {}; if ('name' in b) { const n = clean(b.name, 16); if (!n) throw bad('Name required'); set.name = n; set.nameLower = n.toLowerCase() } if ('avatar' in b) set.avatar = clean(b.avatar, 30); if ('team' in b) set.team = clean(b.team, 30); if ('form' in b) { const f = b.form | 0; if (f < 0 || f > 11) throw bad('Bad formation'); set.form = f }
  if ('bio' in b) set.bio = clean(b.bio, 80); if ('country' in b) set.country = clean(b.country, 3).toUpperCase(); await C.users.updateOne({ _id: req.uid }, { $set: set, $inc: { v: 1 } }); return U.me(await U.getUser(req.uid)) }));
r.get('/users/search', h(async req => { const q = clean(req.query.q, 20).toLowerCase(); if (q.length < 2) return []; const esc = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); const f = /^nx-/.test(q) ? { shortId: q.toUpperCase() } : { nameLower: { $regex: '^' + esc } };
  return (await C.users.find(Object.assign({ _id: { $ne: req.uid } }, f), { projection: { passHash: 0 } }).limit(20).toArray()).map(U.pub) }));
r.get('/users/:id', h(async req => { const u = await U.getUser(req.params.id); let on = false; try { on = !!(await matchMaker.presence.hget('online', u._id)) } catch (e) { } return Object.assign(U.pub(u), { online: on }) }));
/* ----- economy / shop / leaderboard ----- */
r.get('/economy/daily', h(async req => E.dailyStatus(req.user)));
r.post('/economy/daily/claim', h(async req => { const x = await E.claimDaily(req.uid); return { reward: x.reward, status: E.dailyStatus(await U.getUser(req.uid)) } }));
r.get('/economy/quests', h(async req => (await E.quests(req.uid)).list));
r.post('/economy/quests/:id/claim', h(async req => E.claimQuest(req.uid, req.params.id)));
r.post('/shop/buy', h(async req => E.buy(req.uid, req.body.id)));
r.post('/shop/equip', h(async req => E.equip(req.uid, req.body.type, req.body.key)));
r.post('/shop/chest', h(async req => E.chest(req.uid, clean(req.body.key, 10))));
r.get('/leaderboard', h(async () => (await C.users.find({}, { projection: { passHash: 0 } }).sort({ trophies: -1 }).limit(50).toArray()).map((u, i) => Object.assign(U.pub(u), { rank: i + 1 }))));
r.get('/leaderboard/me', h(async req => ({ rank: (await C.users.countDocuments({ trophies: { $gt: req.user.trophies } })) + 1, trophies: req.user.trophies })));
/* ----- social ----- */
r.get('/social/:id', h(req => S.state(req.uid, req.params.id)));
r.post('/social/:id/follow', h(req => S.follow(req.uid, req.params.id, true)));
r.delete('/social/:id/follow', h(req => S.follow(req.uid, req.params.id, false)));
r.post('/social/:id/like', h(req => S.like(req.uid, req.params.id)));
r.get('/social/:id/:kind(followers|following)', h(req => S.list(req.params.kind, req.params.id === 'me' ? req.uid : req.params.id)));
r.get('/friends', h(async req => { const l = await S.friends(req.uid); for (const p of l) { try { p.online = !!(await matchMaker.presence.hget('online', p.id)) } catch (e) { p.online = false } } return l.sort((a, b) => b.online - a.online) }));
r.get('/friends/requests', h(req => S.requests(req.uid)));
r.get('/friends/suggestions', h(req => S.suggestions(req.uid)));
r.post('/friends/:id/:op(add|accept|decline|invite)', h(req => S.friendAction(req.uid, req.params.id, req.params.op, R.create)));
r.delete('/friends/:id', h(req => S.friendAction(req.uid, req.params.id, 'remove')));
/* ----- messages / notifications ----- */
r.get('/chat/global', h(req => S.globalHistory(req.uid)));
r.get('/dm', h(req => S.inbox(req.uid)));
r.get('/dm/unread', h(async req => ({ n: await S.unreadDm(req.uid) })));
r.get('/dm/:id', h(req => S.dmHistory(req.uid, req.params.id)));
r.post('/dm/:id', h(req => S.dmSend(req.uid, req.params.id, req.body.text)));
r.get('/notifications', h(req => S.notifList(req.uid)));
r.get('/notifications/unread', h(async req => ({ n: await C.notifications.countDocuments({ uid: req.uid, read: false }) })));
r.post('/notifications/read', h(async req => { await C.notifications.updateMany({ uid: req.uid, read: false }, { $set: { read: true } }) }));
/* ----- rooms / tournaments / match / ai ----- */
r.get('/rooms', h(() => R.list()));
r.post('/rooms', h(req => R.create(req.uid, req.body || {})));
r.post('/rooms/join', h(req => R.join(req.uid, req.body.code)));
r.get('/tournaments', h(req => T.list(req.uid, req.user.level)));
r.post('/tournaments', h(req => T.create(req.uid, req.body || {})));
r.get('/tournaments/:id', h(req => T.get(req.uid, req.user.level, req.params.id)));
r.post('/tournaments/:id/join', h(req => T.join(req.uid, req.params.id)));
r.post('/tournaments/:id/leave', h(req => T.leave(req.uid, req.params.id)));
r.post('/tournaments/:id/ready', h(req => T.ready(req.uid, req.params.id)));
r.post('/tournaments/:id/unready', h(req => T.unready(req.uid, req.params.id)));
r.post('/match/report', h(req => MM.report(req.uid, req.body || {})));
r.post('/ai', h(req => AI.ask(req.uid, req.body.messages)));
r.get('/stats/online', h(async () => ({ n: await online() })));
module.exports = r;
