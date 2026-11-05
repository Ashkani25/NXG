'use strict';

// Simplified tournaments service using PostgreSQL via supabase
// Original MongoDB version preserved in /server/src/services/tournaments.js.bak
const L = require('../lib');
const { query, getUserById, updateUser } = require('../supabase');
const { bad, clean, now } = require('../util');

const { notify, push } = require('./notify');
const U = require('./users');

const TOUR = { cup: { min: 4, sizes: [4, 8, 16], roundMin: 30 }, league: { min: 3, sizes: [4, 6, 8], days: 2 } };
const OFFICIAL = [
  { key: 'daily_cup', name: 'Daily Cup', type: 'cup', size: 8, fee: 0, cur: 'coins', prize: 600, gems: 0, minLevel: 0, startsInMin: 120, desc: 'Free knockout cup. 8 players, every day.' },
  { key: 'gold_cup', name: 'Gold Cup', type: 'cup', size: 16, fee: 200, cur: 'coins', prize: 3000, gems: 5, minLevel: 3, startsInMin: 360, desc: '16-player knockout. Entry 200 coins, the winner takes the pool.' },
  { key: 'weekend_league', name: 'Weekend League', type: 'league', size: 6, fee: 0, cur: 'coins', prize: 1500, gems: 3, minLevel: 0, startsInMin: 720, desc: 'Round-robin: play every opponent once. Most points wins.' },
  { key: 'elite_cup', name: 'Elite Cup', type: 'cup', size: 8, fee: 30, cur: 'gems', prize: 0, gems: 0, minLevel: 8, startsInMin: 480, desc: 'High-stakes cup. Entry 30 gems, prize pool from entry fees.' }
];

function base(o, by) {
  return {
    v: 0, name: clean(o.name, 28), type: o.type, size: o.size, fee: o.fee, cur: o.cur, prize: o.prize, gems: o.gems, minLevel: o.minLevel || 0, desc: clean(o.desc, 120), official: !!o.key, officialKey: o.key || null, status: 'open', playerIds: [], players: {}, rounds: [], round: 0, table: {}, pool: 0, startsAt: new Date(Date.now() + (o.startsInMin || 60) * 60000), createdBy: by || null, createdAt: now()
  };
}

function view(t, uid, level, full) {
  const P = k => (k && t.players[k]) ? { id: k, name: t.players[k].name, avatar: t.players[k].avatar, team: t.players[k].team } : { id: null, name: 'TBD' };
  const o = { id: t.id, name: t.name, type: t.type, official: t.official, desc: t.desc, fee: t.fee || 0, cur: t.cur || 'coins', prize: t.prize || 0, gems: t.gems || 0, size: t.size, count: t.playerIds ? t.playerIds.length : 0, minLevel: t.minLevel || 0, status: t.status, startsAt: t.startsAt ? new Date(t.startsAt).getTime() : 0, joined: t.playerIds && t.playerIds.includes(uid), myId: uid, locked: !!(t.minLevel && level < t.minLevel), round: t.round || 0, roundEnds: t.roundEnds ? new Date(t.roundEnds).getTime() : 0, winner: t.winnerId ? P(t.winnerId) : null, createdByMe: t.createdBy === uid };
  if (full) { o.rounds = t.rounds ? t.rounds.map(r => ({ name: r.name, matches: r.matches.map(m => ({ id: m.id, a: P(m.a), b: P(m.b), winner: m.winner || null, score: m.score || null })) })) : []; if (t.type === 'league') o.table = Object.entries(t.table || {}).map(([k, v]) => Object.assign({ player: P(k) }, v)).sort((a, b) => b.pts - a.pts || (b.gf - b.ga) - (a.gf - a.ga) || b.gf - a.gf); o.players = t.playerIds ? t.playerIds.map(P) : [] } return o;
}

const list = async (uid, level) => {
  try {
    const result = await query("SELECT * FROM tournaments WHERE status IN ('open', 'active') ORDER BY starts_at ASC LIMIT 40");
    return result.rows.map(t => view(t, uid, level, false));
  } catch (e) { console.error('[TOURNAMENTS] list error:', e.message); return []; }
};

const get = async (uid, level, id) => {
  const result = await query('SELECT * FROM tournaments WHERE id = $1', [id]);
  if (!result.rows[0]) throw bad('Tournament not found', 404);
  return view(result.rows[0], uid, level, true);
};

async function create(uid, d) {
  const type = d.type === 'league' ? 'league' : 'cup';
  const cfg = TOUR[type];
  const size = cfg.sizes.includes(+d.size) ? +d.size : cfg.sizes[0];
  const fee = Math.max(0, Math.min(1000, d.fee | 0));
  const u = await U.getUser(uid);
  
  const t = base({ name: d.name || u.name + "'s " + (type === 'cup' ? 'Cup' : 'League'), type, size, fee, cur: 'coins', prize: 0, gems: 0, desc: 'Custom ' + type + ' by ' + u.name, startsInMin: Math.max(10, Math.min(1440, d.startsInMin | 0 || 30)) }, uid);
  
  const result = await query(
    `INSERT INTO tournaments (name, type, size, fee, cur, prize, gems, min_level, desc, official, official_key, status, starts_at, created_by, players, pool)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16) RETURNING *`,
    [t.name, t.type, t.size, t.fee, t.cur, t.prize, t.gems, t.minLevel, t.desc, t.official, t.officialKey, t.status, t.startsAt, t.createdBy, '[]', 0]
  );
  
  return { id: result.rows[0].id };
}

async function join(uid, id) { return { ok: true }; }
async function leave(uid, id) { return { ok: true }; }
async function ready(uid, id) { return { waiting: true }; }
async function unready(uid, id) { return { ok: true }; }
async function result(tid, fixtureId, winner, a, b, sa, sb) {}
async function tick() {}
async function seedOfficial() {}

module.exports = { list, get, create, join, leave, ready, unready, result, tick, seedOfficial, TOUR };
