/* BERMUDA NXG — client adapter for the Colyseus + Express server (server/). Same window.NexoraBackend shape as backend.js.
   REST (fetch) for everything stateful, Colyseus rooms for realtime: queue (ranked matchmaking), match (relay), gameroom (custom rooms),
   chat (global), user (pushes: notifications, DMs, tournament matchReady). All money/xp/trophies are decided by the server.
   If CFG.API_URL is empty or colyseus.js is missing, this file sets CFG.BACKEND='local' (offline practice). */
(() => {
  const CFG = window.NEXORA_CONFIG, G = window.NexoraGame;
  if (CFG.BACKEND !== 'colyseus') return;
  if (!window.Colyseus || !CFG.API_URL) { console.warn('[BERMUDA NXG] server not configured -> offline mode'); CFG.BACKEND = 'local'; return }
  const API = CFG.API_URL.replace(/\/$/, ''), WS = (CFG.WS_URL || API.replace(/^http/, 'ws')), TK = 'bnxg_token', client = new window.Colyseus.Client(WS);
  const L = { notif: [], profile: [], auth: [] }, emit = (k, d) => L[k].forEach(f => { try { f(d) } catch (e) { console.error(e) } });
  const token = () => { try { return localStorage.getItem(TK) } catch (e) { return null } }, setToken = t => { try { t ? localStorage.setItem(TK, t) : localStorage.removeItem(TK) } catch (e) { } };
  async function api(method, path, body) { let r; try { r = await fetch(API + path, { method, headers: Object.assign({ 'Content-Type': 'application/json' }, token() ? { Authorization: 'Bearer ' + token() } : {}), body: body === undefined ? undefined : JSON.stringify(body) }) } catch (e) { throw new Error('Cannot reach the server. Check your connection.') }
    const j = await r.json().catch(() => ({})); if (!r.ok) { if (r.status === 401 && token()) { setToken(null); me = null; emit('auth', null) } throw new Error(j.error || 'Request failed (' + r.status + ')') } return j }
  const get = p => api('GET', p), post = (p, b) => api('POST', p, b || {}), del = p => api('DELETE', p);
  const leagueOf = tr => { const Ls = CFG.LEAGUES; let i = 0; for (let k = 0; k < Ls.length; k++) if (tr >= Ls[k].min) i = k; const cur = Ls[i], nxt = Ls[i + 1], span = nxt ? nxt.min - cur.min : 2000, div = Math.min(2, Math.floor((tr - cur.min) / (span / 3))); return { id: cur.id, name: cur.name, color: cur.color, division: ['III', 'II', 'I'][div], label: cur.name.toUpperCase() + ' ' + ['III', 'II', 'I'][div], next: nxt ? nxt.min : null, min: cur.min } };
  const withLeague = p => p && Object.assign(p, { league: leagueOf(p.trophies || 0), bot: false });
  let me = null, userRoom = null, chatRoom = null, chatSubs = [], dmSubs = [];
  const loadMe = async () => { me = withLeague(await get('/me')); return me };
  /* ---- realtime: user room (pushes) ---- */
  async function connectUser() { if (userRoom || !token() || !me) return; try { const room = await client.joinOrCreate('user', { token: token(), uid: me.id }); userRoom = room;
      room.onMessage('notif', n => emit('notif', n)); room.onMessage('dm', m => dmSubs.forEach(f => f(m))); room.onMessage('matchReady', v => (B.tournaments._ready || []).forEach(f => f(v)));
      room.onLeave(() => { userRoom = null; setTimeout(() => connectUser().catch(() => { }), 3000) }) } catch (e) { console.warn('user room', e.message) } }
  const disconnectAll = () => { for (const r of [userRoom, chatRoom]) { try { r && r.leave() } catch (e) { } } userRoom = chatRoom = null };
  const sess = u => ({ user: u });
  const afterAuth = async s => { setToken(s.token); await loadMe(); connectUser(); return sess(s.user) };
  /* ---- reservations -> Colyseus room ---- */
  const consume = async reservation => client.consumeSeatReservation(reservation);
  const descOf = async v => { const room = await consume(v.reservation); const d = Object.assign({}, v, { room, opponent: withLeague(Object.assign({ ping: null }, v.opponent)), bot: false }); delete d.reservation; return d };
  function openChannel(desc) { const room = desc.room; if (!room) return null; const h = {}; let closed = false;
    for (const k of ['shot', 'settled', 'goal', 'timeout', 'emote', 'leave', 'peer', 'clock']) room.onMessage(k, d => (h[k] || []).forEach(f => f(d)));
    room.onLeave(async code => { if (closed) return; if (code !== 1000 && room.reconnectionToken) { try { const r2 = await client.reconnect(room.reconnectionToken); desc.room = r2; return openChannel(desc) } catch (e) { /* could not reconnect */ } } });
    ch_clock(room); return { on(k, f) { (h[k] = h[k] || []).push(f) }, send(k, d) { if (!closed) { try { room.send(k, d === undefined ? null : d) } catch (e) { } } }, close() { closed = true; try { room.leave() } catch (e) { } } } }
  function ch_clock(room) { room.onMessage('clock', m => { try { G.syncClock && G.syncClock(m.left) } catch (e) { } }) }
  /* ---- custom rooms ---- */
  let gr = null, curView = null; const roomL = [];
  const roomView = v => v && Object.assign({}, v, { host: withLeague(v.host), guest: v.guest ? withLeague(v.guest) : null, isHost: !!(me && v.host && v.host.id === me.id) });
  async function enterRoom(res) { if (gr) { try { gr.leave() } catch (e) { } } const room = await consume(res.reservation); gr = room; let last = null;
    room.onMessage('state', v => { last = curView = roomView(v); roomL.forEach(f => f({ type: 'state', room: last })) }); room.onMessage('closed', () => { roomL.forEach(f => f({ type: 'closed' })); gr = null; curView = null });
    room.onMessage('start', async v => { try { const d = await descOf(v); roomL.forEach(f => f({ type: 'start', desc: d })) } catch (e) { console.error(e) } }); room.onMessage('error', m => roomL.forEach(f => f({ type: 'error', message: m.message }))); room.onMessage('chat', m => (B.rooms._chat || []).forEach(f => f(Object.assign(m, { mine: m.from && me && m.from.id === me.id }))));
    room.onLeave(() => { if (gr === room) gr = null }); await new Promise(r => setTimeout(r, 250)); return { code: res.code } }
  const B = window.NexoraBackend = {
    kind: 'colyseus', features: { online: true, email: true, oauth: !!CFG.OAUTH, billing: false, voice: false, ai: true },
    onProfile: f => (L.profile.push(f), () => L.profile.splice(L.profile.indexOf(f), 1)), onNotif: f => (L.notif.push(f), () => L.notif.splice(L.notif.indexOf(f), 1)), leagueOf, xpNeed: CFG.XP_NEED,
    auth: {
      async session() { if (!token()) return null; try { await loadMe(); connectUser(); return sess({ id: me.id, email: me.email, guest: me.guest }) } catch (e) { if (/reach/.test(e.message)) throw e; return null } },
      async signInGuest(name) { return afterAuth(await post('/auth/guest', { name })) }, async signUp(email, password, name) { return afterAuth(await post('/auth/register', { email, password, name })) }, async signIn(email, password) { return afterAuth(await post('/auth/login', { email, password })) },
      async oauth() { const cap = window.Capacitor && window.Capacitor.Plugins && (window.Capacitor.Plugins.SocialLogin || window.Capacitor.Plugins.GoogleAuth); if (!cap) throw new Error('Google sign-in needs the Android app');
        const r = cap.login ? await cap.login({ provider: 'google', options: { scopes: ['email', 'profile'] } }) : await cap.signIn(); const idToken = (r.result && r.result.idToken) || (r.authentication && r.authentication.idToken) || r.idToken; return afterAuth(await post('/auth/google', { idToken })) },
      async resetPassword() { throw new Error('Password reset by email is not enabled on this server yet') },
      async signOut() { disconnectAll(); setToken(null); me = null; emit('auth', null) }, async deleteAccount() { await del('/auth/account'); disconnectAll(); setToken(null); me = null; emit('auth', null) }, onChange: f => L.auth.push(f), link: (email, password) => post('/auth/link', { email, password })
    },
    profile: { get: loadMe, async update(p) { const u = await api('PATCH', '/me', p); me = withLeague(u); return me }, async publicProfile(id) { return withLeague(await get('/users/' + (id || me.id))) }, async search(q) { q = String(q || '').trim(); if (q.length < 2) return []; return (await get('/users/search?q=' + encodeURIComponent(q))).map(withLeague) } },
    social: { state: id => get('/social/' + id), follow: id => post('/social/' + id + '/follow'), unfollow: id => del('/social/' + id + '/follow'), like: id => post('/social/' + id + '/like'), async list(kind, id) { return (await get('/social/' + (id || 'me') + '/' + kind)).map(withLeague) } },
    economy: { async dailyStatus() { return get('/economy/daily') }, async claimDaily() { const r = await post('/economy/daily/claim'); await loadMe(); return r }, quests: () => get('/economy/quests'), async claimQuest(id) { const r = await post('/economy/quests/' + id + '/claim'); await loadMe(); return r } },
    shop: {
      async items() { await loadMe(); const p = me, out = [], ob = p.owned.balls || [], of = p.owned.fields || [], price = window.NexoraPrices;
        for (let i = 0; i < G.NB; i++) out.push({ id: 'ball:' + i, type: 'ball', key: i, name: G.ballName(i), sub: 'Trail: ' + G.TRN[i], price: price.ball(i), cur: 'coins', owned: ob.includes(i), equipped: p.equip.ball === i, img: 'assets/balls/s' + i + '.webp' });
        G.FIELDS.forEach(f => out.push({ id: 'field:' + f.id, type: 'field', key: f.id, name: f.name + ' Pitch', sub: 'Pitch', price: price.field(f.id), cur: 'coins', owned: of.includes(f.id), equipped: p.equip.field === f.id, img: 'assets/fields/t_' + f.id + '.webp' }));
        for (const k in CFG.CHESTS) out.push({ id: 'chest:' + k, type: 'chest', key: k, name: CFG.CHESTS[k].name, sub: 'Random rewards', price: CFG.CHESTS[k].price, cur: CFG.CHESTS[k].cur, owned: false, img: 'assets/ui/' + CFG.CHESTS[k].img + '.webp' }); return out },
      async buy(id) { const r = await post('/shop/buy', { id }); await loadMe(); return r }, async equip(type, key) { await post('/shop/equip', { type, key }); await loadMe(); return true }, async openChest(key) { const r = await post('/shop/chest', { key }); await loadMe(); return r } },
    leaderboard: { async top() { return (await get('/leaderboard')).map(withLeague) }, async me() { const r = await get('/leaderboard/me'); return Object.assign(r, { league: leagueOf(r.trophies) }) }, seasonEnds: () => { const d = new Date(); d.setUTCDate(d.getUTCDate() + (7 - d.getUTCDay())); d.setUTCHours(0, 0, 0, 0); return d.getTime() } },
    matchmaking: { _room: null, _rej: null,
      join() { return new Promise(async (res, rej) => { B.matchmaking._rej = rej; try { const room = await client.joinOrCreate('queue', { token: token() }); B.matchmaking._room = room; room.onMessage('matched', async v => { B.matchmaking._room = null; try { res(await descOf(v)) } catch (e) { rej(e) } finally { try { room.leave() } catch (e) { } } }); room.onError((c, m) => rej(new Error(m || 'Matchmaking error'))) } catch (e) { rej(new Error(e.message || 'Matchmaking failed')) } }) },
      async cancel() { const r = B.matchmaking._room; B.matchmaking._room = null; try { r && r.leave() } catch (e) { } if (B.matchmaking._rej) B.matchmaking._rej(new Error('cancelled')); B.matchmaking._rej = null } },
    match: { open: openChannel, async report(r) { const o = await post('/match/report', { matchId: r.matchId || null, mode: r.mode, won: !!r.won, goalsFor: r.goalsFor | 0, goalsAgainst: r.goalsAgainst | 0 }); await loadMe(); if (gr) { try { gr.send('matchDone') } catch (e) { } } return Object.assign(o, { league: leagueOf(o.totalTrophies), xpNeed: CFG.XP_NEED(o.level) }) } },
    rooms: {
      list: () => get('/rooms').then(l => l.map(r => Object.assign(r, { host: withLeague(r.host) }))),
      async current() { return gr ? curView : null }, onChange(f) { roomL.push(f); return () => roomL.splice(roomL.indexOf(f), 1) }, onChat(f) { (B.rooms._chat = B.rooms._chat || []).push(f); return () => B.rooms._chat.splice(B.rooms._chat.indexOf(f), 1) },
      async create(o) { return enterRoom(await post('/rooms', o)) }, async join(code) { return enterRoom(await post('/rooms/join', { code })) },
      async leave() { const r = gr; gr = null; curView = null; try { r && r.leave() } catch (e) { } },
      async setReady(b) { gr && gr.send('ready', !!b) }, async update(p) { gr && gr.send('update', p) }, async start() { gr && gr.send('start'); return new Promise((res, rej) => { const un = B.rooms.onChange(e => { if (e.type === 'start') { un(); res(e.desc) } if (e.type === 'error') { un(); rej(new Error(e.message)) } }); setTimeout(() => { un(); rej(new Error('Start timed out')) }, 15000) }) }, sendChat: t => gr && gr.send('chat', t) },
    tournaments: { _ready: [],
      list: () => get('/tournaments'), get: id => get('/tournaments/' + id), create: o => post('/tournaments', o), async join(id) { const r = await post('/tournaments/' + id + '/join'); await loadMe(); return r }, async leave(id) { await post('/tournaments/' + id + '/leave'); await loadMe(); return true },
      async nextMatch(id) { const r = await post('/tournaments/' + id + '/ready'); if (r.match) return descOf(r.match);
        return new Promise((res, rej) => { const f = async v => { cleanup(); try { res(await descOf(v)) } catch (e) { rej(e) } }, to = setTimeout(async () => { cleanup(); try { await post('/tournaments/' + id + '/unready') } catch (e) { } rej(new Error('Your opponent is not ready yet. Try again in a moment.')) }, 90000), cleanup = () => { clearTimeout(to); B.tournaments._ready = B.tournaments._ready.filter(x => x !== f) }; B.tournaments._ready.push(f) }) },
      async report() { return true } },
    friends: { async list() { return (await get('/friends')).map(withLeague) }, async requests() { return (await get('/friends/requests')).map(withLeague) }, async suggestions() { return (await get('/friends/suggestions')).map(withLeague) },
      add: id => post('/friends/' + id + '/add'), respond: (id, yes) => post('/friends/' + id + '/' + (yes ? 'accept' : 'decline')), remove: id => del('/friends/' + id), async invite(id) { const r = await post('/friends/' + id + '/invite'); await enterRoom(r); return { code: r.code } } },
    chat: {
      async history(ch) { return ch === 'global' ? get('/chat/global') : ch.startsWith('dm:') ? get('/dm/' + ch.slice(3)) : [] },
      async send(ch, text) { text = String(text).trim().slice(0, CFG.MAX_CHAT_LEN); if (!text) return null; if (ch === 'global') { if (!chatRoom) await B.chat._join(); chatRoom.send('say', text); return null } if (ch.startsWith('dm:')) { await post('/dm/' + ch.slice(3), { text }); return { id: 'l' + Date.now(), text, mine: true, from: me, t: Date.now() } } if (ch.startsWith('room:')) { B.rooms.sendChat(text); return null } return null },
      async _join() { chatRoom = await client.joinOrCreate('chat', { token: token() }); chatRoom.onMessage('msg', m => chatSubs.forEach(f => f(Object.assign({}, m, { mine: m.from.id === me.id })))); chatRoom.onLeave(() => { chatRoom = null }) },
      subscribe(ch, cb) { if (ch === 'global') { if (!chatRoom) B.chat._join().catch(() => { }); const f = m => cb(m); chatSubs.push(f); return () => { chatSubs = chatSubs.filter(x => x !== f) } }
        if (ch.startsWith('dm:')) { const oid = ch.slice(3), f = m => { if (m.from === oid) cb({ id: m.id, text: m.text, t: m.t, mine: false, from: { id: oid, name: m.name } }) }; dmSubs.push(f); return () => { dmSubs = dmSubs.filter(x => x !== f) } }
        if (ch.startsWith('room:')) return B.rooms.onChat(m => cb(m)); return () => { } } },
    inbox: { list: async () => (await get('/dm')).map(c => Object.assign(c, { other: withLeague(c.other) })), onChange(cb) { const f = () => cb(); dmSubs.push(f); return () => { dmSubs = dmSubs.filter(x => x !== f) } }, async unread() { return (await get('/dm/unread')).n } },
    ai: { async ask(messages) { return (await post('/ai', { messages: messages.slice(-12) })).text } },
    notifications: { list: () => get('/notifications'), async markAllRead() { await post('/notifications/read'); return true }, async unread() { return (await get('/notifications/unread')).n } },
    voice: { state: { mic: false, speaker: true, joined: null }, async join() { return false }, async leave() { }, async setMic(on) { if (on) throw new Error('Voice chat is not available yet'); return false }, async setSpeaker(on) { B.voice.state.speaker = !!on; return on } },
    presence: { async onlineCount() { try { return (await get('/stats/online')).n } catch (e) { return 0 } } }
  };
})();
