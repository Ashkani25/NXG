/* Match flow + boot. Connects screens <-> engine (NexoraGame) <-> backend channel */
(() => {
  'use strict';
  const NX = window.NX, { el, svg, fmt, B, G, CFG } = NX, S = NX.screens, $ = NX.$;
  const F = NX.flow = { inMatch: false, ctx: null };

  /* ---------- helpers ---------- */
  const showGame = on => { $('#app').classList.toggle('off', on); $('#hud').classList.toggle('show', on); G.setMenuOpen(!on) };
  const meLite = () => ({ id: NX.P.id, name: NX.P.name, avatar: NX.P.avatar, team: NX.P.team, form: NX.P.form || 0, level: NX.P.level, trophies: NX.P.trophies, league: NX.P.league });
  const pickTeam = excl => { const l = G.TEAMS.filter(t => t.cat === 'club' && t.id !== excl); return l[Math.floor(Math.random() * l.length)].id };

  /* ---------- entry points ---------- */
  F.quick = async () => { await NX.refreshProfile(); if (!NX.online()) return F.botSetup(); NX.go('matchmaking', { mode: 'ranked' }) };
  F.local = async () => { await NX.refreshProfile(); const P = NX.P; const t1 = pickTeam(P.team); F.start({ mode: 'local', teams: [P.team, t1], form: [P.form || 0, Math.floor(Math.random() * 6)], names: ['Player 1', 'Player 2'], field: P.equip.field, ball: P.equip.ball, limit: 0, matchTime: CFG.MATCH_SECONDS, turnTime: 0, bot: false }, { kind: 'local' }) };
  F.botSetup = () => {
    let lvl = 1; const P = NX.P, seg = el('div', { class: 'seg', style: { justifyContent: 'center', margin: '12px 0' } });
    const draw = () => seg.replaceChildren(...[['Rookie', 0], ['Pro', 1], ['Legend', 2]].map(([n, v]) => el('button', { class: lvl === v ? 'on' : '', onclick: () => { lvl = v; draw() } }, n))); draw();
    const m = NX.modal([NX.ico('game_controller', 'bigimg'), el('h3', { class: 'gold' }, 'Practice vs Bot'), el('p', null, 'Choose difficulty'), seg, el('button', { class: 'btn gold block', onclick: () => { m.close(); const t1 = pickTeam(P.team); F.start({ mode: 'bot', teams: [P.team, t1], form: [P.form || 0, Math.floor(Math.random() * 6)], names: [P.name, 'Bot ' + ['Rookie', 'Pro', 'Legend'][lvl]], field: P.equip.field, ball: P.equip.ball, limit: 0, matchTime: CFG.MATCH_SECONDS, turnTime: 0, ai: true, aiLvl: lvl }, { kind: 'bot' }) } }, NX.svg('play'), 'Start match')]);
  };
  F.profileSheet = p => {
    const m = NX.modal([NX.avatar(p, 'lg', true), el('h3', { style: { marginTop: '12px' } }, p.name), el('div', { class: 'chip', style: { color: p.league.color } }, svg('trophy'), p.league.label + ' · ' + fmt(p.trophies)),
      el('div', { class: 'acts' }, el('button', { class: 'btn ghost', onclick: () => { m.close(); B.friends.add(p.id); NX.toast('Friend request sent', 'ok') } }, svg('users'), 'Add'), el('button', { class: 'btn gold', onclick: () => { m.close(); NX.go('chat', { ch: 'dm:' + p.id, title: p.name }) } }, svg('chat'), 'Chat'))]);
  };

  /* ---------- matchmaking screen ---------- */
  S.matchmaking = async p => {
    let sec = 0, done = false; const timer = el('b', { style: { fontSize: '30px' } }, '0:00'), msg = el('div', { class: 'mut' }, 'Searching for an opponent…'), body = el('div', { class: 'scr mm' });
    const iv = setInterval(() => { sec++; timer.textContent = Math.floor(sec / 60) + ':' + String(sec % 60).padStart(2, '0'); if (sec === 40) { msg.textContent = 'Few players online right now. Keep waiting or practice vs a bot (counts as a bot match).'; body.append(el('button', { class: 'btn ghost', onclick: async () => { done = true; clearInterval(iv); await B.matchmaking.cancel(); NX.back(); NX.flow.botSetup() } }, 'Practice vs Bot')) } }, 1000); NX.onLeave(() => clearInterval(iv));
    const cancel = async () => { done = true; clearInterval(iv); await B.matchmaking.cancel(); NX.back() };
    body.append(el('div', { class: 'bgmagic' }), el('h2', { class: 'gold', style: { letterSpacing: '3px' } }, 'RANKED MATCH'), el('div', { class: 'radar' }, el('i'), el('i'), el('i'), NX.ico('nexora_x_logo')), timer, msg,
      el('button', { class: 'btn dark', onclick: cancel }, el('img', { src: NX.icoSrc('stop'), style: { width: '26px' } }), 'Cancel'));
    B.matchmaking.join({ mode: p.mode }).then(desc => { if (done) return; clearInterval(iv); F.found(body, desc) }).catch(e => { if (!done && e.message !== 'cancelled') { NX.err(e); NX.back() } });
    return body;
  };
  F.found = async (body, desc) => {
    const me = meLite(), o = desc.opponent; let ready = false, oppReady = false; const card = (pl, you) => el('div', { class: 'card pcard' }, NX.avatar(pl, '', true), el('b', null, pl.name), el('small', null, pl.league.label), el('small', null, you ? 'You' : (pl.ping ? 'Ping ' + pl.ping + ' ms' : '')));
    const rdy = el('img', { class: 'rdy', src: NX.icoSrc('ready'), style: { opacity: .35, transition: '.3s' } }), btn = el('button', { class: 'btn gold block', style: { maxWidth: '260px' } }, 'READY');
    body.replaceChildren(el('div', { class: 'bgmagic' }), el('h2', { class: 'gold', style: { letterSpacing: '3px' } }, 'MATCH FOUND'), el('div', { class: 'vs' }, card(me, 1), el('div', { class: 'vsb gold' }, 'VS'), card(o)), rdy, btn);
    const go = async () => { for (let n = 3; n > 0; n--) { body.replaceChildren(el('div', { class: 'bgmagic' }), el('div', { class: 'cd gold' }, n), el('div', { class: 'mut' }, 'Get ready…')); G.sfx('ui'); await NX.sleep(900) } body.replaceChildren(el('div', { class: 'bgmagic' }), NX.ico('start_rocket', 'rdy'), el('h2', { class: 'gold' }, 'GO!')); await NX.sleep(450); F.begin(desc, true) };
    btn.onclick = () => { if (ready) return; ready = true; btn.classList.add('dis'); btn.textContent = 'Waiting…'; rdy.style.opacity = 1; setTimeout(go, desc.bot ? 900 : 0) };
    NX.onLeave(() => { ready = true });
  };

  /* ---------- begin match from a descriptor ---------- */
  F.begin = (desc, skipNav) => {
    const P = NX.P, o = desc.opponent, S_ = desc.settings, host = desc.role === 'host';
    const cfg = { mode: desc.bot ? 'bot' : 'online', teams: host ? [P.team, o.team] : [o.team, P.team], form: host ? [P.form || 0, o.form || 0] : [o.form || 0, P.form || 0], names: host ? [P.name, o.name] : [o.name, P.name], field: Math.max(0, G.FIELDS.findIndex(f => f.id === S_.field)), ball: S_.ball, limit: S_.limit || 0, matchTime: S_.matchTime || (S_.limit ? 0 : CFG.MATCH_SECONDS), turnTime: S_.turnTime || 0, ai: !!desc.bot, aiLvl: desc.aiLvl, mirror: !desc.bot && !host };
    F.start(cfg, { kind: desc.bot ? 'matchbot' : 'online', desc });
  };

  F.start = (cfg, meta) => {
    F.ctx = Object.assign({ cfg, startedAt: Date.now(), ended: false }, meta); F.inMatch = true; NX.cleanup(); showGame(true); NX.saveUI();
    G.SET.lim = cfg.limit; $('#bubbles').replaceChildren(); buildHud(meta);
    const fieldIdx = typeof cfg.field === 'number' ? cfg.field : Math.max(0, G.FIELDS.findIndex(f => f.id === cfg.field));
    G.startMatch(Object.assign({}, cfg, { field: fieldIdx }));
    if (meta.kind === 'online') wireOnline(meta.desc);
  };

  /* ---------- online channel wiring (real adapter) ---------- */
  for (const k of ['shot', 'settled', 'goal', 'timeout']) G.E.on(k, m => { if (F.ctx && F.ctx.ch) F.ctx.ch.send(k, m) });
  function wireOnline(desc) {
    const ch = F.ctx.ch = B.match.open(desc); if (!ch) return;
    ch.on('shot', m => G.remoteShot(m)); ch.on('settled', m => G.remoteSettled(m)); ch.on('goal', m => G.remoteGoal(m)); ch.on('timeout', m => G.remoteTimeout(m));
    ch.on('emote', m => bubble(m, 'opp')); ch.on('leave', () => { if (!F.ctx.ended) finish(true, 'Opponent left') });
  }

  /* ---------- in-game HUD ---------- */
  function buildHud(meta) {
    const hb = $('#hbot'), online = meta.kind === 'online' || meta.kind === 'matchbot', emo = $('#emo'); emo.classList.remove('show');
    const mic = el('button', { class: 'ibtn ' + (NX.UI.mic ? '' : 'off'), onclick: async () => { NX.UI.mic = NX.UI.mic ? 0 : 1; try { await B.voice.setMic(!!NX.UI.mic) } catch (e) { NX.UI.mic = 0; NX.err(e) } NX.saveUI(); mic.classList.toggle('off', !NX.UI.mic) } }, svg('mic'));
    const spk = el('button', { class: 'ibtn ' + (NX.UI.spk ? '' : 'off'), onclick: () => { NX.UI.spk = NX.UI.spk ? 0 : 1; B.voice.setSpeaker(!!NX.UI.spk); NX.saveUI(); spk.classList.toggle('off', !NX.UI.spk) } }, svg('spk'));
    hb.replaceChildren(...[el('button', { class: 'ibtn', onclick: pause }, svg('pause')), online ? el('button', { class: 'ibtn', onclick: () => emo.classList.toggle('show') }, svg('emo')) : null, online ? mic : null, online ? spk : null].filter(Boolean));
    emo.replaceChildren(...CFG.QUICK_CHAT.map(t => el('button', { onclick: () => sendEmote(t) }, t)), ...CFG.EMOJIS.map(t => el('button', { class: 'e', onclick: () => sendEmote(t) }, t)));
  }
  function sendEmote(t) { $('#emo').classList.remove('show'); bubble({ text: t }, 'me'); if (F.ctx.ch) F.ctx.ch.send('emote', { text: t }); else if (F.ctx.kind === 'matchbot' && Math.random() < .6) setTimeout(() => bubble({ text: CFG.QUICK_CHAT[Math.floor(Math.random() * 4)] }, 'opp'), 1200) }
  function bubble(m, who) { const b = el('div', { class: 'bubble ' + who }, m.text); $('#bubbles').append(b); setTimeout(() => b.remove(), 2600) }

  function pause() {
    if (!F.ctx || F.ctx.ended) return; const online = F.ctx.kind === 'online', bot = F.ctx.kind === 'matchbot'; if (!online) G.setMenuOpen(true);
    const m = NX.modal([el('h3', { class: 'gold' }, 'Paused'), el('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px', marginTop: '10px' } },
      el('button', { class: 'btn gold block', onclick: () => m.close() }, el('img', { src: NX.icoSrc('continue'), style: { width: '28px' } }), 'Continue'),
      !online && !bot ? el('button', { class: 'btn dark block', onclick: () => { m.close(); G.restart(0) } }, svg('refresh'), 'Restart') : null,
      el('button', { class: 'btn dark block', onclick: () => { NX.UI.snd = NX.UI.snd ? 0 : 1; NX.saveUI(); NX.toast('Sound ' + (NX.UI.snd ? 'on' : 'off')) } }, svg('spk'), 'Sound on/off'),
      el('button', { class: 'btn red block', onclick: () => NX.confirm('Leave match', online || bot ? 'Leaving counts as a loss.' : 'Leave this match?', 'Leave', () => { m.close(); if (online || bot) finish(false, 'forfeit'); else F.exit() }, true) }, el('img', { src: NX.icoSrc('exit'), style: { width: '26px' } }), 'Leave'))], { sticky: true, onclose: () => { if (!online) G.setMenuOpen(false) } });
  }
  F.exit = () => { F.inMatch = false; if (F.ctx && F.ctx.ch) F.ctx.ch.close(); F.ctx = null; G.stop(); showGame(false); NX.go('home', null, { root: 1 }) };

  /* ---------- result ---------- */
  G.E.on('end', async r => { if (!F.ctx || F.ctx.ended) return; finish(r.local[0] > r.local[1]) });
  async function finish(won, why) {
    const c = F.ctx; if (!c || c.ended) return; c.ended = true; const sc = G.score, gf = sc[0], ga = sc[1], kind = c.kind;
    if (why === 'forfeit') won = false;
    const mode = kind === 'online' || kind === 'matchbot' ? (c.desc && c.desc.friendly ? 'room' : c.desc && c.desc.tournamentId ? 'tournament' : 'online') : kind === 'bot' ? 'bot' : 'local';
    let rep = null, tour = null;
    try { if (mode !== 'local') rep = await B.match.report({ mode: mode === 'room' ? 'bot' : mode, won, goalsFor: gf, goalsAgainst: ga, ranked: c.desc && c.desc.ranked, oppTrophies: c.desc && c.desc.opponent && c.desc.opponent.trophies, matchId: c.desc && c.desc.matchId }); if (c.desc && c.desc.tournamentId) tour = await B.tournaments.report(c.desc.tournamentId, won) } catch (e) { NX.err(e) }
    await NX.refreshProfile(); showGame(false); G.setMenuOpen(true); $('#app').classList.remove('off');
    NX.mount(resultScreen({ won, gf, ga, rep, tour, why, c }));
  }
  function resultScreen(o) {
    const { won, gf, ga, rep, tour, c } = o, rw = rep ? [[NX.icoSrc('xp'), '+' + rep.xp, 'XP'], ['assets/nx3/coin.webp', '+' + rep.coins, 'Coins'], [NX.icoSrc('league'), (rep.trophies >= 0 ? '+' : '') + rep.trophies, 'Trophies']] : null;
    const again = () => { if (c.kind === 'online') { NX.go('matchmaking', { mode: 'ranked' }, { root: 1 }) } else if (c.kind === 'tournament') NX.go('home', null, { root: 1 }); else F.start(c.cfg, { kind: c.kind, desc: c.desc }) };
    return el('div', { class: 'scr res' }, el('div', { class: 'bgmagic' }), NX.ico(won ? 'cup' : 'close', 'cup'), el('div', { class: 'big ' + (won ? 'gold' : ''), style: won ? null : { color: 'var(--mut)' } }, won ? 'VICTORY' : 'DEFEAT'), el('div', { class: 'sc gold' }, gf + ' : ' + ga), o.why ? el('div', { class: 'mut' }, o.why) : null,
      rw ? el('div', { class: 'card rbox' }, rw.map(([i, v, l]) => el('div', null, el('img', { src: i }), v, el('small', null, l)))) : null,
      rep && rep.levelUp ? el('div', { class: 'lvup' }, '⭐ LEVEL UP! Level ' + rep.level) : null, rep ? el('div', { style: { width: 'min(100%,300px)' } }, el('div', { class: 'xpl' }, el('em', null, 'XP'), rep.xpNow + ' / ' + rep.xpNeed), el('div', { class: 'bar' }, el('i', { style: { width: rep.xpNow / rep.xpNeed * 100 + '%' } }))) : null,
      tour ? el('div', { class: 'chip', style: { fontSize: '14px' } }, tour.status === 'champion' ? '🏆 Tournament champion!' : tour.status === 'eliminated' ? 'Eliminated from the tournament' : 'Advanced to the next round') : null,
      el('div', { style: { display: 'flex', gap: '10px', width: 'min(100%,360px)', marginTop: '10px' } }, tour ? el('button', { class: 'btn gold', style: { flex: 1 }, onclick: () => { F.inMatch = false; NX.go('tournament', { id: c.desc.tournamentId }, { root: 1 }) } }, 'Continue') : el('button', { class: 'btn gold', style: { flex: 1 }, onclick: again }, c.kind === 'online' ? 'Next match' : 'Rematch'), el('button', { class: 'btn dark', style: { flex: 1 }, onclick: () => { F.inMatch = false; F.ctx = null; NX.go('home', null, { root: 1 }) } }, svg('home'), 'Home')));
  }

  /* ---------- boot ---------- */
  window.addEventListener('resize', () => { G.resize() });
  document.addEventListener('pointerdown', () => { G.loadSnd(); G.musicSync() }, { once: true });
  (async () => {
    NX.mount(S.splash()); const sess = await B.auth.session(); await NX.introDone;
    if (sess) await NX.afterAuth(); else NX.go('auth', null, { root: 1 });
    G.musicSync();
  })();
})();
