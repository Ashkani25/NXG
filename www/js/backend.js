/* =====================================================================================
   BERMUDA NXG backend layer.
   The UI (app.js) ONLY talks to `window.NexoraBackend`. Two implementations exist:
     - OfflineBackend (this file) : single-player only – guest profile, progress, shop, daily rewards, quests stored on the device.
                                    Every social/online feature reports `features.online = false` and throws 'Online server required'.
     - SupabaseBackend (js/backend-supabase.js) : to be written following AI_AGENT_BACKEND_GUIDE.txt
   Every method returns a Promise (even the local ones) so swapping is a drop-in change.
   The shape of every returned object is documented in AI_AGENT_BACKEND_GUIDE.txt (section 6).
   ===================================================================================== */
(() => {
  const CFG = window.NEXORA_CONFIG, G = window.NexoraGame;
  if (CFG.BACKEND !== 'local') return; // supabase adapter installs itself instead
  const LS = 'nexora_local_v2';
  const rnd = (a, b) => a + Math.floor(Math.random() * (b - a + 1));
  const pick = a => a[Math.floor(Math.random() * a.length)];
  const clone = o => JSON.parse(JSON.stringify(o));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const today = () => new Date().toISOString().slice(0, 10);
  const uid = () => 'u_' + Math.random().toString(36).slice(2, 10);
  const FREE_BALLS = [0, 4, 5], FREE_FIELDS = ['stadium', 'forest', 'ice', 'street'];
  const BALL_PRICE = i => FREE_BALLS.includes(i) ? 0 : i >= 13 ? 800 + (i - 13) * 100 : 300 + (i % 5) * 300;
  const FIELD_PRICE = id => FREE_FIELDS.includes(id) ? 0 : 500 + (id.length % 4) * 400;
  const listeners = { profile: [], notif: [], auth: [] };
  const emit = (k, d) => listeners[k].forEach(f => { try { f(d) } catch (e) { console.error(e) } });

  /* ---------- storage ---------- */
  let DB = (() => { try { return JSON.parse(localStorage.getItem(LS)) || {} } catch (e) { return {} } })();
  const save = () => { try { localStorage.setItem(LS, JSON.stringify(DB)) } catch (e) { } };
  const newProfile = (name, extra) => Object.assign({
    id: uid(), name, avatar: 'club0', team: 'club0', form: 0, level: 1, xp: 0, coins: 1500, gems: 20, trophies: 0,
    stats: { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 },
    owned: { balls: FREE_BALLS.slice(), fields: FREE_FIELDS.slice(), teams: [G.VIP_FREE] }, equip: { ball: 4, field: 'stadium' },
    daily: { day: 0, last: '' }, quests: { date: '', list: [] }, friends: [], reqs: [],
    created: Date.now(), country: '', bio: ''
  }, extra || {});
  const me = () => DB.profile;
  const touch = () => { save(); emit('profile', clone(me())) };
  const leagueOf = tr => { const L = CFG.LEAGUES; let i = 0; for (let k = 0; k < L.length; k++) if (tr >= L[k].min) i = k; const cur = L[i], nxt = L[i + 1], span = nxt ? nxt.min - cur.min : 2000, div = Math.min(2, Math.floor((tr - cur.min) / (span / 3))); return { id: cur.id, name: cur.name, color: cur.color, division: ['III', 'II', 'I'][div], label: cur.name.toUpperCase() + ' ' + ['III', 'II', 'I'][div], next: nxt ? nxt.min : null, min: cur.min }; };
  const xpNeed = l => CFG.XP_NEED(l);
  const pub = p => ({ id: p.id, name: p.name, avatar: p.avatar, team: p.team, form: p.form || 0, level: p.level, trophies: p.trophies, league: leagueOf(p.trophies), online: true, bot: false, stats: p.stats });
  function notify(title, body, kind) { const n = { id: uid(), title, body, kind: kind || 'info', t: Date.now(), read: false }; (DB.notifs = DB.notifs || []).unshift(n); DB.notifs = DB.notifs.slice(0, 40); save(); emit('notif', n) }

  /* ---------- quests ---------- */
  function ensureQuests() {
    const p = me(); if (!p || p.quests.date === today()) return;
    p.quests = { date: today(), list: [{ id: 'q1', type: 'play', need: 3, have: 0, coins: 120, claimed: false, text: 'Play 3 matches' }, { id: 'q2', type: 'win', need: 1, have: 0, coins: 200, gems: 2, claimed: false, text: 'Win 1 match' }, { id: 'q3', type: 'goals', need: 6, have: 0, coins: 150, claimed: false, text: 'Score 6 goals' }] };
  }
  const addXp = (p, xp) => { p.xp += xp; let up = 0; while (p.xp >= xpNeed(p.level)) { p.xp -= xpNeed(p.level); p.level++; up++; p.coins += 100 + p.level * 10; p.gems += p.level % 5 === 0 ? 5 : 0 } return up };

  const NEED_ONLINE = async () => { throw new Error('Online server required') };

  /* ---------- the backend object ---------- */
  const B = window.NexoraBackend = {
    kind: 'local',
    features: { online: false, email: false, oauth: false, billing: false },
    onProfile: f => (listeners.profile.push(f), () => listeners.profile.splice(listeners.profile.indexOf(f), 1)),
    onNotif: f => (listeners.notif.push(f), () => listeners.notif.splice(listeners.notif.indexOf(f), 1)),
    leagueOf, xpNeed,
    auth: {
      async session() { return DB.profile ? { user: { id: DB.profile.id, email: DB.email || null, guest: !!DB.guest } } : null },
      async signInGuest(name) { DB.profile = newProfile(name || 'Player' + rnd(1000, 9999)); DB.guest = true; DB.email = null; ensureQuests(); save(); return { user: { id: DB.profile.id, guest: true } } },
      signUp: NEED_ONLINE, signIn: NEED_ONLINE, oauth: NEED_ONLINE,
      resetPassword: NEED_ONLINE,
      async signOut() { DB.profile = null; save(); emit('auth', null) },
      async deleteAccount() { DB = {}; save(); emit('auth', null) },
      onChange: f => listeners.auth.push(f)
    },
    profile: {
      async get() { ensureQuests(); const raw = me(); if (raw && raw.owned) { raw.owned.teams = (G.TEAMS||[]).filter(t=>G.isVip(t.id)).map(t=>t.id); raw.owned.balls = Array.from({length:G.NB},(_,i)=>i); raw.owned.fields = (G.FIELDS||[]).map(f=>f.id); } const p = clone(raw); p.league = leagueOf(p.trophies); p.xpNeed = xpNeed(p.level); p.rank = null; return p },
      async update(patch) { const p = me(), ok = ['name', 'avatar', 'team', 'form', 'bio', 'country']; for (const k of ok) if (k in patch) p[k] = k === 'name' ? String(patch[k]).trim().slice(0, 16) || p.name : patch[k]; touch(); return B.profile.get() },
      async publicProfile() { return pub(me()) },
      search: async () => []
    },
    economy: {
      async dailyStatus() { const d = me().daily, t = today(), claimed = d.last === t, yest = new Date(Date.now() - 864e5).toISOString().slice(0, 10); let day = d.day; if (!claimed && d.last !== yest && d.last) day = 0; return { day, claimedToday: claimed, nextIndex: claimed ? day - 1 : day % 7, rewards: CFG.DAILY_REWARDS } },
      async claimDaily() { const s = await B.economy.dailyStatus(); if (s.claimedToday) throw new Error('Already claimed today'); const p = me(), idx = s.day % 7, r = CFG.DAILY_REWARDS[idx]; p.coins += r.coins || 0; p.gems += r.gems || 0; p.daily = { day: s.day + 1, last: today() }; const got = { coins: r.coins || 0, gems: r.gems || 0 }; if (r.chest) got.chest = (await B.shop.openChest('wood', true)).rewards; touch(); return { reward: got, status: await B.economy.dailyStatus() } },
      async quests() { ensureQuests(); return clone(me().quests.list) },
      async claimQuest(id) { const q = me().quests.list.find(x => x.id === id); if (!q || q.claimed || q.have < q.need) throw new Error('Not ready'); q.claimed = true; me().coins += q.coins || 0; me().gems += q.gems || 0; touch(); return { coins: q.coins || 0, gems: q.gems || 0 } }
    },
    shop: {
      async items() {
        const p = me(), out = []; p.owned.balls = Array.from({length:G.NB},(_,i)=>i); p.owned.fields = (G.FIELDS||[]).map(f=>f.id); p.owned.teams = (G.TEAMS||[]).filter(t=>G.isVip(t.id)).map(t=>t.id); const ob = p.owned.balls, of = p.owned.fields;
        for (let i = 0; i < G.NB; i++) out.push({ id: 'ball:' + i, type: 'ball', key: i, name: G.ballName(i), sub: 'Trail: ' + G.TRN[i], price: BALL_PRICE(i), cur: 'coins', owned: ob.includes(i), equipped: p.equip.ball === i, img: 'assets/balls/s' + i + '.webp' });
        G.FIELDS.forEach(f => out.push({ id: 'field:' + f.id, type: 'field', key: f.id, name: f.name + ' Pitch', sub: 'Pitch', price: FIELD_PRICE(f.id), cur: 'coins', owned: of.includes(f.id), equipped: p.equip.field === f.id, img: 'assets/fields/t_' + f.id + '.webp' }));
        for (const k in CFG.CHESTS) out.push({ id: 'chest:' + k, type: 'chest', key: k, name: CFG.CHESTS[k].name, sub: 'Random rewards', price: CFG.CHESTS[k].price, cur: CFG.CHESTS[k].cur, owned: false, img: 'assets/ui/' + CFG.CHESTS[k].img + '.webp' });
        return out
      },
      async buy(id) {
        const [type, key] = id.split(':'), p = me();
        if (type === 'pack') throw new Error('Purchases need the online store');
        if (type === 'chest') return B.shop.openChest(key, true);
        if (type === 'team') { if (!G.isVip(key)) throw new Error('Item not found'); if (!p.owned.teams) p.owned.teams = []; if (!p.owned.teams.includes(key)) p.owned.teams.push(key); touch(); return { granted: { item: G.T(key).name } } }
        const items = await B.shop.items(), it = items.find(x => x.id === id); if (!it) throw new Error('Item not found'); if (it.owned) throw new Error('Already owned');
        /* temporary open-store mode: no currency deduction */
        if (type === 'ball') p.owned.balls.push(+key); else p.owned.fields.push(key); touch(); return { granted: { item: it.name } }
      },
      async equip(type, key) { const p = me(); if (type === 'ball') { if (!p.owned.balls.includes(+key)) throw new Error('Locked'); p.equip.ball = +key } else { if (!p.owned.fields.includes(key)) throw new Error('Locked'); p.equip.field = key } touch(); return true },
      async openChest(k, free) {
        const c = CFG.CHESTS[k], p = me(); if (!free) { if (p[c.cur] < c.price) throw new Error('Not enough ' + c.cur); p[c.cur] -= c.price }
        const rewards = [], tier = k === 'magic' ? 3 : k === 'gold' ? 2 : 1;
        const coins = rnd(100, 300) * tier; p.coins += coins; rewards.push({ type: 'coins', amount: coins });
        if (Math.random() < .5) { const g = rnd(1, 3) * tier; p.gems += g; rewards.push({ type: 'gems', amount: g }) }
        if (Math.random() < .18 * tier) { const miss = []; for (let i = 0; i < G.NB; i++) if (!p.owned.balls.includes(i)) miss.push(i); if (miss.length) { const b = pick(miss); p.owned.balls.push(b); rewards.push({ type: 'ball', key: b, name: G.ballName(b) }) } }
        if (Math.random() < .12 * tier) { const miss = G.FIELDS.filter(f => !p.owned.fields.includes(f.id)); if (miss.length) { const f = pick(miss); p.owned.fields.push(f.id); rewards.push({ type: 'field', key: f.id, name: f.name + ' Pitch' }) } }
        touch(); return { rewards }
      }
    },
    leaderboard: {
      top: async () => [],
      async me() { const p = me(); return { rank: null, trophies: p.trophies, league: leagueOf(p.trophies) } },
      seasonEnds: () => { const d = new Date(); d.setDate(d.getDate() + (7 - d.getDay())); d.setHours(0, 0, 0, 0); return d.getTime() }
    },
    matchmaking: { join: NEED_ONLINE, cancel: async () => { } },
    match: {
      open() { return null },
      async report(r) {
        const p = me(), won = !!r.won, gf = r.goalsFor | 0, ga = r.goalsAgainst | 0, k = r.mode === 'local' ? 0 : .5;   // offline practice gives reduced rewards, no trophies
        const xp = Math.round(k * ((won ? 120 : 45) + gf * 10)), coins = Math.round(k * (won ? 120 : 30));
        if (k > 0) { p.stats.played++; p.stats.goals += gf; p.stats.conceded += ga; if (won) { p.stats.wins++; p.stats.streak++; p.stats.best = Math.max(p.stats.best, p.stats.streak) } else { p.stats.losses++; p.stats.streak = 0 } }
        p.coins += coins; const before = p.level, lv = k > 0 ? addXp(p, xp) : 0;
        ensureQuests(); for (const q of p.quests.list) { if (q.type === 'play') q.have = Math.min(q.need, q.have + 1); if (q.type === 'win' && won) q.have = Math.min(q.need, q.have + 1); if (q.type === 'goals') q.have = Math.min(q.need, q.have + gf) }
        touch(); return { xp, coins, trophies: 0, totalTrophies: p.trophies, level: p.level, levelUp: lv > 0, levelsGained: lv, league: leagueOf(p.trophies), xpNow: p.xp, xpNeed: xpNeed(p.level), levelBefore: before }
      }
    },
    rooms: { list: async () => [], current: async () => null, onChange: () => () => { }, create: NEED_ONLINE, join: NEED_ONLINE, leave: async () => { }, setReady: NEED_ONLINE, update: NEED_ONLINE, start: NEED_ONLINE },
    tournaments: { list: async () => [], get: NEED_ONLINE, join: NEED_ONLINE, nextMatch: NEED_ONLINE, report: NEED_ONLINE, leave: async () => { } },
    friends: { list: async () => [], requests: async () => [], suggestions: async () => [], add: NEED_ONLINE, respond: NEED_ONLINE, remove: NEED_ONLINE, invite: NEED_ONLINE },
    chat: { history: async () => [], send: NEED_ONLINE, subscribe: () => () => { } },
    notifications: {
      async list() { return clone(DB.notifs || []) },
      async markAllRead() { (DB.notifs || []).forEach(n => n.read = true); save(); return true },
      async unread() { return (DB.notifs || []).filter(n => !n.read).length }
    },
    voice: {
      state: { mic: false, speaker: true, joined: null },
      async join(room) { B.voice.state.joined = room; return true }, async leave() { B.voice.state.joined = null; B.voice.state.mic = false },
      async setMic(on) { if (on) { try { if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) { const s = await navigator.mediaDevices.getUserMedia({ audio: true }); s.getTracks().forEach(t => t.stop()) } } catch (e) { throw new Error('Microphone permission denied') } } B.voice.state.mic = !!on; return B.voice.state.mic },
      async setSpeaker(on) { B.voice.state.speaker = !!on; return on }
    },
    presence: { onlineCount: async () => 0 }
  };
})();
