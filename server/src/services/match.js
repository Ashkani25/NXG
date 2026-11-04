'use strict';
const { ObjectId } = require('mongodb'), { matchMaker } = require('@colyseus/core'), L = require('../lib'), { C, mutate } = require('../db'), { bad, now } = require('../util'), U = require('./users'), { signTicket } = require('../auth'), economy = require('./economy');
/* creates the match document + the Colyseus 'match' room + one seat reservation per player */
async function create(o) { const [a, b] = [o.a, o.b], [ua, ub] = await Promise.all([U.getUser(a), U.getUser(b)]), _id = new ObjectId().toHexString();
  const settings = Object.assign({ field: ua.equip.field, ball: ua.equip.ball, matchTime: 300, turnTime: 15 }, o.settings || {});
  const doc = { _id, v: 0, players: [a, b], hostId: a, pub: { [a]: U.pub(ua), [b]: U.pub(ub) }, settings, ranked: !!o.ranked, friendly: !!o.friendly, tournamentId: o.tournamentId || null, fixtureId: o.fixtureId || null, roomCode: o.roomCode || null, roomId: o.roomId || null, status: 'playing', reports: {}, createdAt: now() };
  await C.matches.insertOne(doc); const room = await matchMaker.createRoom('match', { matchId: _id }), reservations = {};
  for (const uid of [a, b]) reservations[uid] = await matchMaker.reserveSeatFor(room, { uid, ticket: signTicket(uid, 'match:' + _id) });
  return { matchId: _id, doc, reservations } }
const viewFor = (doc, uid, reservation) => { const oid = doc.players.find(x => x !== uid); return { matchId: doc._id, role: doc.hostId === uid ? 'host' : 'guest', opponent: doc.pub[oid], settings: doc.settings, ranked: doc.ranked, friendly: doc.friendly, tournamentId: doc.tournamentId, oppTrophies: doc.pub[oid].trophies, reservation } };
/* result report from one player. Rewards are computed HERE; the client only says what it saw. */
async function report(uid, d) { const gf = Math.max(0, Math.min(60, d.goalsFor | 0)), ga = Math.max(0, Math.min(60, d.goalsAgainst | 0)), won = !!d.won; if (won && gf <= ga) throw bad('Invalid result');
  let m = null, bot = false, ranked = false, friendly = false, tournament = false, oppTr = null, disputed = false;
  if (d.matchId) { m = await C.matches.findOne({ _id: String(d.matchId) }); if (!m || !m.players.includes(uid)) throw bad('Match not found', 404); if (m.reports && m.reports[uid]) throw bad('Already reported');
    const age = (Date.now() - m.createdAt.getTime()) / 1000; if (won && age < 60) throw bad('Result rejected (match too short)'); ranked = m.ranked; friendly = m.friendly; tournament = !!m.tournamentId;
    const oid = m.players.find(x => x !== uid); oppTr = m.pub[oid].trophies; const opp = m.reports && m.reports[oid]; if (opp && (opp.gf !== ga || opp.ga !== gf)) disputed = true;
    const r = await C.matches.updateOne({ _id: m._id, ['reports.' + uid]: { $exists: false } }, { $set: Object.assign({ ['reports.' + uid]: { gf, ga, won, t: now() } }, disputed ? { disputed: true } : {}) }); if (!r.matchedCount) throw bad('Already reported') }
  else if (d.mode !== 'bot') throw bad('Missing matchId'); else bot = true;
  const out = await mutate(C.users, uid, u => { if (oppTr == null) oppTr = u.trophies;
    if (bot) { const b = u.bots && u.bots.date === L.today() ? u.bots : { date: L.today(), n: 0 }; if (b.n >= 15) return { xp: 0, coins: 0, trophies: 0, totalTrophies: u.trophies, level: u.level, levelUp: false, levelsGained: 0, xpNow: u.xp, levelBefore: u.level, note: 'Daily bot reward limit reached' }; u.bots = { date: b.date, n: b.n + 1 } }
    const rw = L.matchRewards({ won, gf, ranked, friendly, tournament, bot }); let dt = ranked && !disputed ? L.trophyDelta(u.trophies, oppTr, won) : 0; const tr = Math.max(0, u.trophies + dt); dt = tr - u.trophies; const before = u.level;
    u.stats.played++; u.stats.goals += gf; u.stats.conceded += ga; if (won) { u.stats.wins++; u.stats.streak++; u.stats.best = Math.max(u.stats.best, u.stats.streak) } else { u.stats.losses++; u.stats.streak = 0 }
    const up = L.addXp(u, disputed ? 0 : rw.xp); if (!disputed) u.coins += rw.coins; u.trophies = tr; economy.ensureQuests(u);
    for (const q of u.quests.list) { if (q.type === 'play') q.have = Math.min(q.need, q.have + 1); if (q.type === 'win' && won) q.have = Math.min(q.need, q.have + 1); if (q.type === 'goals') q.have = Math.min(q.need, q.have + gf) }
    return { xp: disputed ? 0 : rw.xp, coins: disputed ? 0 : rw.coins, trophies: dt, totalTrophies: tr, level: u.level, levelUp: up > 0, levelsGained: up, xpNow: u.xp, levelBefore: before, disputed } });
  if (m) settle(m._id).catch(e => console.error('settle', e)); return out }
/* decide the final winner once enough reports exist; then reopen the custom room / advance the tournament (once) */
async function settle(matchId) { const m = await C.matches.findOne({ _id: matchId }); if (!m || m.settled) return null; const [a, b] = m.players, ra = m.reports && m.reports[a], rb = m.reports && m.reports[b]; let win = null, sa = 0, sb = 0;
  if (ra && rb && ra.gf === rb.ga && ra.ga === rb.gf) { sa = ra.gf; sb = ra.ga; win = sa > sb ? a : b }
  else if (ra && rb) { const x = ra.won ? a : rb.won ? b : null; if (x) { win = x; sa = x === a ? ra.gf : rb.ga; sb = x === a ? ra.ga : rb.gf } else { win = Math.random() < .5 ? a : b; sa = win === a ? 1 : 0; sb = win === a ? 0 : 1 } }
  else if (ra && !ra.won) { win = b; sa = ra.gf; sb = ra.ga } else if (rb && !rb.won) { win = a; sa = rb.ga; sb = rb.gf } else return null;
  const r = await C.matches.updateOne({ _id: matchId, settled: { $ne: true } }, { $set: { settled: true, winner: win, status: 'done' } }); if (!r.matchedCount) return null;
  if (m.roomId) { try { await matchMaker.remoteRoomCall(m.roomId, 'matchDone') } catch (e) { /* room already closed */ } }
  if (m.tournamentId) await require('./tournaments').result(m.tournamentId, m.fixtureId, win, a, b, sa, sb); return { win, sa, sb } }
/* a player left / disconnected without reporting -> counts as his loss */
async function forfeit(matchId, uid) { await C.matches.updateOne({ _id: matchId, ['reports.' + uid]: { $exists: false } }, { $set: { ['reports.' + uid]: { gf: 0, ga: 0, won: false, forfeit: true, t: now() } } }); return settle(matchId) }
module.exports = { create, viewFor, report, settle, forfeit };
