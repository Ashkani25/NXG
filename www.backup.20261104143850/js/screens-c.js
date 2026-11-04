/* BERMUDA NXG — online screens: rooms, chats inbox, AI coach, follow / like profile sheet, tournaments (cups + leagues).
   Loaded after flow.js. Every list shows real server data; empty states are shown honestly. */
(() => {
  'use strict';
  const NX = window.NX, { el, svg, fmt, B, G, CFG } = NX, S = NX.screens, F = NX.flow;
  const ago = t => { const s = Math.max(1, (Date.now() - t) / 1000 | 0); return s < 60 ? 'now' : s < 3600 ? (s / 60 | 0) + 'm' : s < 86400 ? (s / 3600 | 0) + 'h' : (s / 86400 | 0) + 'd' };
  const until = t => { const s = Math.max(0, (t - Date.now()) / 1000 | 0); return s < 60 ? 'soon' : s < 3600 ? (s / 60 | 0) + ' min' : s < 86400 ? (s / 3600 | 0) + ' h' : (s / 86400 | 0) + ' d' };
  const needOnline = title => NX.offlineScreen(title, 'Sign in with an account (or guest) on the online server to use this.');
  const hasTab = (list, cur, set) => el('div', { class: 'tabs' }, list.map(([k, l]) => el('button', { class: cur === k ? 'on' : '', onclick: () => set(k) }, l)));

  /* ---------- profile sheet: follow / like / message / friend ---------- */
  F.profileSheet = async p => {
    const mine = NX.P && p.id === NX.P.id, stats = el('div', { class: 'psx' }), acts = el('div', { class: 'acts' }), m = NX.modal([NX.avatar(p, 'lg', true), el('h3', { style: { marginTop: '12px' } }, p.name),
      el('div', { class: 'chip', style: { color: p.league.color } }, svg('trophy'), p.league.label + ' · ' + fmt(p.trophies)), p.bio ? el('p', { class: 'mut', style: { margin: '8px 0 0' } }, p.bio) : null, stats, acts]);
    const stat = (n, l, kind) => el('div', { style: { cursor: 'pointer' }, onclick: () => { m.close(); NX.go('followlist', { kind, id: p.id, title: l, name: p.name }) } }, el('b', null, fmt(n)), el('small', null, l));
    const draw = st => { stats.replaceChildren(stat(st.followers, 'Followers', 'followers'), stat(st.followingCount, 'Following', 'following'), el('div', null, el('b', null, fmt(st.likes)), el('small', null, 'Likes')));
      acts.replaceChildren(
        mine ? null : el('button', { class: 'btn ' + (st.following ? 'ghost' : 'gold'), onclick: e => NX.busy(e.currentTarget, async () => { st.following ? await B.social.unfollow(p.id) : await B.social.follow(p.id); draw(await B.social.state(p.id)) }) }, svg('users'), st.following ? 'Following' : st.followedBy ? 'Follow back' : 'Follow'),
        mine ? null : el('button', { class: 'btn ' + (st.liked ? 'gold' : 'ghost'), onclick: e => NX.busy(e.currentTarget, async () => { await B.social.like(p.id); draw(await B.social.state(p.id)) }) }, svg('heart'), st.liked ? 'Liked' : 'Like'),
        mine ? null : el('button', { class: 'btn ghost', onclick: () => { m.close(); NX.go('chat', { ch: 'dm:' + p.id, title: p.name }) } }, svg('chat'), 'Message'),
        mine ? null : el('button', { class: 'btn ghost', onclick: e => NX.busy(e.currentTarget, async () => { await B.friends.add(p.id); NX.toast('Friend request sent', 'ok') }) }, svg('users'), 'Add friend')) };
    if (!NX.online()) { acts.append(el('p', { class: 'mut' }, 'Online server required')); return }
    try { draw(await B.social.state(p.id)) } catch (e) { NX.err(e) } };

  S.followlist = async p => {
    if (!NX.online()) return needOnline(p.title);
    const l = await B.social.list(p.kind, p.id);
    return el('div', { class: 'scr' }, NX.topbar(p.title), NX.page(l.length ? [el('p', { class: 'mut', style: { textAlign: 'center' } }, p.name), ...l.map(u => el('div', { class: 'lrow', onclick: () => F.profileSheet(u) }, NX.avatar(u, 'xs'), el('div', { class: 't' }, el('b', null, u.name), el('small', null, u.league.label + ' · Lv ' + u.level)), el('b', null, fmt(u.trophies))))] : el('div', { class: 'empty' }, 'Nobody here yet'))) };

  /* ---------- chats inbox ---------- */
  S.inbox = async () => {
    if (!NX.online()) return needOnline('Chats');
    const box = el('div'), q = el('input', { placeholder: 'Find a player to message…' }), res = el('div');
    const row = (icon, title, sub, onclick, right) => el('div', { class: 'lrow', onclick }, icon, el('div', { class: 't' }, el('b', null, title), el('small', null, sub)), right);
    const draw = async () => { const list = await B.inbox.list();
      box.replaceChildren(
        row(NX.ico('chat', 'ic0 sm'), 'Global chat', 'Everyone online', () => NX.go('chat', { ch: 'global', title: 'Global chat' })),
        row(NX.ico('start_rocket', 'ic0 sm'), 'NX Coach (AI)', 'Tips, tactics and app help', () => NX.go('assistant')),
        el('div', { class: 'sec' }, 'Messages'),
        ...(list.length ? list.map(c => c.other ? el('div', { class: 'lrow', onclick: () => NX.go('chat', { ch: c.ch, title: c.other.name }) }, NX.avatar(c.other, 'xs'), el('div', { class: 't' }, el('b', null, c.other.name), el('small', null, (c.mine ? 'You: ' : '') + c.last)), el('div', { style: { textAlign: 'right' } }, el('small', { class: 'mut' }, ago(c.lastAt)), c.unread ? el('div', { class: 'ubadge' }, c.unread > 9 ? '9+' : c.unread) : null)) : null) : [el('div', { class: 'empty' }, 'No messages yet. Search a player above or open a profile and tap Message.')])) };
    q.oninput = async () => { const v = q.value.trim(); if (v.length < 2) { res.replaceChildren(); return } const l = await B.profile.search(v); res.replaceChildren(...l.map(p => el('div', { class: 'lrow', onclick: () => F.profileSheet(p) }, NX.avatar(p, 'xs'), el('div', { class: 't' }, el('b', null, p.name), el('small', null, p.league.label + ' · Lv ' + p.level)), el('button', { class: 'ibtn sm', onclick: ev => { ev.stopPropagation(); NX.go('chat', { ch: 'dm:' + p.id, title: p.name }) } }, svg('chat'))))) };
    await draw(); NX.onLeave(B.inbox.onChange(() => draw().catch(() => { })));
    return el('div', { class: 'scr' }, NX.topbar('Chats', el('button', { class: 'ibtn', onclick: () => NX.go('friends') }, svg('users'))), NX.page([el('div', { class: 'sbox' }, svg('search'), q), res, el('div', { style: { height: '10px' } }), box], true), NX.navbar('chat')) };
  const origChat = S.chat; S.chat = async p => { const r = await origChat(p); return r };

  /* ---------- AI coach ---------- */
  S.assistant = async () => {
    if (!NX.online()) return needOnline('NX Coach');
    const msgs = el('div', { class: 'msgs' }), inp = el('input', { placeholder: 'Ask about tactics, rewards, rooms…', maxlength: 400 }), hist = [];
    const add = (role, text) => { const b = el('div', { class: 'msg ' + (role === 'user' ? 'me' : '') }, el('div', { class: 'bub' }, role === 'user' ? null : el('small', null, 'NX Coach'), text)); msgs.append(b); msgs.scrollTop = 1e9; return b };
    add('assistant', 'Hi! I am NX Coach. Ask me how to aim better, defend your goal, earn coins, use rooms or join tournaments.');
    const send = async t => { t = (t || inp.value).trim(); if (!t) return; inp.value = ''; add('user', t); hist.push({ role: 'user', content: t }); const wait = add('assistant', '…');
      try { const a = await B.ai.ask(hist); wait.querySelector('.bub').lastChild.textContent = a; hist.push({ role: 'assistant', content: a }) } catch (e) { wait.remove(); hist.pop(); NX.err(e) } msgs.scrollTop = 1e9 };
    inp.onkeydown = e => { if (e.key === 'Enter') send() };
    const chips = ['How do I score more goals?', 'How to defend?', 'How do ranked trophies work?', 'How do rooms work?'];
    return el('div', { class: 'scr' }, NX.topbar('NX Coach'), el('div', { class: 'chat' }, msgs, el('div', { class: 'qc' }, chips.map(t => el('button', { onclick: () => send(t) }, t))), el('div', { class: 'cin' }, inp, el('button', { class: 'ibtn', onclick: () => send() }, svg('send'))))) };

  /* ---------- lobby: active rooms + create ---------- */
  const fieldName = id => { const f = G.FIELDS.find(x => x.id === id); return f ? f.name : id };
  S.lobby = async () => {
    if (!NX.online()) return needOnline('Rooms');
    const list = el('div'), code = el('input', { class: 'inp', placeholder: 'ROOM CODE', maxlength: 5, style: { textTransform: 'uppercase', letterSpacing: '4px', textAlign: 'center' } });
    const join = c => e => NX.busy(e.currentTarget, async () => { await B.rooms.join(c); NX.go('room') });
    const draw = async () => { const rooms = await B.rooms.list(); list.replaceChildren(...(rooms.length ? rooms.map(r => el('div', { class: 'lrow' }, NX.avatar(r.host, 'xs'), el('div', { class: 't' }, el('b', null, r.name), el('small', null, fieldName(r.field) + ' · ' + r.minutes + ' min · host ' + r.host.name)), el('button', { class: 'btn gold sm', onclick: join(r.code) }, 'Join'))) : [el('div', { class: 'empty' }, 'No public rooms right now. Create one!')])) };
    const create = () => { let pub = true, mins = 5, field = (NX.P.equip && NX.P.equip.field) || 'stadium'; const name = el('input', { class: 'inp', placeholder: 'Room name', maxlength: 24, value: NX.P.name + "'s room" }), seg = el('div', { class: 'seg', style: { justifyContent: 'center', margin: '8px 0' } }), vis = el('div', { class: 'seg', style: { justifyContent: 'center', margin: '8px 0' } }), owned = (NX.P.owned && NX.P.owned.fields) || ['stadium'];
      const fsel = el('select', { class: 'inp', onchange: e => field = e.target.value }, owned.map(id => el('option', { value: id, selected: id === field }, fieldName(id))));
      const dr = () => { seg.replaceChildren(...[3, 5, 7, 10].map(v => el('button', { class: mins === v ? 'on' : '', onclick: () => { mins = v; dr() } }, v + ' min'))); vis.replaceChildren(...[[true, 'Public'], [false, 'Private']].map(([v, l]) => el('button', { class: pub === v ? 'on' : '', onclick: () => { pub = v; dr() } }, l))) }; dr();
      const m = NX.modal([NX.ico('lobby', 'bigimg'), el('h3', { class: 'gold' }, 'Create room'), name, el('small', { class: 'mut' }, 'Match length (unlimited goals)'), seg, vis, fsel, el('div', { style: { height: '8px' } }), el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.rooms.create({ name: name.value, public: pub, matchTime: mins * 60, field }); m.close(); NX.go('room') }) }, 'Create')]) };
    await draw(); const iv = setInterval(() => draw().catch(() => { }), 8000); NX.onLeave(() => clearInterval(iv));
    return el('div', { class: 'scr' }, NX.topbar('Rooms', el('button', { class: 'ibtn', onclick: () => draw() }, svg('refresh'))), NX.page([el('div', { class: 'card pad', style: { textAlign: 'center' } }, NX.ico('lobby', '', 0), el('button', { class: 'btn gold block', style: { marginTop: '8px' }, onclick: create }, 'Create room'), el('div', { class: 'row', style: { marginTop: '10px', gap: '8px' } }, code, el('button', { class: 'btn ghost sm', onclick: e => { if (code.value.trim().length === 5) join(code.value.trim().toUpperCase())(e); else NX.toast('Enter the 5-letter code') } }, 'Join'))),
      el('div', { class: 'sec' }, 'Active rooms'), list])) };

  /* ---------- notifications (tap to act) ---------- */
  S.notifications = async () => {
    const l = await B.notifications.list(); await B.notifications.markAllRead().catch(() => { });
    const act = async n => { try { if (n.kind === 'invite' && n.data && n.data.code) { await B.rooms.join(n.data.code); NX.go('room') } else if (n.data && n.data.id && ['follow', 'like', 'friend'].includes(n.kind)) { const p = await B.profile.publicProfile(n.data.id); if (p) F.profileSheet(p) } else if (n.kind === 'tournament' && n.data && n.data.id) NX.go('tournament', { id: n.data.id }) } catch (e) { NX.err(e) } };
    return el('div', { class: 'scr' }, NX.topbar('Notifications'), NX.page(l.length ? l.map(n => el('div', { class: 'lrow', onclick: () => act(n) }, el('div', { class: 'cal', style: { width: '42px', height: '42px', fontSize: '22px' } }, svg(n.kind === 'friend' || n.kind === 'follow' ? 'users' : n.kind === 'tournament' ? 'trophy' : n.kind === 'like' ? 'heart' : 'bell')), el('div', { class: 't' }, el('b', null, n.title), el('small', null, n.body)), el('small', { class: 'mut' }, ago(n.t)))) : el('div', { class: 'empty' }, 'No notifications yet'))) };

  /* ---------- tournaments ---------- */
  const typeLabel = t => t.type === 'league' ? 'League' : 'Cup';
  S.tournaments = async p => {
    if (!NX.online()) return needOnline('Tournaments');
    let tab = (p && p.tab) || 'all'; const box = el('div'), tabs = el('div'); let data = await B.tournaments.list();
    const card = t => el('div', { class: 'card pad', style: { marginBottom: '12px', opacity: t.locked ? .6 : 1 }, onclick: () => !t.locked && NX.go('tournament', { id: t.id }) },
      el('div', { class: 'row' }, NX.ico(t.type === 'league' ? 'league' : 'tournament', '', 0), el('div', { style: { flex: 1, minWidth: 0 } }, el('b', { style: { fontSize: '17px' } }, t.name), el('div', { class: 'mut', style: { fontSize: '12px', margin: '2px 0 6px' } }, t.desc),
        el('div', { class: 'row', style: { gap: '6px', flexWrap: 'wrap' } }, el('span', { class: 'chip' }, typeLabel(t)), el('span', { class: 'chip' }, svg('users'), t.count + '/' + t.size), el('span', { class: 'chip' }, 'Entry ', t.fee ? NX.cur(t.fee, t.cur) : 'Free'),
          t.locked ? el('span', { class: 'chip' }, svg('lock'), 'Lv ' + t.minLevel) : null, t.joined ? el('span', { class: 'chip', style: { color: 'var(--ok)' } }, 'Joined') : null, t.status === 'open' ? el('span', { class: 'chip' }, 'Starts in ' + until(t.startsAt)) : el('span', { class: 'chip', style: { color: 'var(--acc)' } }, 'Live')))),
      (t.prize || t.gems) ? el('div', { class: 'row', style: { marginTop: '10px', justifyContent: 'space-between' } }, el('span', { class: 'mut', style: { fontSize: '12px' } }, 'Prize'), el('div', { class: 'row' }, t.prize ? NX.cur(t.prize) : null, t.gems ? NX.cur(t.gems, 'gems') : null)) : null);
    const draw = () => { tabs.replaceChildren(hasTab([['all', 'All'], ['cup', 'Cups'], ['league', 'Leagues'], ['mine', 'Mine']], tab, k => { tab = k; draw() }));
      const l = data.filter(t => tab === 'all' || (tab === 'mine' ? t.joined || t.createdByMe : t.type === tab)); box.replaceChildren(...(l.length ? l.map(card) : [el('div', { class: 'empty' }, 'Nothing here yet. Official tournaments appear every few hours, or create your own.')])) }; draw();
    const create = () => { let type = 'cup', size = 8; const name = el('input', { class: 'inp', placeholder: 'Tournament name', maxlength: 28 }), fee = el('input', { class: 'inp', type: 'number', min: 0, max: 1000, value: 0, placeholder: 'Entry fee (coins)' }), st = el('input', { class: 'inp', type: 'number', min: 10, max: 1440, value: 30, placeholder: 'Starts in (minutes)' }), a = el('div', { class: 'seg', style: { justifyContent: 'center', margin: '8px 0' } }), b = el('div', { class: 'seg', style: { justifyContent: 'center', margin: '8px 0' } });
      const dr = () => { a.replaceChildren(...[['cup', 'Knockout cup'], ['league', 'League']].map(([k, l]) => el('button', { class: type === k ? 'on' : '', onclick: () => { type = k; size = k === 'cup' ? 8 : 6; dr() } }, l))); b.replaceChildren(...(type === 'cup' ? [4, 8, 16] : [4, 6, 8]).map(v => el('button', { class: size === v ? 'on' : '', onclick: () => { size = v; dr() } }, v + ' players'))) }; dr();
      const m = NX.modal([NX.ico('tournament', 'bigimg'), el('h3', { class: 'gold' }, 'Create tournament'), name, a, b, el('small', { class: 'mut' }, 'Entry fee (coins). 90% of fees go to the winner.'), fee, el('small', { class: 'mut' }, 'Starts in (minutes). Starts early when full.'), st, el('div', { style: { height: '8px' } }), el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { const r = await B.tournaments.create({ name: name.value, type, size, fee: +fee.value || 0, startsInMin: +st.value || 30 }); m.close(); NX.go('tournament', { id: r.id }) }) }, 'Create')]) };
    return el('div', { class: 'scr' }, NX.topbar('Tournaments', el('button', { class: 'ibtn', onclick: create }, svg('plus'))), NX.page([tabs, el('div', { style: { height: '12px' } }), box])) };

  S.tournament = async p => {
    const t = await B.tournaments.get(p.id), P = NX.P;
    const nm = x => x && x.id ? x.name : 'TBD';
    const bracket = () => el('div', { class: 'bk' }, t.rounds.map(r => el('div', { class: 'rd' }, el('h5', null, r.name), r.matches.map(m => { const row = x => el('div', { class: (m.winner ? (m.winner === x.id ? 'w' : 'l') : '') + (x.id === t.myId ? ' you' : '') }, nm(x)); return el('div', { class: 'bm' }, row(m.a), row(m.b)) }))));
    const table = () => el('div', { class: 'card pad' }, el('div', { class: 'lrow', style: { fontSize: '11px', opacity: .7 } }, el('div', { class: 't' }, 'Player'), el('b', { style: { width: '28px' } }, 'P'), el('b', { style: { width: '40px' } }, 'GD'), el('b', { style: { width: '34px' } }, 'Pts')),
      t.table.map((r, i) => el('div', { class: 'lrow' + (r.player.id === t.myId ? ' me' : '') }, el('b', { style: { width: '20px' } }, i + 1), el('div', { class: 't' }, nm(r.player)), el('span', { style: { width: '28px' } }, r.p), el('span', { style: { width: '40px' } }, (r.gf - r.ga > 0 ? '+' : '') + (r.gf - r.ga)), el('b', { style: { width: '34px' } }, r.pts))));
    const myFx = () => { const rs = t.type === 'cup' ? [t.rounds[t.round]] : t.rounds; for (const r of rs) { if (!r) continue; const m = r.matches.find(x => !x.winner && x.a.id && x.b.id && (x.a.id === t.myId || x.b.id === t.myId)); if (m) return { m, r } } return null };
    const head = el('div', { class: 'card pad', style: { textAlign: 'center', marginBottom: '12px' } }), put = (...a) => head.append(...a.flat(5).filter(Boolean));
    const info = [el('span', { class: 'chip' }, typeLabel(t)), el('span', { class: 'chip' }, svg('users'), t.count + '/' + t.size), el('span', { class: 'chip' }, 'Entry ', t.fee ? NX.cur(t.fee, t.cur) : 'Free')];
    if (t.status === 'open') put(el('p', { class: 'mut' }, t.desc), el('div', { class: 'row', style: { justifyContent: 'center', gap: '6px', flexWrap: 'wrap' } }, info), el('p', { class: 'mut' }, 'Starts in ' + until(t.startsAt) + ' (or when full). Needs ' + (t.type === 'cup' ? 4 : 3) + '+ players, otherwise entry fees are refunded.'),
      t.joined ? el('button', { class: 'btn dark', onclick: e => NX.busy(e.currentTarget, async () => { await B.tournaments.leave(p.id); NX.render() }) }, 'Leave (refund)') : el('button', { class: 'btn gold', onclick: e => NX.busy(e.currentTarget, async () => { await B.tournaments.join(p.id); NX.toast('You are in!', 'ok'); NX.render() }) }, 'Join tournament'));
    else if (t.status === 'active') { const fx = t.joined && myFx();
      put(el('div', { class: 'row', style: { justifyContent: 'center', gap: '6px', flexWrap: 'wrap', marginBottom: '8px' } }, info, el('span', { class: 'chip' }, 'Round ends in ' + until(t.roundEnds))),
        !t.joined ? el('p', { class: 'mut' }, 'Registration closed. You can watch the bracket.') : fx ? [el('small', { class: 'mut' }, fx.r.name.toUpperCase()), el('h3', { class: 'gold', style: { margin: '6px 0' } }, 'vs ' + nm(fx.m.a.id === t.myId ? fx.m.b : fx.m.a)), el('p', { class: 'mut', style: { fontSize: '12px' } }, 'Both players press Play to start. If your opponent does not show up before the round ends you win by walkover.'), el('button', { class: 'btn gold', onclick: e => NX.busy(e.currentTarget, async () => { NX.toast('Waiting for your opponent…'); const d = await B.tournaments.nextMatch(p.id); NX.flow.begin(d) }) }, NX.svg('play'), 'Play match')] : el('p', { class: 'mut' }, t.type === 'cup' ? 'You are out, or waiting for the other matches of this round.' : 'You played all your fixtures. Waiting for the others.')) }
    else put(el('h3', { class: 'gold' }, t.status === 'cancelled' ? 'Cancelled' : 'Finished'), t.winner ? el('p', null, 'Winner: ', el('b', null, t.winner.name)) : null);
    return el('div', { class: 'scr' }, NX.topbar(t.name), NX.page([head, t.type === 'league' && t.table ? [el('div', { class: 'sec' }, 'Table'), table()] : null, t.rounds.length ? [el('div', { class: 'sec' }, t.type === 'league' ? 'Fixtures' : 'Bracket'), bracket()] : [el('div', { class: 'sec' }, 'Players'), ...t.players.map(x => el('div', { class: 'lrow', onclick: async () => { const pp = await B.profile.publicProfile(x.id); if (pp) F.profileSheet(pp) } }, NX.avatar(x, 'xs'), el('div', { class: 't' }, el('b', null, x.name))))]])) };
})();
