(() => {
  'use strict';
  const NX = window.NX, { el, svg, fmt, B, G, CFG } = NX, S = NX.screens;
  const time = t => { const d = new Date(t); return d.getHours().toString().padStart(2, '0') + ':' + d.getMinutes().toString().padStart(2, '0') };

  /* ---------------- daily reward ---------------- */
  S.daily = async () => {
    const ds = await B.economy.dailyStatus(), grid = el('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: '8px' } });
    const label = r => [r.coins ? el('div', { class: 'cur' }, el('img', { src: 'assets/nx3/coin.webp' }), r.coins) : null, r.gems ? el('div', { class: 'cur' }, el('img', { src: 'assets/nx3/gem.webp' }), r.gems) : null, r.chest ? el('img', { src: 'assets/ui/chest_wood.webp', style: { width: '30px' } }) : null];
    CFG.DAILY_REWARDS.forEach((r, i) => { const done = i < ds.day % 7 || (ds.claimedToday && i === (ds.day - 1) % 7), cur = !ds.claimedToday && i === ds.day % 7; grid.append(el('div', { class: 'card pad', style: { textAlign: 'center', gridColumn: i === 6 ? 'span 2' : '', borderColor: cur ? 'var(--g1)' : '', boxShadow: cur ? '0 0 20px var(--glow)' : '', opacity: done ? .5 : 1 } }, el('small', { class: 'mut' }, 'DAY ' + (i + 1)), el('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '3px', minHeight: '46px', justifyContent: 'center', fontSize: '13px' } }, label(r)), done ? svg('check') : null)) });
    const btn = el('button', { class: 'btn gold block pulse ' + (ds.claimedToday ? 'dis' : ''), onclick: e => NX.busy(e.currentTarget, async () => { const r = await B.economy.claimDaily(); const l = []; if (r.reward.coins) l.push({ img: 'assets/nx3/coin.webp', label: '+' + r.reward.coins }); if (r.reward.gems) l.push({ img: 'assets/nx3/gem.webp', label: '+' + r.reward.gems }); (r.reward.chest || []).forEach(c => l.push({ img: 'assets/ui/chest_wood.webp', label: c.type === 'coins' || c.type === 'gems' ? '+' + c.amount : c.name })); NX.rewards('Daily reward', l, () => NX.render()) }) }, ds.claimedToday ? 'Come back tomorrow' : 'Claim reward');
    return el('div', { class: 'scr' }, NX.topbar('Daily rewards'), NX.page([el('div', { style: { textAlign: 'center', margin: '4px 0 14px' } }, NX.ico('start_rocket', ''), el('h3', { class: 'gold' }, ds.day + '-day streak')), grid, el('div', { style: { height: '16px' } }), btn]));
  };

  /* ---------------- quests ---------------- */
  S.quests = async () => {
    const q = await B.economy.quests();
    return el('div', { class: 'scr' }, NX.topbar('Daily quests'), NX.page([el('p', { class: 'mut', style: { margin: '2px 4px 12px' } }, 'Resets every day. Finish matches to progress.'), ...q.map(x => el('div', { class: 'card pad', style: { marginBottom: '10px' } }, el('div', { class: 'row' }, el('div', { style: { flex: 1 } }, el('b', null, x.text), el('div', { class: 'bar', style: { margin: '8px 0 4px' } }, el('i', { style: { width: x.have / x.need * 100 + '%' } })), el('small', { class: 'mut' }, x.have + ' / ' + x.need)), el('div', { style: { textAlign: 'center' } }, el('div', { class: 'cur', style: { marginBottom: '6px' } }, el('img', { src: 'assets/nx3/coin.webp' }), x.coins), x.claimed ? el('div', { class: 'eq', style: { height: 'auto' } }, svg('check')) : el('button', { class: 'btn gold sm ' + (x.have >= x.need ? '' : 'dis'), onclick: e => NX.busy(e.currentTarget, async () => { await B.economy.claimQuest(x.id); NX.toast('Reward claimed', 'ok'); NX.render() }) }, 'Claim')))))]));
  };

  /* ---------------- notifications ---------------- */
  S.notifications = async () => {
    const l = await B.notifications.list(); await B.notifications.markAllRead();
    return el('div', { class: 'scr' }, NX.topbar('Notifications'), NX.page(l.length ? l.map(n => el('div', { class: 'lrow' }, el('div', { class: 'cal', style: { width: '42px', height: '42px', fontSize: '22px' } }, svg(n.kind === 'friend' ? 'users' : n.kind === 'tour' ? 'trophy' : 'bell')), el('div', { class: 't' }, el('b', null, n.title), el('small', null, n.body)), el('small', { class: 'mut' }, time(n.t)))) : el('div', { class: 'empty' }, 'No notifications yet')));
  };

  /* ---------------- league / leaderboard ---------------- */
  S.league = async () => {
    let scope = 'global'; const box = el('div'), tabs = el('div', { class: 'tabs' }), P = NX.P, L = P.league, ends = B.leaderboard.seasonEnds(), days = Math.max(0, Math.ceil((ends - Date.now()) / 864e5));
    const next = L.next, prog = next ? Math.min(100, (P.trophies - L.min) / (next - L.min) * 100) : 100;
    const draw = async () => {
      if (!NX.online()) { tabs.replaceChildren(); box.replaceChildren(el('div', { class: 'empty' }, 'Leaderboards are available when connected to the online server.')); return }
      tabs.replaceChildren(...[['global', 'Global'], ['friends', 'Friends']].map(([k, l]) => el('button', { class: scope === k ? 'on' : '', onclick: () => { scope = k; draw() } }, l)));
      const list = await B.leaderboard.top(scope), t3 = list.slice(0, 3), pod = (p, c) => p ? el('div', { class: c }, NX.avatar(p, 'sm'), el('b', { class: 'n' }, p.name), el('small', { class: 'mut' }, fmt(p.trophies)), el('div', { class: 'b' }, p.rank)) : el('div');
      box.replaceChildren(el('div', { class: 'pod' }, pod(t3[1], 'p2'), pod(t3[0], 'p1'), pod(t3[2], 'p3')), ...list.slice(3).map(p => el('div', { class: 'lrow ' + (p.me ? 'me' : ''), onclick: () => !p.me && NX.flow.profileSheet(p) }, el('div', { class: 'rk' }, p.rank), NX.avatar(p, 'xs'), el('div', { class: 't' }, el('b', null, p.name), el('small', null, p.league.label + ' · Lv ' + p.level)), el('span', { class: 'cur' }, svg('trophy'), fmt(p.trophies)))))
    }; draw();
    return el('div', { class: 'scr' }, NX.topbar('League'), NX.page([el('div', { class: 'card pad', style: { display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '12px' } }, NX.ico('league', '', 0), el('div', { style: { flex: 1 } }, el('b', { style: { fontSize: '22px', color: L.color } }, L.label), el('div', { class: 'cur', style: { margin: '4px 0' } }, svg('trophy'), fmt(P.trophies), next ? el('small', { class: 'mut' }, ' / ' + fmt(next)) : null), el('div', { class: 'bar' }, el('i', { style: { width: prog + '%' } })), el('small', { class: 'mut' }, (NX.online() ? 'Season ends in ' + days + ' day' + (days === 1 ? '' : 's') + (P.rank ? ' · Rank #' + P.rank : '') : 'Trophies are earned in online ranked matches')))), tabs, box]));
  };
  const lgImg = () => { }; // eslint placeholder

  /* ---------------- tournaments ---------------- */
  S.tournaments = async () => {
    if (!NX.online()) return NX.offlineScreen('Tournaments', 'Tournaments need the online server.');
    const l = await B.tournaments.list();
    return el('div', { class: 'scr' }, NX.topbar('Tournaments'), NX.page(l.map(t => el('div', { class: 'card pad', style: { marginBottom: '12px', opacity: t.locked ? .6 : 1 }, onclick: () => !t.locked && NX.go('tournament', { id: t.id }) }, el('div', { class: 'row' }, NX.ico('tournament', '', 0), el('div', { style: { flex: 1, minWidth: 0 } }, el('b', { style: { fontSize: '17px' } }, t.name), el('div', { class: 'mut', style: { fontSize: '12px', margin: '2px 0 6px' } }, t.desc), el('div', { class: 'row', style: { gap: '6px', flexWrap: 'wrap' } }, el('span', { class: 'chip' }, svg('users'), t.size + ' players'), el('span', { class: 'chip' }, 'Fee ', t.fee ? NX.cur(t.fee, t.cur) : 'Free'), t.locked ? el('span', { class: 'chip' }, svg('lock'), 'Lv ' + t.level) : t.joined ? el('span', { class: 'chip', style: { color: 'var(--ok)' } }, t.status) : null))), el('div', { class: 'row', style: { marginTop: '10px', justifyContent: 'space-between' } }, el('span', { class: 'mut', style: { fontSize: '12px' } }, 'Prize pool'), el('div', { class: 'row' }, NX.cur(t.prize), t.gems ? NX.cur(t.gems, 'gems') : null))))));
  };
  S.tournament = async (p) => {
    const t = await B.tournaments.get(p.id);
    const bracket = () => el('div', { class: 'bk' }, t.rounds.map(r => el('div', { class: 'rd' }, el('h5', null, r.name), r.matches.map(m => { const row = (x, o) => el('div', { class: (m.winner ? (m.winner === x.id ? 'w' : 'l') : '') + (x.id === t.myId ? ' you' : '') }, x.name); return el('div', { class: 'bm' }, row(m.a), row(m.b)) }))));
    let body;
    if (!t.joined) body = [el('p', { class: 'mut' }, t.desc), el('div', { class: 'card pad', style: { margin: '10px 0' } }, el('div', { class: 'row', style: { justifyContent: 'space-between' } }, 'Entry fee', t.fee ? NX.cur(t.fee, t.cur) : 'Free'), el('div', { class: 'row', style: { justifyContent: 'space-between', marginTop: '8px' } }, 'Prize', el('div', { class: 'row' }, NX.cur(t.prize), t.gems ? NX.cur(t.gems, 'gems') : null)), el('div', { class: 'row', style: { justifyContent: 'space-between', marginTop: '8px' } }, 'Format', t.size + ' players · knock-out · first to 3')), el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.tournaments.join(p.id); NX.toast('You are in!', 'ok'); NX.render() }) }, 'Join tournament')];
    else {
      const cur = t.rounds[t.round], me = cur && cur.matches.find(m => m.a.id === t.myId || m.b.id === t.myId), opp = me && (me.a.id === t.myId ? me.b : me.a);
      body = [el('div', { class: 'card pad', style: { textAlign: 'center', marginBottom: '12px' } }, t.status === 'active' ? [el('small', { class: 'mut' }, cur.name.toUpperCase()), el('h3', { class: 'gold', style: { margin: '6px 0' } }, 'vs ' + (opp ? opp.name : '?')), el('button', { class: 'btn gold', onclick: e => NX.busy(e.currentTarget, async () => { const d = await B.tournaments.nextMatch(p.id); NX.flow.begin(d) }) }, NX.svg('play'), 'Play match')] : t.status === 'champion' ? [el('h3', { class: 'gold' }, '🏆 Champion!'), el('button', { class: 'btn dark', onclick: async () => { await B.tournaments.leave(p.id); NX.back() } }, 'Finish')] : [el('h3', { style: { color: 'var(--bad)' } }, 'Eliminated'), el('button', { class: 'btn dark', onclick: async () => { await B.tournaments.leave(p.id); NX.back() } }, 'Close')]), bracket()];
    }
    return el('div', { class: 'scr' }, NX.topbar(t.name), NX.page(body));
  };

  /* ---------------- friends ---------------- */
  S.friends = async () => {
    if (!NX.online()) return NX.offlineScreen('Friends', 'Sign in to the online server to add friends.');
    let tab = 'friends'; const box = el('div'), tabs = el('div', { class: 'tabs' }), q = el('input', { placeholder: 'Search by name or ID (NX-0007)', oninput: () => { if (q.value.length > 1) { tab = 'search'; draw() } else if (!q.value) { tab = 'friends'; draw() } } });
    const fr = (p, acts) => el('div', { class: 'lrow' }, NX.avatar(p, 'xs'), el('div', { class: 't', onclick: () => NX.flow.profileSheet(p) }, el('b', null, p.name), el('small', null, (p.online ? 'Online' : 'Offline') + ' · Lv ' + p.level + ' · ' + p.league.label)), acts);
    const draw = async () => {
      tabs.replaceChildren(...[['friends', 'Friends'], ['requests', 'Requests'], ['suggest', 'Suggested']].map(([k, l]) => el('button', { class: tab === k ? 'on' : '', onclick: () => { tab = k; q.value = ''; draw() } }, l)));
      let l = [];
      if (tab === 'friends') { l = (await B.friends.list()).map(p => fr(p, el('div', { class: 'row', style: { gap: '6px' } }, el('button', { class: 'ibtn sm', onclick: () => NX.go('chat', { ch: 'dm:' + p.id, title: p.name }) }, svg('chat')), el('button', { class: 'btn gold sm', onclick: e => NX.busy(e.currentTarget, async () => { await B.friends.invite(p.id); NX.go('room') }) }, 'Play')))); if (!l.length) l = [el('div', { class: 'empty' }, 'No friends yet. Add some!')] }
      if (tab === 'requests') { l = (await B.friends.requests()).map(p => fr(p, el('div', { class: 'row', style: { gap: '6px' } }, el('button', { class: 'ibtn sm', onclick: async () => { await B.friends.respond(p.id, true); draw() } }, svg('check')), el('button', { class: 'ibtn sm', onclick: async () => { await B.friends.respond(p.id, false); draw() } }, svg('close'))))); if (!l.length) l = [el('div', { class: 'empty' }, 'No pending requests')] }
      if (tab === 'suggest' || tab === 'search') { const src = tab === 'search' ? await B.profile.search(q.value) : await B.friends.suggestions(); l = src.map(p => fr(p, el('button', { class: 'btn gold sm', onclick: async e => { await B.friends.add(p.id); e.currentTarget.textContent = 'Sent'; e.currentTarget.classList.add('dis') } }, 'Add'))); if (!l.length) l = [el('div', { class: 'empty' }, 'Nobody found')] }
      box.replaceChildren(...l)
    }; draw();
    return el('div', { class: 'scr' }, NX.topbar('Friends'), NX.page([el('div', { class: 'sbox' }, svg('search'), q), el('div', { style: { height: '10px' } }), tabs, el('div', { style: { height: '12px' } }), box]));
  };

  /* ---------------- chat (global / dm / room) ---------------- */
  NX.chatView = async (ch, opts) => {
    opts = opts || {}; const msgs = el('div', { class: 'msgs' }), inp = el('input', { placeholder: 'Type a message…', maxlength: CFG.MAX_CHAT_LEN });
    const add = m => { const mine = m.mine || (m.from && m.from.id === NX.P.id); msgs.append(el('div', { class: 'msg ' + (mine ? 'me' : '') }, mine ? null : NX.avatar(m.from, 'xs'), el('div', { class: 'bub' }, mine ? null : el('small', null, m.from.name), m.text))); msgs.scrollTop = 1e9 };
    (await B.chat.history(ch)).forEach(add); const un = B.chat.subscribe(ch, m => { if (!m.mine) add(m) }); NX.onLeave(un);
    const send = async t => { t = (t || inp.value).trim(); if (!t) return; inp.value = ''; try { const m = await B.chat.send(ch, t); if (m) add(m) } catch (e) { NX.err(e) } };
    inp.onkeydown = e => { if (e.key === 'Enter') send() };
    return el('div', { class: 'chat' }, msgs, el('div', { class: 'qc' }, CFG.QUICK_CHAT.map(t => el('button', { onclick: () => send(t) }, t))), el('div', { class: 'cin' }, inp, el('button', { class: 'ibtn', onclick: () => send() }, svg('send'))));
  };
  S.chat = async (p) => {
    if (!NX.online()) return NX.offlineScreen('Chat', 'Chat needs the online server.');
    const ch = (p && p.ch) || 'global'; const friends = await B.friends.list(); let tabsEl = null;
    if (ch === 'global' || ch.startsWith('dm:')) tabsEl = el('div', { class: 'tabs', style: { margin: '0 14px 6px' } }, el('button', { class: ch === 'global' ? 'on' : '', onclick: () => NX.go('chat', { ch: 'global' }, { root: 0 }) }, 'Global'), ...friends.slice(0, 6).map(f => el('button', { class: ch === 'dm:' + f.id ? 'on' : '', onclick: () => NX.go('chat', { ch: 'dm:' + f.id, title: f.name }) }, f.name)));
    return el('div', { class: 'scr' }, NX.topbar(p && p.title ? p.title : 'Chat'), tabsEl, await NX.chatView(ch));
  };

  /* ---------------- lobby / rooms ---------------- */
  S.lobby = async () => {
    if (!NX.online()) return NX.offlineScreen('Lobby', 'Rooms need the online server.');
    const rooms = await B.rooms.list(), code = el('input', { class: 'inp', placeholder: 'ROOM CODE', maxlength: 5, style: { textTransform: 'uppercase', letterSpacing: '4px', textAlign: 'center' } });
    const join = c => async e => NX.busy(e.currentTarget, async () => { await B.rooms.join(c); NX.go('room') });
    return el('div', { class: 'scr' }, NX.topbar('Lobby'), NX.page([el('div', { class: 'card pad', style: { textAlign: 'center' } }, NX.ico('lobby', '', 0), el('div', { class: 'row', style: { marginTop: '6px' } }, el('button', { class: 'btn gold', style: { flex: 1 }, onclick: e => NX.busy(e.currentTarget, async () => { await B.rooms.create({ goals: 5 }); NX.go('room') }) }, 'Create room'), el('button', { class: 'btn ghost', style: { flex: 1 }, onclick: () => NX.go('room', { pick: true }) }, 'Join by code'))),
      el('div', { class: 'sec' }, 'Public rooms', el('a', { onclick: () => NX.render() }, svg('refresh'))), ...rooms.map(r => el('div', { class: 'lrow' }, NX.avatar(r.host, 'xs'), el('div', { class: 't' }, el('b', null, r.name), el('small', null, r.field + ' · first to ' + r.goals + ' · ' + r.players + '/' + r.max)), el('button', { class: 'btn gold sm', onclick: join(r.id) }, 'Join')))]));
  };
  S.room = async (p) => {
    if (p && p.pick) { const code = el('input', { class: 'inp', placeholder: 'ROOM CODE', maxlength: 5, style: { textTransform: 'uppercase', letterSpacing: '6px', textAlign: 'center', fontSize: '22px' } }); return el('div', { class: 'scr' }, NX.topbar('Join room'), NX.page([el('p', { class: 'mut', style: { textAlign: 'center' } }, 'Enter the 5-letter code from your friend'), code, el('div', { style: { height: '12px' } }), el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.rooms.join(code.value.trim().toUpperCase()); NX.stack.pop(); NX.go('room') }) }, 'Join')])) }
    let room = null; const slots = el('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px' } }), actions = el('div', { class: 'row', style: { margin: '12px 0' } }), chatHost = el('div', { class: 'card', style: { height: '260px', display: 'flex', flexDirection: 'column', overflow: 'hidden' } });
    const slot = (pl, ready, label) => pl ? el('div', { class: 'slot f' }, NX.avatar(pl, 'sm', true), el('div', { style: { flex: 1, minWidth: 0 } }, el('b', null, pl.name), el('div', { class: 'mut', style: { fontSize: '11px' } }, label + ' · ' + pl.league.label)), el('span', { class: 'r ' + (ready ? 'y' : '') }, ready ? 'READY' : 'NOT READY')) : el('div', { class: 'slot' }, el('div', { class: 'av sm', style: { opacity: .3 } }, el('img', { src: 'assets/ui/i_user.webp' })), el('div', { class: 'mut', style: { flex: 1 } }, 'Waiting for opponent…'), el('div', { class: 'chip' }, 'Invite code: ' + room.code));
    const drawRoom = () => {
      if (!room) return; slots.replaceChildren(slot(room.host, room.ready.host, 'Host'), slot(room.guest, room.ready.guest, 'Guest'));
      const my = room.isHost ? room.ready.host : room.ready.guest; actions.replaceChildren(
        el('button', { class: 'ibtn', onclick: async () => { NX.UI.mic = NX.UI.mic ? 0 : 1; try { await B.voice.setMic(!!NX.UI.mic) } catch (e) { NX.UI.mic = 0; NX.err(e) } NX.saveUI(); drawRoom() } }, svg('mic'), NX.UI.mic ? null : el('i', { class: 'dot' })),
        el('button', { class: 'ibtn', onclick: () => { NX.UI.spk = NX.UI.spk ? 0 : 1; B.voice.setSpeaker(!!NX.UI.spk); NX.saveUI(); drawRoom() } }, svg('spk'), NX.UI.spk ? null : el('i', { class: 'dot' })),
        el('button', { class: 'btn ' + (my ? 'ghost' : 'gold'), style: { flex: 1 }, onclick: async () => { room = await B.rooms.setReady(!my); drawRoom() } }, my ? 'Cancel ready' : 'Ready'),
        room.isHost ? el('button', { class: 'btn gold', style: { flex: 1 }, onclick: e => NX.busy(e.currentTarget, async () => { const d = await B.rooms.start(); NX.flow.begin(d) }) }, NX.svg('play'), 'Start') : null)
    };
    room = await B.rooms.current(); if (!room) { NX.stack.pop(); return S.lobby() }
    const un = B.rooms.onChange(ev => { if (ev.type === 'state') { room = ev.room; drawRoom() } else if (ev.type === 'start') { NX.flow.begin(ev.desc) } }); NX.onLeave(un);
    NX.onLeave(() => { if (!NX.flow.inMatch) B.rooms.leave() });
    drawRoom(); chatHost.append(await NX.chatView('room:' + room.code));
    return el('div', { class: 'scr' }, NX.topbar('Room', el('button', { class: 'ibtn', onclick: () => { try { navigator.clipboard.writeText(room.code) } catch (e) { } NX.toast('Code ' + room.code + ' copied') } }, svg('copy'))), NX.page([slots, actions, el('div', { class: 'sec' }, 'Room chat'), chatHost]));
  };

  /* ---------------- teams & formation ---------------- */
  S.teams = async () => {
    const P = NX.P; let cat = G.catOf(P.team), team = P.team, form = P.form || 0; const grid = el('div', { class: 'tgrid' }), tabs = el('div', { class: 'tabs' }), fm = el('div', { class: 'fm' });
    const draw = () => {
      tabs.replaceChildren(...G.CATS.map((c, i) => el('button', { class: cat === i ? 'on' : '', onclick: () => { cat = i; draw() } }, c[1])));
      grid.replaceChildren(...G.TEAMS.filter(t => t.cat === G.CATS[cat][0]).map(t => el('button', { class: 'tc ' + (team === t.id ? 'sel' : ''), onclick: async () => { team = t.id; await B.profile.update({ team: t.id }); draw() } }, el('img', { src: t.src, loading: 'lazy' }), el('span', null, t.name))));
      fm.replaceChildren(...G.FORMS.map((f, i) => { const cv = document.createElement('canvas'); cv.width = 120; cv.height = 100; const x = cv.getContext('2d'); x.fillStyle = '#16301c'; x.fillRect(0, 0, 120, 100); x.strokeStyle = 'rgba(255,255,255,.6)'; x.lineWidth = 2; x.strokeRect(2, 2, 116, 96); x.beginPath(); x.moveTo(2, 2); x.lineTo(118, 2); x.stroke(); for (const [nx, ny] of G.slots(i)) { x.fillStyle = '#4aa8ff'; x.beginPath(); x.arc(14 + nx * 92, 92 - ny / .5 * 80, 8, 0, 7); x.fill(); x.strokeStyle = '#fff'; x.stroke() } return el('button', { class: form === i ? 'sel' : '', onclick: async () => { form = i; await B.profile.update({ form: i }); draw() } }, cv, el('b', null, f[0]), el('span', { class: 'mut' }, f[1])) }));
    }; draw();
    return el('div', { class: 'scr' }, NX.topbar('Team & formation'), NX.page([el('div', { class: 'sec', style: { marginTop: '4px' } }, 'Your team'), tabs, el('div', { style: { height: '10px' } }), grid, el('div', { class: 'sec' }, 'Formation'), fm]));
  };

  /* ---------------- pitch & ball ---------------- */
  S.fieldball = async () => {
    let P = NX.P; const items = await B.shop.items(), fields = items.filter(i => i.type === 'field'), balls = items.filter(i => i.type === 'ball'); const fb = el('div', { class: 'fgrid' }), bb = el('div', { class: 'bgrid' }), info = el('div', { class: 'card pad', style: { marginBottom: '8px' } });
    const draw = async () => {
      const it = await B.shop.items(), fs = it.filter(i => i.type === 'field'), bs = it.filter(i => i.type === 'ball'), eb = bs.find(b => b.equipped), cols = G.TR[eb.key].c; info.replaceChildren(el('div', { class: 'row' }, el('img', { src: eb.img, style: { width: '48px' } }), el('div', { style: { flex: 1 } }, el('b', null, eb.name), el('div', { class: 'mut', style: { fontSize: '12px' } }, 'Light trail: ' + G.TRN[eb.key])), NX.ico('xp', '', 0)), el('div', { class: 'trail-prev', style: { background: 'linear-gradient(90deg,transparent,' + cols.join(',') + ')' } }));
      info.querySelector('.row img:last-child').style.width = '40px';
      fb.replaceChildren(...fs.map(f => el('button', { class: 'fc ' + (f.equipped ? 'sel' : '') + (f.owned ? '' : ' lk'), onclick: async () => { if (f.owned) { await B.shop.equip('field', f.key) } else NX.confirm('Unlock ' + f.name, 'Buy for ' + fmt(f.price) + ' coins?', 'Buy', async () => { try { await B.shop.buy(f.id); await B.shop.equip('field', f.key) } catch (e) { NX.err(e) } draw() }); draw() } }, el('img', { src: f.img }), el('b', null, f.name.replace(' Pitch', '')), f.owned ? null : el('i', { class: 'lkb' }, svg('lock')))));
      bb.replaceChildren(...bs.map(b => el('button', { class: 'bc ' + (b.equipped ? 'sel' : '') + (b.owned ? '' : ' lk'), onclick: async () => { if (b.owned) { await B.shop.equip('ball', b.key) } else NX.confirm('Unlock ' + b.name, 'Buy for ' + fmt(b.price) + ' coins?', 'Buy', async () => { try { await B.shop.buy(b.id); await B.shop.equip('ball', b.key) } catch (e) { NX.err(e) } draw() }); draw() } }, el('img', { src: b.img }), b.owned ? null : el('i', { class: 'lkb' }, svg('lock')))));
    }; draw();
    return el('div', { class: 'scr' }, NX.topbar('Pitch & ball'), NX.page([info, el('div', { class: 'sec', style: { marginTop: '10px' } }, 'Balls'), bb, el('div', { class: 'sec' }, 'Pitches'), fb]));
  };
})();
