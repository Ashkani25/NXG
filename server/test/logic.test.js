require('../src/lib'); const fs = require('fs'), path = require('path'), assert = require('assert');
const a = fs.readFileSync(path.join(__dirname, '../src/lib.js'), 'utf8');
// reuse the exact same pure-logic tests as the original library
const L = require('../src/lib');
for (const n of [2, 3, 4, 5, 7, 8, 11, 16]) { const ids = Array.from({ length: n }, (_, i) => 'p' + i), r = L.buildCup(ids); let g = 0; while (g++ < 40) { const ri = L.currentRound(r), m = r[ri].matches.find(x => !x.winner); if (!m) break; assert(m.a && m.b); m.winner = Math.random() < .5 ? m.a : m.b; if (L.advanceCup(r)) break } assert(ids.includes(L.advanceCup(r)), 'champion n=' + n) }
for (const n of [3, 4, 5, 6, 8]) { const ids = Array.from({ length: n }, (_, i) => 'p' + i), lg = L.buildLeague(ids), s = new Set(); lg.rounds.forEach(r => r.matches.forEach(m => s.add([m.a, m.b].sort().join('-')))); assert.strictEqual(s.size, n * (n - 1) / 2) }
const s = { level: 1, xp: 0, coins: 0, gems: 0 }; assert.strictEqual(L.addXp(s, 700), 1); assert(L.trophyDelta(1000, 1000, true) > 0 && L.trophyDelta(1000, 1000, false) < 0); console.log('logic ok');

