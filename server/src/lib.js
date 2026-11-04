'use strict';
/* Pure game-economy logic shared by the functions (no Firebase imports) so it can be unit-tested. */
const LEAGUES = [0, 500, 1000, 1800, 2800, 4000, 6000];
const XP_NEED = l => 300 + l * 350;
const FREE_BALLS = [0, 4, 5], FREE_FIELDS = ['stadium', 'forest', 'ice', 'street'];
const NB = 36;
const FIELDS = ['forest','ice','ocean','street','streetarena','lava','stadium','checker','futsal','arena','arena2','desert','grove','pool','neon','royal','mahogany','leather','aqua','asphalt','court','cyberbox','realmadrid','psg','acmilan','barcelona','persepolis','esteghlal','mancity'];
const ballPrice = i => FREE_BALLS.includes(i) ? 0 : i >= 13 ? 800 + (i - 13) * 100 : 300 + (i % 5) * 300;
const fieldPrice = id => FREE_FIELDS.includes(id) ? 0 : 500 + (id.length % 4) * 400;
const CHESTS = { wood: { price: 400, cur: 'coins' }, gold: { price: 60, cur: 'gems' }, magic: { price: 140, cur: 'gems' } };
const DAILY = [{ coins: 100 }, { coins: 150 }, { coins: 200 }, { gems: 5 }, { coins: 300 }, { coins: 400 }, { coins: 600, gems: 10, chest: 'wood' }];
const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
const today = () => new Date().toISOString().slice(0, 10);
const newQuests = () => ({ date: today(), list: [
  { id: 'q1', type: 'play', need: 3, have: 0, coins: 120, claimed: false, text: 'Play 3 matches' },
  { id: 'q2', type: 'win', need: 1, have: 0, coins: 200, gems: 2, claimed: false, text: 'Win 1 match' },
  { id: 'q3', type: 'goals', need: 6, have: 0, coins: 150, claimed: false, text: 'Score 6 goals' }] });
/* add xp to {level,xp,coins,gems}; returns levels gained */
function addXp(s, xp) { s.xp += xp; let up = 0; while (s.xp >= XP_NEED(s.level)) { s.xp -= XP_NEED(s.level); s.level++; up++; s.coins += 100 + s.level * 10; if (s.level % 5 === 0) s.gems += 5 } return up }
/* ELO-like trophy change for ranked matches */
function trophyDelta(myTr, oppTr, won) { const exp = 1 / (1 + Math.pow(10, (oppTr - myTr) / 400)); return won ? Math.max(8, Math.round(32 * (1 - exp))) : -Math.max(6, Math.round(24 * exp)) }
function matchRewards({ won, gf, ranked, friendly, tournament, bot }) {
  const k = bot ? .5 : friendly ? .5 : 1; return { xp: Math.round(k * ((won ? 120 : 45) + gf * 10)), coins: tournament ? 0 : Math.round(k * (won ? 120 : 30)) } }
function chestRewards(key, owned) { const tier = key === 'magic' ? 3 : key === 'gold' ? 2 : 1, rewards = [], coins = rnd(100, 300) * tier; rewards.push({ type: 'coins', amount: coins }); let gems = 0;
  if (Math.random() < .5) { gems = rnd(1, 3) * tier; rewards.push({ type: 'gems', amount: gems }) }
  if (Math.random() < .18 * tier) { const miss = []; for (let i = 0; i < NB; i++) if (!owned.balls.includes(i)) miss.push(i); if (miss.length) { const b = miss[rnd(0, miss.length - 1)]; rewards.push({ type: 'ball', key: b }) } }
  if (Math.random() < .12 * tier) { const miss = FIELDS.filter(f => !owned.fields.includes(f)); if (miss.length) rewards.push({ type: 'field', key: miss[rnd(0, miss.length - 1)] }) }
  return rewards }
/* knockout bracket: players -> rounds (byes auto-advance) */
function roundName(n) { return n === 2 ? 'Final' : n === 4 ? 'Semi-final' : n === 8 ? 'Quarter-final' : 'Round of ' + n }
function buildCup(ids) { const shuffled = ids.slice().sort(() => Math.random() - .5); let size = 2; while (size < shuffled.length) size *= 2;
  while (shuffled.length < size) shuffled.push(null); // byes (they sit in the second half, so no match has two byes)
  const rounds = []; let n = size, r = 0; while (n >= 2) { rounds.push({ name: roundName(n), matches: Array.from({ length: n / 2 }, (_, i) => ({ id: 'r' + r + 'm' + i, a: null, b: null, winner: null, score: null, matchId: null, readyA: false, readyB: false })) }); n /= 2; r++ }
  rounds[0].matches.forEach((m, i) => { m.a = shuffled[i]; m.b = shuffled[i + size / 2]; if (m.a && !m.b) m.winner = m.a; else if (!m.a && m.b) m.winner = m.b });
  advanceCup(rounds); return rounds }
/* fill next rounds from decided winners; returns champion id or null */
function advanceCup(rounds) { for (let r = 0; r < rounds.length - 1; r++) { const nxt = rounds[r + 1]; rounds[r].matches.forEach((m, i) => { const t = nxt.matches[(i / 2) | 0], slot = i % 2 ? 'b' : 'a'; if (m.winner && !t[slot]) t[slot] = m.winner }); }
  const last = rounds[rounds.length - 1].matches[0]; return last.winner || null }
function currentRound(rounds) { for (let r = 0; r < rounds.length; r++) if (rounds[r].matches.some(m => !m.winner)) return r; return rounds.length - 1 }
/* round-robin (circle method) */
function buildLeague(ids) { const p = ids.slice(); if (p.length % 2) p.push(null); const n = p.length, rounds = []; for (let r = 0; r < n - 1; r++) { const ms = []; for (let i = 0; i < n / 2; i++) { const a = p[i], b = p[n - 1 - i]; if (a && b) ms.push({ id: 'r' + r + 'm' + i, a, b, winner: null, score: null, matchId: null, readyA: false, readyB: false, done: false }) } rounds.push({ name: 'Matchday ' + (r + 1), matches: ms }); p.splice(1, 0, p.pop()) }
  const table = {}; ids.forEach(i => table[i] = { p: 0, w: 0, d: 0, l: 0, gf: 0, ga: 0, pts: 0 }); return { rounds, table } }
function leagueApply(table, a, b, ga, gb) { const A = table[a], B = table[b]; A.p++; B.p++; A.gf += ga; A.ga += gb; B.gf += gb; B.ga += ga; if (ga > gb) { A.w++; B.l++; A.pts += 3 } else if (gb > ga) { B.w++; A.l++; B.pts += 3 } else { A.d++; B.d++; A.pts++; B.pts++ } }
module.exports = { LEAGUES, XP_NEED, FREE_BALLS, FREE_FIELDS, NB, FIELDS, ballPrice, fieldPrice, CHESTS, DAILY, rnd, today, newQuests, addXp, trophyDelta, matchRewards, chestRewards, buildCup, advanceCup, currentRound, buildLeague, leagueApply, roundName };
