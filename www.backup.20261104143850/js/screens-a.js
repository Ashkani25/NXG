(() => {
  'use strict';
  const NX = window.NX, { el, svg, ico, fmt, B, G, CFG } = NX, S = NX.screens;

  /* ---------------- splash ---------------- */
  S.splash = () => {
    let fin; NX.introDone = new Promise(r => fin = r); let done = false; const finish = () => { if (!done) { done = true; clearInterval(wd); fin() } };
    const v = el('video', { class: 'intro4', playsinline: '', preload: 'auto' }), t0 = Date.now();
    v.setAttribute('webkit-playsinline', ''); v.setAttribute('playsinline', ''); v.playsInline = true;
    for (const [f, t] of [['intro.mp4', 'video/mp4'], ['intro.webm', 'video/webm']]) v.append(el('source', { src: 'assets/' + f + '?v=3', type: t }));
    v.onended = finish; let started = false, last = -1, stall = 0;
    v.addEventListener('playing', () => { started = true });
    // watchdog: never block the game if the video cannot start or freezes
    const wd = setInterval(() => { const el_ = Date.now() - t0; if (!started && el_ > 4500) return finish(); if (started) { if (v.currentTime === last && !v.paused) stall++; else stall = 0; last = v.currentTime; if (stall > 12) finish() } }, 250);
    const play = async () => { try { v.muted = false; await v.play() } catch (e) { try { v.muted = true; await v.play() } catch (e2) { } } };
    v.load(); setTimeout(play, 60); v.addEventListener('canplay', () => { if (v.paused) play() }, { once: true }); setTimeout(finish, 9000);
    return el('div', { class: 'scr splash4', onclick: () => { if (Date.now() - t0 > 1200) finish() } }, v);
  };


  /* ---------------- auth ---------------- */
  S.auth = (p) => {
    let mode = 'login'; const err = el('div', { class: 'err' }), name = el('input', { class: 'inp', placeholder: 'Username', maxlength: 16, style: { display: 'none' } }),
      mail = el('input', { class: 'inp', type: 'email', placeholder: 'Email', autocomplete: 'email' }), pw = el('input', { class: 'inp', type: 'password', placeholder: 'Password (6+ characters)', autocomplete: 'current-password' });
    const main = el('button', { class: 'btn gold block' }, 'Sign in'), sw = el('button', { class: 'btn ghost block' }, 'Create new account'), forgot = el('button', { class: 'mut', style: { fontSize: '13px', padding: '6px' } }, 'Forgot password?');
    const sync = () => { const s = mode === 'signup'; name.style.display = s ? 'block' : 'none'; main.textContent = s ? 'Create account' : 'Sign in'; sw.textContent = s ? 'I already have an account' : 'Create new account'; forgot.style.display = s ? 'none' : 'block'; err.textContent = '' };
    const done = async () => { await NX.afterAuth() };
    main.onclick = () => NX.busy(main, async () => { err.textContent = ''; try { if (mode === 'signup') await B.auth.signUp(mail.value.trim(), pw.value, name.value.trim()); else await B.auth.signIn(mail.value.trim(), pw.value); await done() } catch (e) { err.textContent = e.message } });
    sw.onclick = () => { mode = mode === 'login' ? 'signup' : 'login'; sync() };
    forgot.onclick = () => NX.busy(forgot, async () => { try { await B.auth.resetPassword(mail.value.trim()); NX.toast('Reset link sent to your email', 'ok') } catch (e) { err.textContent = e.message } });
    const oauth = pr => () => NX.busy(event.currentTarget, async () => { try { await B.auth.oauth(pr); await done() } catch (e) { err.textContent = e.message } });
    const F = B.features || {}, emailUI = F.email ? [name, mail, pw, err, main, forgot, sw, el('div', { class: 'or' }, 'OR')] : [], socUI = F.oauth ? [el('div', { class: 'soc' }, el('button', { class: 'btn dark', onclick: oauth('google') }, 'Google'), el('button', { class: 'btn dark', onclick: oauth('apple') }, 'Apple'))] : [];
    const root = el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), el('div', { class: 'auth', style: F.email ? null : { justifyContent: 'center' } },
      el('div', { class: 'lg' }, NX.ico('nexora_x_logo'), el('b', { class: 'gold' }, 'BERMUDA NXG'), el('small', null, 'ONLINE. PLAY MORE.')),
      ...emailUI, ...socUI,
      el('button', { class: 'btn ghost block', onclick: e => NX.busy(e.currentTarget, async () => { await B.auth.signInGuest(); await done() }) }, NX.svg('play'), 'Play as guest'),
      el('small', { class: 'mut', style: { textAlign: 'center', lineHeight: 1.5 } }, 'By continuing you accept the Terms of Service and Privacy Policy.')));
    if (F.email) sync(); return root;
  };

  /* ---------------- onboarding (name + team) ---------------- */
  S.onboard = () => {
    const P = NX.P; let team = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16, placeholder: 'Choose your name' });
    const grid = el('div', { class: 'tgrid' }); const draw = () => { grid.replaceChildren(...G.TEAMS.filter(t => t.cat === 'club' || t.cat === 'nat').slice(0, 40).map(t => el('button', { class: 'tc ' + (team === t.id ? 'sel' : ''), onclick: () => { team = t.id; draw() } }, el('img', { src: t.src, loading: 'lazy' }), el('span', null, t.name)))) }; draw();
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), NX.page([el('h2', { class: 'gold', style: { textAlign: 'center', letterSpacing: '3px', marginTop: '20px' } }, 'CREATE YOUR PLAYER'), el('p', { class: 'mut', style: { textAlign: 'center' } }, 'Pick a name and your favourite team'), name, el('div', { style: { height: '14px' } }), grid, el('div', { style: { height: '16px' } }),
      el('button', { class: 'btn gold block cta', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: team, team }); NX.UI.seenIntro = 1; NX.saveUI(); NX.go('home', null, { root: 1 }) }) }, 'Let\'s go')]));
  };

  NX.afterAuth = async () => { await NX.refreshProfile(); if (!NX.UI.seenIntro) NX.go('onboard', null, { root: 1 }); else NX.go('home', null, { root: 1 }) };

  /* ---------------- home ---------------- */
  const MODES = [
    { id: 'online', name: 'ONLINE', ic: 'multiplayer', bg: 'stadium', tag: 'live', fn: () => NX.flow.quick() },
    { id: 'bot', name: 'VS BOT', ic: 'game_controller', bg: 'ice', tag: 'AI', fn: () => NX.flow.botSetup() },
    { id: 'tour', name: 'TOURNAMENT', ic: 'tournament', bg: 'lava', tag: 'Cup', fn: () => NX.go('tournaments') },
    { id: 'room', name: 'PRIVATE ROOM', ic: 'lobby', bg: 'forest', tag: 'Friends', fn: () => NX.go('lobby') },
    { id: 'local', name: '2 PLAYERS', ic: 'friends', bg: 'street', tag: 'Local', fn: () => NX.flow.local() }
  ];
  const ONLINE_ONLY = ['online', 'tour', 'room'];
  const modeCard = (m, on) => { const off = ONLINE_ONLY.includes(m.id) && !NX.online(), b = el('button', { class: 'mode', onclick: off ? NX.needOnline : m.fn }, el('div', { class: 'bg', style: { backgroundImage: 'url(assets/fields/t_' + m.bg + '.webp)' } }), el('b', null, m.name), NX.ico(m.ic, 'ic'), el('div', { class: 'tag ' + (m.tag === 'live' && !off ? 'live' : '') }, off ? 'Offline' : m.tag === 'live' ? (on || '…') : m.tag)); return b };
  S.home = async () => {
    // BERMUDA NXG home: top bar, logo, 3D card carousel, daily rewards, bottom bar
    const P = NX.P, ds = await B.economy.dailyStatus(), unread = await B.notifications.unread(), on = await B.presence.onlineCount(), online = NX.online();
    const coinsV = el('b', null, fmt(P.coins)), gemsV = el('b', null, fmt(P.gems));
    const goShop = () => NX.go('shop', { tab: B.features && B.features.billing ? 'packs' : 'chests' }, { root: 1 });
    const pill = (img, val, fn) => el('div', { class: 'pl3' }, el('img', { src: img, alt: '' }), val, el('button', { class: 'plus', onclick: fn }, svg('plus')));
    const need = fn => online ? fn : () => NX.needOnline();
    const cards = [
      { t: 'ROOMS', art: 'assets/nx2/g_shield_nx.webp', ic: 'friends', go: need(() => NX.go('lobby')), dim: !online },
      { t: 'FRIENDS', art: 'assets/nx2/c_friends.webp', ic: 'friends', go: need(() => NX.go('friends')), dim: !online },
      { t: 'TOURNAMENTS', art: 'assets/nx2/c_trophy.webp', ic: 'trophy', go: need(() => NX.go('tournaments')), dim: !online },
      { t: online ? 'PLAY ONLINE' : 'PLAY', art: 'assets/nx2/c_ball.webp', ic: 'play', main: true, go: () => online ? NX.flow.quick() : NX.flow.botSetup() },
      { t: 'RANKINGS', art: 'assets/nx2/c_podium.webp', ic: 'podium', go: () => NX.go('league') },
      { t: 'MY DISCS', art: 'assets/nx2/c_discs.webp', ic: 'coins', go: () => NX.go('teams') },
      { t: 'VS BOT', art: 'assets/nx2/g_bolt.webp', ic: 'bolt', go: () => NX.flow.botSetup() }];
    let cur = 3; const cs = el('div', { class: 'cs' });
    const render = () => [...cs.children].forEach((c, i) => { const d = i - cur, ad = Math.abs(d); c.classList.toggle('on', d === 0); c.style.zIndex = 20 - ad; c.style.opacity = ad > 2 ? 0 : 1 - ad * .1; c.style.pointerEvents = ad > 2 ? 'none' : 'auto';
      c.style.transform = 'translateX(' + (d * 84) + '%) translateZ(' + (-ad * 60) + 'px) rotateY(' + (-d * 30) + 'deg) scale(' + (d === 0 ? 1.1 : 1 - ad * .07) + ')' });
    cards.forEach((c, i) => cs.append(el('div', { class: 'cc' + (c.main ? ' main' : '') + (c.dim ? ' dim' : ''), onclick: () => { if (i === cur) c.go(); else { cur = i; render() } } },
      c.main ? el('img', { class: 'crw', src: 'assets/nx2/i_crown.webp', alt: '' }) : null, el('div', { class: 'art' }, el('img', { src: c.art, alt: '', draggable: 'false' })), el('b', { class: 'ct' }, c.t), el('i', { class: 'cb' }, el('img', { src: 'assets/nx2/g_' + c.ic + '.webp', alt: '' })))));
    let sx = null; cs.addEventListener('pointerdown', e => { sx = e.clientX }); cs.addEventListener('pointerup', e => { if (sx == null) return; const dx = e.clientX - sx; sx = null; if (Math.abs(dx) > 36) { cur = Math.max(0, Math.min(cards.length - 1, cur + (dx < 0 ? 1 : -1))); render() } }); cs.addEventListener('pointercancel', () => { sx = null });
    const arrow = (dir, ic) => el('button', { class: 'ar ' + dir, onclick: () => { cur = Math.max(0, Math.min(cards.length - 1, cur + (dir === 'l' ? -1 : 1))); render() } }, el('img', { src: 'assets/nx2/g_' + ic + '.webp', alt: '' }));
    const root = el('div', { class: 'scr home' }, NX.page([
      el('div', { class: 'tb1' }, el('div', { class: 'me', onclick: () => NX.go('profile', null, { root: 1 }) }, NX.avatar(P, 'sm', true), el('div', { class: 'mt' }, el('div', { class: 'nm' }, P.name), el('div', { class: 'xpl' }, 'Lv. ' + P.level), el('div', { class: 'bar' }, el('i', { style: { width: Math.min(100, P.xp / P.xpNeed * 100) + '%' } })))),
        el('button', { class: 'rb2', onclick: () => NX.go('notifications') }, el('img', { src: 'assets/nx2/i_bell.webp', alt: '' }), unread ? el('em', null, unread > 9 ? '9+' : unread) : null), el('button', { class: 'rb2', onclick: () => NX.go('settings') }, el('img', { src: 'assets/nx2/i_gear.webp', alt: '' }))),
      el('div', { class: 'tb2' }, pill('assets/nx3/coin.webp', coinsV, goShop), pill('assets/nx3/gem.webp', gemsV, goShop)),
      el('div', { class: 'logo3' }, el('img', { src: 'assets/nx2/logo.webp', alt: 'BERMUDA NXG' }), el('small', null, on ? 'BERMUDA NXG · ' + fmt(on) + ' ONLINE' : 'BERMUDA NXG')),
      el('div', { class: 'stage3' }, cs, arrow('l', 'left'), arrow('r', 'right'), el('div', { class: 'ped' })),
      el('div', { class: 'bot3' }, el('div', { class: 'daily', onclick: () => NX.go('daily') }, el('img', { src: 'assets/nx2/i_gift.webp', alt: '' }), el('div', { class: 'dt' }, el('b', null, 'DAILY'), el('b', null, 'REWARDS'), el('small', { class: ds.claimedToday ? 'done' : '' }, ds.claimedToday ? 'Come back tomorrow' : 'Claim now!')), el('i', { class: 'go' }, svg('chev'))),
        el('button', { class: 'ballbtn', onclick: () => NX.flow.botSetup() }, el('img', { src: 'assets/nx2/g_ball.webp', alt: '' }), el('small', null, 'PRACTICE')))
    ], true), NX.navbar('home')); render();
    NX.live.home = async () => { const p = await B.profile.get(); NX.P = p; coinsV.textContent = fmt(p.coins); gemsV.textContent = fmt(p.gems) };
    return root;
  };

  /* ---------------- wallet (balances, daily reward, quests: all real data) ---------------- */
  S.wallet = async () => {
    const P = NX.P; let ds = await B.economy.dailyStatus(), qs = await B.economy.quests(); const box = el('div');
    const draw = () => { box.replaceChildren(
      el('div', { class: 'wgrid' }, el('div', { class: 'card wc' }, el('img', { src: 'assets/nx3/coin.webp', alt: '' }), el('small', null, 'COINS'), el('b', null, fmt(NX.P.coins))), el('div', { class: 'card wc' }, el('img', { src: 'assets/nx3/gem.webp', alt: '' }), el('small', null, 'GEMS'), el('b', null, fmt(NX.P.gems)))),
      el('div', { class: 'sec' }, 'Daily reward'), el('div', { class: 'card pad row', style: { gap: '12px' } }, el('img', { src: 'assets/nx2/i_gift.webp', alt: '', style: { width: '64px' } }), el('div', { style: { flex: 1 } }, el('b', null, ds.claimedToday ? 'Claimed today' : 'Reward ready'), el('div', { class: 'mut', style: { fontSize: '12px' } }, 'Streak: day ' + Math.max(0, ds.day))),
        el('button', { class: 'btn gold sm', disabled: ds.claimedToday, onclick: e => NX.busy(e.currentTarget, async () => { const r = await B.economy.claimDaily(); ds = r.status; NX.P = await B.profile.get(); NX.toast('Reward claimed', 'ok'); draw() }) }, ds.claimedToday ? 'Done' : 'Claim')),
      el('div', { class: 'sec' }, 'Quests'), ...qs.map(q => el('div', { class: 'card pad row', style: { gap: '10px', marginBottom: '10px' } }, el('div', { style: { flex: 1 } }, el('b', null, q.text), el('div', { class: 'bar', style: { marginTop: '8px' } }, el('i', { style: { width: Math.min(100, q.have / q.need * 100) + '%' } })), el('small', { class: 'mut' }, q.have + '/' + q.need + ' · ' + (q.coins || 0) + ' coins' + (q.gems ? ' + ' + q.gems + ' gems' : ''))),
        el('button', { class: 'btn gold sm', disabled: q.claimed || q.have < q.need, onclick: e => NX.busy(e.currentTarget, async () => { await B.economy.claimQuest(q.id); NX.P = await B.profile.get(); qs = await B.economy.quests(); draw() }) }, q.claimed ? 'Done' : 'Claim'))),
      el('button', { class: 'btn ghost block', style: { marginTop: '6px' }, onclick: () => NX.go('shop', { tab: 'chests' }, { root: 1 }) }, 'Open chests in the shop')) };
    draw(); return el('div', { class: 'scr' }, NX.topbar('Wallet', el('div', { class: 'sp' })), NX.page([box], true), NX.navbar('wallet')) };

  /* ---------------- games hub ---------------- */
  S.games = async () => {
    const P = NX.P, rows = [
      { m: MODES[0], t: 'Online Ranked', d: NX.online() ? 'Climb the leagues vs real players' : 'Needs the online server', cta: 'Play' }, { m: MODES[1], t: 'Practice vs Bot', d: 'Three difficulty levels', cta: 'Play' },
      { m: MODES[2], t: 'Tournaments', d: 'Win cups, prizes and gems', cta: 'Enter' }, { m: MODES[3], t: 'Private Room', d: 'Create or join with a code', cta: 'Open' }, { m: MODES[4], t: 'Local 2 Players', d: 'Pass & play on one phone', cta: 'Play' }];
    const card = r => el('div', { class: 'card', style: { display: 'flex', alignItems: 'center', gap: '12px', padding: '10px', marginBottom: '10px', opacity: ONLINE_ONLY.includes(r.m.id) && !NX.online() ? .55 : 1 }, onclick: ONLINE_ONLY.includes(r.m.id) && !NX.online() ? NX.needOnline : r.m.fn },
      el('div', { style: { width: '84px', height: '84px', borderRadius: '16px', backgroundImage: 'url(assets/fields/t_' + r.m.bg + '.webp)', backgroundSize: 'cover', display: 'grid', placeItems: 'center', border: '1px solid var(--line2)', flex: 'none' } }, NX.ico(r.m.ic, '', 0)), el('div', { style: { flex: 1, minWidth: 0 } }, el('b', { style: { fontSize: '16px' } }, r.t), el('div', { class: 'mut', style: { fontSize: '12.5px', marginTop: '2px' } }, r.d)), el('button', { class: 'btn gold sm' }, r.cta));
    card.toString; const imgs = rows.map(card); imgs.forEach((n, i) => { const im = n.querySelector('img'); if (im) { im.style.width = '64px'; im.style.height = '64px'; im.style.objectFit = 'contain' } });
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), el('div', { class: 'top' }, el('div', { class: 'sp' }), el('h2', { class: 'gold' }, 'Games'), el('button', { class: 'ibtn', onclick: () => NX.go('settings') }, svg('gear'))), NX.page([
      ...imgs, el('div', { class: 'sec' }, 'Customize'), el('div', { class: 'two', style: { gridTemplateColumns: '1fr 1fr' } },
        el('button', { class: 'card pad', style: { textAlign: 'center' }, onclick: () => NX.go('fieldball') }, NX.ico('field_and_ball_select', '', 0), el('b', null, 'Pitch & Ball')), el('button', { class: 'card pad', style: { textAlign: 'center' }, onclick: () => NX.go('teams') }, NX.ico('team_select'), el('b', null, 'Team & Formation')))], true), NX.navbar('games'));
  };

  /* ---------------- shop ---------------- */
  S.shop = async (p) => {
    let tab = (p && p.tab) || 'balls'; const list = el('div'), tabs = el('div', { class: 'tabs' }), head = el('div', { class: 'row', style: { gap: '12px', margin: '6px 0 12px' } });
    const T = [['balls', 'Balls'], ['fields', 'Pitches'], ['chests', 'Chests']].concat(B.features && B.features.billing ? [['packs', 'Coins']] : []); if (!T.some(t => t[0] === tab)) tab = 'balls';
    const draw = async () => {
      const items = await B.shop.items(); NX.P = await B.profile.get(); head.replaceChildren(el('div', { class: 'card pad', style: { flex: 1 } }, NX.cur(NX.P.coins)), el('div', { class: 'card pad', style: { flex: 1 } }, NX.cur(NX.P.gems, 'gems')));
      tabs.replaceChildren(...T.map(([k, l]) => el('button', { class: tab === k ? 'on' : '', onclick: () => { tab = k; draw() } }, l)));
      const type = { balls: 'ball', fields: 'field', chests: 'chest', packs: 'pack' }[tab], sel = items.filter(i => i.type === type);
      list.replaceChildren(el('div', { class: 'sgrid' }, sel.map(i => {
        const act = i.type === 'ball' || i.type === 'field' ? (i.owned ? (i.equipped ? el('div', { class: 'eq' }, svg('check'), 'Equipped') : el('button', { class: 'btn dark', onclick: e => NX.busy(e.currentTarget, async () => { await B.shop.equip(i.type, i.key); draw() }) }, 'Equip')) : buyBtn(i)) : buyBtn(i);
        return el('div', { class: 'card sitem' }, el('div', { class: 'im' }, el('img', { src: i.img, class: i.type === 'field' ? 'fld' : '' })), el('b', null, i.name), el('small', null, i.sub), act)
      })));
    };
    const buyBtn = i => el('button', { class: 'btn gold', onclick: e => NX.busy(e.currentTarget, async () => { const r = await B.shop.buy(i.id); if (r.rewards) NX.rewards('Chest opened', r.rewards.map(rw => ({ img: rw.type === 'coins' ? 'assets/nx3/coin.webp' : rw.type === 'gems' ? 'assets/nx3/gem.webp' : rw.type === 'ball' ? 'assets/balls/s' + rw.key + '.webp' : 'assets/fields/t_' + rw.key + '.webp', label: rw.type === 'coins' || rw.type === 'gems' ? '+' + fmt(rw.amount) : rw.name })), draw); else { NX.toast('Purchased!', 'ok'); draw() } }) },
      i.cur === 'money' ? i.price : [el('img', { src: i.cur === 'gems' ? 'assets/nx3/gem.webp' : 'assets/nx3/coin.webp', style: { width: '16px' } }), fmt(i.price)]);
    draw(); NX.live.shop = () => { };
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), el('div', { class: 'top' }, el('div', { class: 'sp' }), el('h2', { class: 'gold' }, 'Shop'), el('div', { class: 'sp' })), NX.page([head, tabs, el('div', { style: { height: '12px' } }), list], true), NX.navbar('shop'));
  };

  /* ---------------- profile ---------------- */
  const BADGES = [['First win', '🏆', p => p.stats.wins >= 1], ['10 wins', '🥉', p => p.stats.wins >= 10], ['50 wins', '🥈', p => p.stats.wins >= 50], ['100 goals', '⚽', p => p.stats.goals >= 100], ['3 streak', '🔥', p => p.stats.best >= 3], ['Level 10', '⭐', p => p.level >= 10], ['Gold league', '👑', p => p.trophies >= 1000], ['Collector', '💎', p => p.owned.balls.length >= 6]];
  S.profile = async () => {
    const P = NX.P, st = P.stats, wr = st.played ? Math.round(st.wins / st.played * 100) : 0;
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), el('div', { class: 'top' }, el('div', { class: 'sp' }), el('h2', { class: 'gold' }, 'Profile'), el('button', { class: 'ibtn', onclick: () => NX.go('settings') }, svg('gear'))), NX.page([
      el('div', { class: 'phead' }, el('div', { class: 'pframe' }, NX.avatar(P, 'lg', true)), el('h3', null, P.name), el('div', { class: 'row' }, el('span', { class: 'chip', style: { color: P.league.color } }, svg('trophy'), P.league.label), el('span', { class: 'chip' }, 'ID: NX-' + String(P.id).slice(-6).toUpperCase())),
        el('div', { style: { width: '80%' } }, el('div', { class: 'xpl', style: { justifyContent: 'center' } }, el('em', null, 'XP'), fmt(P.xp) + ' / ' + fmt(P.xpNeed)), el('div', { class: 'bar' }, el('i', { style: { width: P.xp / P.xpNeed * 100 + '%' } }))),
        el('button', { class: 'btn ghost sm', onclick: () => NX.go('editprofile') }, svg('edit'), 'Edit profile')),
      el('div', { class: 'lg4' }, [['Played', st.played], ['Wins', st.wins], ['Win %', wr + '%'], ['Goals', st.goals]].map(([l, v]) => el('div', { class: 'card stat' }, el('b', null, v), el('small', null, l)))),
      el('div', { class: 'lg4', style: { marginTop: '8px' } }, [['Streak', st.streak], ['Best', st.best], ['Trophies', fmt(P.trophies)], ['Rank', P.rank ? '#' + P.rank : '—']].map(([l, v]) => el('div', { class: 'card stat' }, el('b', null, v), el('small', null, l)))),
      el('div', { class: 'sec' }, 'Achievements'), el('div', { class: 'lg4' }, BADGES.map(([n, e, f]) => el('div', { class: 'badge ' + (f(P) ? '' : 'lock') }, el('i', null, e), n))),
      el('div', { class: 'sec' }, 'Shortcuts'), el('div', { class: 'two', style: { gridTemplateColumns: '1fr 1fr' } }, el('button', { class: 'btn dark', onclick: () => NX.go('friends') }, svg('users'), 'Friends'), el('button', { class: 'btn dark', onclick: () => NX.go('quests') }, svg('check'), 'Quests'), el('button', { class: 'btn dark', onclick: () => NX.go('teams') }, svg('star'), 'My team'), el('button', { class: 'btn dark', onclick: () => NX.go('fieldball') }, svg('games'), 'Pitch & ball'))], true), NX.navbar('profile'));
  };
  S.editprofile = async () => {
    const P = NX.P; let av = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16 }), grid = el('div', { class: 'tgrid' });
    const draw = () => grid.replaceChildren(...G.TEAMS.filter(t => ['club', 'nat', 'car', 'lux', 'spt'].includes(t.cat)).slice(0, 80).map(t => el('button', { class: 'tc ' + (av === t.id ? 'sel' : ''), onclick: () => { av = t.id; draw() } }, el('img', { src: t.src, loading: 'lazy' })))); draw();
    return el('div', { class: 'scr' }, NX.topbar('Edit profile'), NX.page([el('div', { class: 'mut', style: { margin: '4px 2px 6px' } }, 'Display name'), name, el('div', { class: 'sec' }, 'Avatar'), grid, el('div', { style: { height: '14px' } }), el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: av }); NX.toast('Saved', 'ok'); NX.back() }) }, 'Save')]));
  };

  /* ---------------- settings ---------------- */
  S.settings = async () => {
    const U = NX.UI, tg = (key, cb) => { const t = el('button', { class: 'tgl ' + (U[key] ? 'on' : ''), onclick: () => { U[key] = U[key] ? 0 : 1; t.classList.toggle('on', !!U[key]); NX.saveUI(); cb && cb() } }); return t };
    const seg = (key, opts, cb) => { const w = el('div', { class: 'seg' }); const d = () => w.replaceChildren(...opts.map(([v, l]) => el('button', { class: U[key] === v ? 'on' : '', onclick: () => { U[key] = v; NX.saveUI(); d(); cb && cb() } }, l))); d(); return w };
    const row = (ic, label, ctl) => el('div', { class: 'set' }, svg(ic), el('span', { style: { flex: 1 } }, label), ctl);
    const P = NX.P, sess = await B.auth.session();
    return el('div', { class: 'scr' }, NX.topbar('Settings'), NX.page([
      row('spk', 'Sound effects', tg('snd')), row('play', 'Music', tg('mus')), row('bell', 'Vibration', tg('vib')),
      row('mic', 'Microphone (voice chat)', tg('mic', async () => { try { await B.voice.setMic(!!U.mic) } catch (e) { U.mic = 0; NX.saveUI(); NX.err(e); NX.render() } })), row('spk', 'Speaker (voice chat)', tg('spk', () => B.voice.setSpeaker(!!U.spk))),
      row('games', 'Graphics', seg('gfx', [['high', 'High'], ['low', 'Low']], () => { G.setQuality && G.setQuality(U.gfx) })),
      el('div', { class: 'sec' }, 'Account'), el('div', { class: 'card pad' }, el('div', { class: 'row' }, NX.avatar(P, 'sm'), el('div', null, el('b', null, P.name), el('div', { class: 'mut', style: { fontSize: '12px' } }, sess && sess.user.guest ? 'Guest account' : (sess && sess.user.email) || ''))), el('div', { style: { height: '10px' } }), sess && sess.user.guest && B.features && B.features.email ? el('button', { class: 'btn gold block sm', onclick: () => NX.confirm('Link account', 'Guest progress is stored on this device only. Sign in with an email to keep it safe.', 'Sign out & register', async () => { await B.auth.signOut(); NX.go('auth', null, { root: 1 }) }) }, 'Secure my account') : null),
      el('div', { style: { height: '12px' } }), el('button', { class: 'btn dark block', onclick: () => NX.confirm('Sign out', 'Do you want to sign out?', 'Sign out', async () => { await B.auth.signOut(); NX.go('auth', null, { root: 1 }) }) }, svg('out'), 'Sign out'),
      el('div', { style: { height: '10px' } }), el('button', { class: 'btn red block sm', onclick: () => NX.confirm('Delete account', 'This permanently deletes your progress. This cannot be undone.', 'Delete', async () => { await B.auth.deleteAccount(); NX.go('auth', null, { root: 1 }) }, true) }, 'Delete account'),
      el('p', { class: 'mut', style: { textAlign: 'center', fontSize: '12px', marginTop: '16px' } }, 'BERMUDA NXG v' + CFG.APP_VERSION + ' · ' + (NX.online() ? 'Online' : 'Offline mode'))]));
  };
})();
