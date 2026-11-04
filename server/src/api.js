'use strict';
const express = require('express'), { matchMaker } = require('@colyseus/core'), L = require('./lib'), cfg = require('./config'), { C, mutate } = require('./db'), { bad, clean, limit } = require('./util'),
  A = require('./auth'), U = require('./services/users'), E = require('./services/economy'), S = require('./services/social'), MM = require('./services/match'), R = require('./services/rooms'), T = require('./services/tournaments'), AI = require('./services/ai');

const r = express.Router();

const h = fn => (req, res, next) => Promise.resolve(fn(req, res)).then(v => res.json(v === undefined ? { ok: true } : v)).catch(next);

const needIp = (req, key, n, ms) => {
  if (!limit(key + ':' + req.ip, n, ms)) throw bad('Too many attempts, wait a minute', 429);
};

const session = u => ({ token: A.signToken(u._id), user: { id: u._id, email: u.email || null, guest: !!u.guest } });

const online = async () => { try { return await matchMaker.presence.hlen('online') } catch (e) { return 0 } };

const emailOk = e => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) && e.length <= 120;

/* ----- auth ----- */
r.post('/auth/guest', h(async (req) => {
  needIp(req, 'auth', 20, 60000);
  const u = U.newUser({ guest: true, name: req.body.name });
  await C.users.insertOne(u);
  return session(u);
}));

r.post('/auth/register', h(async (req) => {
  needIp(req, 'auth', 20, 60000);
  const email = clean(req.body.email, 120).toLowerCase();
  const pw = String(req.body.password || '');
  if (!emailOk(email)) throw bad('Enter a valid email');
  if (pw.length < 6 || pw.length > 72) throw bad('Password must be 6-72 characters');
  
  const u = U.newUser({ email, passHash: await A.hash(pw), name: req.body.name });
  try {
    await C.users.insertOne(u);
  } catch (e) {
    if (e.code === 11000) throw bad('This email is already registered', 409);
    throw e;
  }
  return session(u);
}));

r.post('/auth/login', h(async (req) => {
  needIp(req, 'auth', 20, 60000);
  const email = clean(req.body.email, 120).toLowerCase();
  const u = await C.users.findOne({ email });
  if (!u || !u.passHash || !(await A.same(String(req.body.password || ''), u.passHash))) {
    throw bad('Wrong email or password', 401);
  }
  if (u.banned) throw bad('Account suspended', 403);
  return session(u);
}));

r.post('/auth/username', h(async (req) => {
  // Simple username-based login for quick play
  needIp(req, 'auth', 20, 60000);
  const name = clean(req.body.username, 16) || 'Player';
  
  // Find existing user or create new
  let u = await C.users.findOne({ nameLower: name.toLowerCase() });
  if (!u) {
    u = U.newUser({ guest: true, name });
    await C.users.insertOne(u);
  }
  if (u.banned) throw bad('Account suspended', 403);
  
  return session(u);
}));

r.delete('/auth/account', A.requireUser, h(async (req) => {
  const id = req.uid;
  await Promise.all([
    C.users.deleteOne({ _id: id }),
    C.notifications.deleteMany({ uid: id }),
    C.follows.deleteMany({ $or: [{ a: id }, { b: id }] }),
    C.likes.deleteMany({ $or: [{ a: id }, { b: id }] }),
    C.friends.deleteMany({ users: id }),
    C.dms.deleteMany({ users: id })
  ]);
  return { ok: true };
}));

/* ----- health check ----- */
r.get('/health', (req, res) => {
  res.json({ ok: true, t: Date.now(), uptime: process.uptime() });
});

r.use(A.requireUser);

/* ----- profile ----- */
r.get('/me', h(async req => U.me(req.user)));

r.patch('/me', h(async req => {
  const b = req.body || {}, set = {};
  if ('name' in b) {
    const n = clean(b.name, 16);
    if (!n) throw bad('Name required');
    set.name = n;
    set.nameLower = n.toLowerCase();
  }
  if ('avatar' in b) set.avatar = clean(b.avatar, 30);
  if ('team' in b) set.team = clean(b.team, 30);
  if ('form' in b) {
    const f = b.form | 0;
    if (f < 0 || f > 11) throw bad('Bad formation');
    set.form = f;
  }
  if ('bio' in b) set.bio = clean(b.bio, 80);
  if ('country' in b) set.country = clean(b.country, 3).toUpperCase();
  
  await C.users.updateOne({ _id: req.uid }, { $set: set, $inc: { v: 1 } });
  return U.me(await U.getUser(req.uid));
}));

r.get('/users/search', h(async req => {
  const q = clean(req.query.q, 20).toLowerCase();
  if (q.length < 2) return [];
  const esc = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const f = /^nx-/.test(q) ? { shortId: q.toUpperCase() } : { nameLower: { $regex: '^' + esc } };
  return (await C.users.find(Object.assign({ _id: { $ne: req.uid } }, f), { projection: { passHash: 0 } }).limit(20).toArray()).map(U.pub);
}));

r.get('/users/:id', h(async req => {
  const u = await U.getUser(req.params.id);
  let on = false;
  try { on = !!(await matchMaker.presence.hget('online', u._id)) } catch (e) { }
  return Object.assign(U.pub(u), { online: on });
}));

/* ----- rooms ----- */
r.get('/rooms', h(() => R.list()));
r.post('/rooms', h(req => R.create(req.uid, req.body || {})));
r.post('/rooms/join', h(req => R.join(req.uid, req.body.code)));
r.get('/rooms/active', h(async () => ({ count: await R.activeCount() })));

/* ----- matchmaking ----- */
r.post('/matchmaking/join', h(async (req) => {
  const mode = req.body.mode || '1v1';
  return { mode, status: 'queued' };
}));

r.post('/matchmaking/cancel', h(async (req) => {
  return { status: 'canceled' };
}));

/* ----- matches ----- */
r.post('/match/report', h(req => MM.report(req.uid, req.body || {})));
r.get('/matches/history', h(async req => {
  const matches = await C.matches.find({ players: req.uid }).sort({ createdAt: -1 }).limit(50).toArray();
  return matches.map(m => ({
    id: m._id,
    mode: m.mode,
    score: [m.team0Score || 0, m.team1Score || 0],
    won: m.winner === (m.teams?.[0]?.includes(req.uid) ? 0 : 1),
    date: m.createdAt,
    ranked: m.ranked
  }));
}));

/* ----- economy ----- */
r.get('/economy/daily', h(async req => E.dailyStatus(req.user)));
r.post('/economy/daily/claim', h(async req => {
  const x = await E.claimDaily(req.uid);
  return { reward: x.reward, status: E.dailyStatus(await U.getUser(req.uid)) };
}));

r.get('/economy/quests', h(async req => (await E.quests(req.uid)).list));
r.post('/economy/quests/:id/claim', h(req => E.claimQuest(req.uid, req.params.id)));

r.get('/leaderboard', h(async () =>
  (await C.users.find({}, { projection: { passHash: 0 } }).sort({ trophies: -1 }).limit(50).toArray())
    .map((u, i) => Object.assign(U.pub(u), { rank: i + 1 }))
));

r.get('/leaderboard/me', h(async req => ({
  rank: (await C.users.countDocuments({ trophies: { $gt: req.user.trophies } })) + 1,
  trophies: req.user.trophies
})));

/* ----- social ----- */
r.get('/social/:id', h(req => S.state(req.uid, req.params.id)));
r.post('/social/:id/follow', h(req => S.follow(req.uid, req.params.id, true)));
r.delete('/social/:id/follow', h(req => S.follow(req.uid, req.params.id, false)));
r.post('/social/:id/like', h(req => S.like(req.uid, req.params.id)));

r.get('/social/:id/:kind(followers|following)', h(req => S.list(req.params.kind, req.params.id === 'me' ? req.uid : req.params.id)));

r.get('/friends', h(async req => {
  const l = await S.friends(req.uid);
  for (const p of l) {
    try { p.online = !!(await matchMaker.presence.hget('online', p.id)) } catch (e) { p.online = false }
  }
  return l.sort((a, b) => b.online - a.online);
}));

r.get('/friends/requests', h(req => S.requests(req.uid)));
r.get('/friends/suggestions', h(req => S.suggestions(req.uid)));
r.post('/friends/:id/:op(add|accept|decline|invite)', h(req => S.friendAction(req.uid, req.params.id, req.params.op, R.create)));
r.delete('/friends/:id', h(req => S.friendAction(req.uid, req.params.id, 'remove')));

/* ----- messages ----- */
r.get('/chat/global', h(req => S.globalHistory(req.uid)));
r.get('/dm', h(req => S.inbox(req.uid)));
r.get('/dm/unread', h(async req => ({ n: await S.unreadDm(req.uid) })));
r.get('/dm/:id', h(req => S.dmHistory(req.uid, req.params.id)));
r.post('/dm/:id', h(req => S.dmSend(req.uid, req.params.id, req.body.text)));

r.get('/notifications', h(req => S.notifList(req.uid)));
r.get('/notifications/unread', h(async req => ({ n: await C.notifications.countDocuments({ uid: req.uid, read: false }) })));
r.post('/notifications/read', h(async req => { await C.notifications.updateMany({ uid: req.uid, read: false }, { $set: { read: true } }) }));

/* ----- tournaments ----- */
r.get('/tournaments', h(req => T.list(req.uid, req.user.level)));
r.post('/tournaments', h(req => T.create(req.uid, req.body || {})));
r.get('/tournaments/:id', h(req => T.get(req.uid, req.user.level, req.params.id)));
r.post('/tournaments/:id/join', h(req => T.join(req.uid, req.params.id)));
r.post('/tournaments/:id/leave', h(req => T.leave(req.uid, req.params.id)));
r.post('/tournaments/:id/ready', h(req => T.ready(req.uid, req.params.id)));
r.post('/tournaments/:id/unready', h(req => T.unready(req.uid, req.params.id)));

/* ----- AI ----- */
r.post('/ai', h(req => AI.ask(req.uid, req.body.messages)));

/* ----- stats ----- */
r.get('/stats/online', h(async () => ({ n: await online() })));

module.exports = r;
