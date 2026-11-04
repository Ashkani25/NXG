/* NX v9: unified UI on the new asset pack. Loaded last: overrides shared widgets and the screens that changed. */
(() => {
  'use strict';
  const NX = window.NX, { el, svg, fmt, B, G, CFG } = NX, S = NX.screens, A = n => 'assets/nx3/' + n + '.webp';
  const sfx = n => { try { G.sfx(n) } catch (e) { } };

  /* ---------- shared widgets ---------- */
  NX.navbar = active => {
    const t = (id, img, label) => el('button', { class: active === id ? 'on' : '', 'aria-label': label, onclick: () => NX.go(id, null, { root: 1 }) }, el('img', { src: A(img), alt: '', draggable: 'false' }));
    return el('div', { class: 'navbar' }, t('home', 't_home', 'Home'), t('profile', 't_user', 'Profile'), t('wallet', 't_wallet', 'Wallet'), t('shop', 't_cart', 'Shop'), t('league', 't_trophy', 'Leagues'));
  };
  NX.topbar = (title, right, onBack) => el('div', { class: 'top' }, el('button', { class: 'ibtn bk', 'aria-label': 'Back', onclick: onBack || NX.back }, el('img', { src: A('a_left'), alt: '' })), el('h2', { class: 'gold' }, title), right || el('div', { class: 'sp' }));
  NX.cur = (v, type) => el('span', { class: 'cur' }, el('img', { src: A(type === 'gems' ? 'gem' : 'coin'), alt: '' }), NX.fmt(v));
  const gearBtn = () => el('button', { class: 'ibtn', 'aria-label': 'Settings', onclick: () => NX.go('settings') }, el('img', { src: A('gear'), alt: '' }));

  /* pop-out feedback on every tap (delegated, no per-element cost) */
  const POP = '.btn,.card,.tc,.lrow,.ibtn,.rb2,.dly,.vsb,.fc,.bc,.pt,.set,.tabs button,.seg button,.fm button,.navbar button,.mode,.stat,.badge,.cu .plus,.cc';
  document.addEventListener('pointerup', e => { const t = e.target.closest && e.target.closest(POP); if (!t || t.classList.contains('dis')) return; t.classList.remove('popout'); void t.offsetWidth; t.classList.add('popout') }, true);
  document.addEventListener('animationend', e => { if (e.animationName === 'popout') e.target.classList.remove('popout') }, true);

  /* ---------- vertical page-flip deck ---------- */
  // o: {items, index, card(item,i)->node, onTap(item,i), onChange(i)}. Windowed (max 7 nodes), transform-only, rAF only while moving.
  NX.deck = o => {
    const items = o.items, N = items.length, nodes = new Map(), STEP = 118; let pos = Math.max(0, Math.min(N - 1, o.index || 0)), tgt = Math.round(pos), vel = 0, raf = 0, lastT = 0, st = null, moved = false, ctr = -1;
    const cnt = el('div', { class: 'dkc' }), root = el('div', { class: 'dk' });
    const arrow = (c, d) => el('button', { class: 'dka ' + c, 'aria-label': c === 'u' ? 'Previous' : 'Next', onclick: () => go(Math.round(tgt) + d) }, el('img', { src: A('a_left'), alt: '' }));
    root.append(arrow('u', -1), arrow('d', 1), cnt);
    const place = (n, d) => { const ad = Math.abs(d); let y, z, rx, sc, op;
      if (d < 0) { y = d * 62; z = -ad * 40; rx = ad * 26; sc = 1 - ad * .04; op = Math.max(0, 1 - ad * .75) } // flipped cards peel up and away
      else { y = d * 40; z = -d * 55; rx = -d * 4; sc = 1 - d * .06; op = Math.max(0, 1 - d * .3) }
      n.style.transform = 'translate3d(-50%,-50%,0) translate3d(0,' + y.toFixed(1) + 'px,' + z.toFixed(1) + 'px) rotateX(' + rx.toFixed(1) + 'deg) scale(' + sc.toFixed(3) + ')'; n.style.opacity = op.toFixed(2); n.style.zIndex = 100 - Math.round(ad * 10) + (d < 0 ? -50 : 0); n.style.pointerEvents = ad < .6 ? 'auto' : 'none' };
    const layout = () => { const c = Math.round(pos), lo = Math.max(0, Math.floor(pos) - 2), hi = Math.min(N - 1, Math.ceil(pos) + 3);
      for (const [i, n] of nodes) if (i < lo || i > hi) { n.remove(); nodes.delete(i) }
      for (let i = lo; i <= hi; i++) { let n = nodes.get(i); if (!n) { n = el('div', { class: 'dcard' + (o.cls ? ' ' + o.cls : ''), 'data-i': i }, o.card(items[i], i)); nodes.set(i, n); root.append(n) } place(n, i - pos) }
      if (c !== ctr) { ctr = c; for (const [i, n] of nodes) n.classList.toggle('ctr', i === c); cnt.textContent = (c + 1) + ' / ' + N; o.onChange && o.onChange(c, items[c]) } };
    const tick = t => { const dt = Math.min(.035, (t - lastT) / 1000 || .016); lastT = t; vel += ((tgt - pos) * 300 - vel * 23) * dt; pos += vel * dt; layout();
      if (Math.abs(tgt - pos) > .0015 || Math.abs(vel) > .004) raf = requestAnimationFrame(tick); else { pos = tgt; vel = 0; raf = 0; layout() } };
    const kick = () => { if (!raf) { lastT = performance.now(); raf = requestAnimationFrame(tick) } };
    const go = i => { i = Math.max(0, Math.min(N - 1, i)); if (i !== tgt) sfx('ui'); tgt = i; kick() };
    root.addEventListener('pointerdown', e => { if (e.target.closest('.dka') || e.target.closest('.act')) return; st = { y: e.clientY, p: pos, t: performance.now(), id: e.pointerId }; moved = false; vel = 0; if (raf) { cancelAnimationFrame(raf); raf = 0 } });
    root.addEventListener('pointermove', e => { if (!st) return; const dy = e.clientY - st.y; if (!moved && Math.abs(dy) > 7) { moved = true; try { root.setPointerCapture(st.id) } catch (x) { } }
      if (moved) { let p = st.p - dy / STEP; if (p < 0) p *= .35; if (p > N - 1) p = N - 1 + (p - N + 1) * .35; pos = p; layout() } });
    const end = e => { if (!st) return; const dy = e.clientY - st.y, dtm = Math.max(1, performance.now() - st.t), v = -dy / dtm; // px/ms, + = next
      if (moved) { tgt = Math.max(0, Math.min(N - 1, Math.round(pos + Math.max(-3, Math.min(3, v * 1.1))))); if (tgt !== ctr) sfx('ui'); kick() } st = null };
    root.addEventListener('pointerup', end); root.addEventListener('pointercancel', () => { if (st && moved) { tgt = Math.round(pos); kick() } st = null });
    root.addEventListener('click', e => { if (moved) { moved = false; return } const c = e.target.closest('.dcard'); if (!c || e.target.closest('.act') || e.target.closest('.dka')) return; const i = +c.dataset.i; if (i === Math.round(tgt)) o.onTap && o.onTap(items[i], i); else go(i) });
    root.addEventListener('wheel', e => { e.preventDefault(); go(Math.round(tgt) + (e.deltaY > 0 ? 1 : -1)) }, { passive: false });
    layout();
    return { el: root, go, index: () => Math.round(tgt), refresh: () => { for (const [i, n] of nodes) n.replaceChildren(o.card(items[i], i)) } };
  };

  /* team picker (category tabs + deck). get/set current team id; set may be async */
  const teamPicker = (get, set, opt) => {
    opt = opt || {}; const cats = G.CATS.filter(c => !opt.cats || opt.cats.includes(c[0])); const k0 = G.CATS[G.catOf(get())][0]; let cat = Math.max(0, cats.findIndex(c => c[0] === k0)), deck;
    const tabs = el('div', { class: 'tabs' }), wrap = el('div', { class: 'dkw' });
    const build = () => {
      tabs.replaceChildren(...cats.map((c, i) => el('button', { class: cat === i ? 'on' : '', onclick: () => { cat = i; build() } }, c[1])));
      const items = G.TEAMS.filter(t => t.cat === cats[cat][0]).slice(0, opt.max || 999); const idx = Math.max(0, items.findIndex(t => t.id === get()));
      deck = NX.deck({ items, index: idx, cls: 'tcard', card: t => [el('img', { src: t.src, alt: '', draggable: 'false' }), el('b', null, t.name), el('small', { class: get() === t.id ? 'eqd' : '' }, get() === t.id ? '✓ SELECTED' : 'TAP TO SELECT')],
        onTap: async t => { await set(t); deck.refresh() }, onChange: (i, t) => { } });
      wrap.replaceChildren(deck.el); };
    build(); return [tabs, el('div', { style: { height: '8px' } }), wrap, el('p', { class: 'dkh' }, 'SWIPE UP / DOWN')];
  };

  /* ---------- HOME ---------- */
  S.home = async () => {
    const P = NX.P, ds = await B.economy.dailyStatus(), unread = await B.notifications.unread(), on = await B.presence.onlineCount(), online = NX.online();
    const coinsV = el('b', null, fmt(P.coins)), gemsV = el('b', null, fmt(P.gems));
    const goShop = () => NX.go('shop', { tab: B.features && B.features.billing ? 'packs' : 'chests' }, { root: 1 });
    const cu = (img, val, fn) => el('div', { class: 'cu' }, el('img', { src: A(img), alt: '' }), val, el('button', { class: 'plus', 'aria-label': 'Add', onclick: fn }, '+'));
    const need = fn => online ? fn : () => NX.needOnline();
    const cards = [
      { t: 'TOURNAMENTS', art: 'k_trophy', go: need(() => NX.go('tournaments')), dim: !online },
      { t: 'RANKINGS', art: 'k_podium', go: () => NX.go('league') },
      { t: online ? 'PLAY ONLINE' : 'PLAY', art: 'k_ball', main: true, go: () => online ? NX.flow.quick() : NX.flow.botSetup() },
      { t: 'MY DISCS', art: 'k_nx', go: () => NX.go('teams') },
      { t: 'ROOMS', art: 'k_team', go: need(() => NX.go('lobby')), dim: !online }];
    let cur = 2; const cs = el('div', { class: 'cs' });
    const render = () => [...cs.children].forEach((c, i) => { const d = i - cur, ad = Math.abs(d); c.classList.toggle('main', d === 0); c.style.zIndex = 20 - ad; c.style.opacity = ad > 2 ? 0 : 1 - ad * .12; c.style.pointerEvents = ad > 2 ? 'none' : 'auto';
      c.style.transform = 'translateX(' + (d * 74) + '%) translateZ(' + (-ad * 70) + 'px) rotateY(' + (-d * 30) + 'deg) scale(' + (d === 0 ? 1.12 : 1 - ad * .08) + ')' });
    cards.forEach((c, i) => cs.append(el('div', { class: 'cc' + (c.dim ? ' dim' : ''), onclick: () => { if (i === cur) c.go(); else { cur = i; render(); sfx('ui') } } }, el('img', { class: 'face', src: A(c.art), alt: '', draggable: 'false' }), el('b', { class: 'ct' }, c.t))));
    let sx = null; cs.addEventListener('pointerdown', e => { sx = e.clientX }); cs.addEventListener('pointerup', e => { if (sx == null) return; const dx = e.clientX - sx; sx = null; if (Math.abs(dx) > 34) { cur = Math.max(0, Math.min(cards.length - 1, cur + (dx < 0 ? 1 : -1))); render(); sfx('ui') } }); cs.addEventListener('pointercancel', () => { sx = null });
    const arrow = (dir, ic) => el('button', { class: 'ar ' + dir, 'aria-label': dir === 'l' ? 'Previous' : 'Next', onclick: () => { cur = Math.max(0, Math.min(cards.length - 1, cur + (dir === 'l' ? -1 : 1))); render() } }, el('img', { src: A(ic), alt: '' }));
    const dayNo = ds.claimedToday ? ((ds.day - 1) % 7) + 1 : (ds.day % 7) + 1;
    const root = el('div', { class: 'scr home' }, NX.page([
      el('div', { class: 'hb' }, el('div', { class: 'me', onclick: () => NX.go('profile', null, { root: 1 }) }, el('div', { class: 'avw' }, el('img', { class: 'crw', src: A('crown'), alt: '' }), NX.avatar(P, 'sm')),
        el('div', { class: 'mt' }, el('small', null, 'NX GAME'), el('b', { class: 'nm' }, P.name), el('span', { class: 'xpl' }, 'Lv. ' + P.level), el('div', { class: 'bar' }, el('i', { style: { width: Math.min(100, P.xp / P.xpNeed * 100) + '%' } })))),
        el('div', { class: 'cus' }, cu('coin', coinsV, goShop), cu('gem', gemsV, goShop)),
        el('button', { class: 'rb2', 'aria-label': 'Notifications', onclick: () => NX.go('notifications') }, el('img', { src: A('bell'), alt: '' }), unread ? el('em', null, unread > 9 ? '9+' : unread) : null),
        el('button', { class: 'rb2', 'aria-label': 'Settings', onclick: () => NX.go('settings') }, el('img', { src: A('gear'), alt: '' }))),
      el('div', { class: 'logo3' }, el('img', { src: A('logo'), alt: 'BERMUDA NXG' }), el('small', null, on ? 'BERMUDA NXG · ' + fmt(on) + ' ONLINE' : 'BERMUDA NXG')),
      el('div', { class: 'stage3' }, cs, arrow('l', 'a_left'), arrow('r', 'a_right'), el('div', { class: 'ped' })),
      el('div', { class: 'bot3' }, el('div', { class: 'dly', onclick: () => NX.go('daily') }, el('img', { class: 'gf', src: A('gift'), alt: '' }),
        el('div', { class: 'dt' }, el('b', null, 'DAILY'), el('b', null, 'REWARDS'), el('small', { class: ds.claimedToday ? 'done' : '' }, ds.claimedToday ? 'Come back tomorrow' : 'Claim now!'), el('div', { class: 'pg' }, el('div', { class: 'bar' }, el('i', { style: { width: dayNo / 7 * 100 + '%' } })), 'Day ' + dayNo + ' / 7')),
        el('img', { class: 'go', src: A('go'), alt: '' })),
        el('button', { class: 'vsb', onclick: () => NX.flow.botSetup() }, el('img', { src: A('t_play'), alt: '' }), el('small', null, 'VS BOT')))
    ], true), NX.navbar('home')); render();
    NX.live.home = async () => { const p = await B.profile.get(); NX.P = p; coinsV.textContent = fmt(p.coins); gemsV.textContent = fmt(p.gems) };
    return root;
  };

  /* ---------- PROFILE ---------- */
  const BADGES = [['First win', '🏆', p => p.stats.wins >= 1], ['10 wins', '🥉', p => p.stats.wins >= 10], ['50 wins', '🥈', p => p.stats.wins >= 50], ['100 goals', '⚽', p => p.stats.goals >= 100], ['3 streak', '🔥', p => p.stats.best >= 3], ['Level 10', '⭐', p => p.level >= 10], ['Gold league', '👑', p => p.trophies >= 1000], ['Collector', '💎', p => p.owned.balls.length >= 6]];
  S.profile = async () => {
    const P = NX.P, st = P.stats, wr = st.played ? Math.round(st.wins / st.played * 100) : 0, tile = (img, l, v) => el('div', { class: 'pt' }, el('img', { src: A(img), alt: '' }), el('small', null, l), el('b', null, v));
    const share = () => { const t = P.name + ' · ID NX-' + String(P.id).slice(-6).toUpperCase() + ' · BERMUDA NXG'; try { if (navigator.share) navigator.share({ text: t }); else navigator.clipboard.writeText(t).then(() => NX.toast('Copied', 'ok')) } catch (e) { } };
    return el('div', { class: 'scr' }, NX.topbar('Profile', gearBtn(), () => NX.go('home', null, { root: 1 })), NX.page([
      el('div', { class: 'pcd' }, el('div', { class: 'pav' }, el('img', { class: 'crn', src: A('crown'), alt: '' }), NX.avatar(P, 'lg')),
        el('div', { class: 'lvl' }, el('span', null, 'Level'), el('b', null, P.level)),
        el('div', { class: 'pxp' }, el('i', { style: { width: 'calc(' + Math.min(100, P.xp / P.xpNeed * 100) + '% - 6px)' } }), el('em', null, fmt(P.xp) + ' / ' + fmt(P.xpNeed))),
        el('div', { class: 'nmr' }, el('b', null, P.name), el('span', { class: 'vip', style: { color: P.league.color } }, P.league.label)),
        el('div', { class: 'ptiles' }, tile('i_sword', 'Wins', fmt(st.wins)), tile('i_cup', 'Rank', P.rank ? '#' + P.rank : '—'), tile('i_star', 'Trophies', fmt(P.trophies))),
        el('div', { class: 'pbtn' }, el('button', { class: 'btn ghost', onclick: () => NX.go('editprofile') }, svg('edit'), 'Edit Profile'), el('button', { class: 'btn ghost', onclick: share }, svg('copy'), 'Share'))),
      el('div', { class: 'lg4', style: { marginTop: '14px' } }, [['Played', st.played], ['Wins', st.wins], ['Win %', wr + '%'], ['Goals', st.goals]].map(([l, v]) => el('div', { class: 'card stat' }, el('b', null, v), el('small', null, l)))),
      el('div', { class: 'lg4', style: { marginTop: '8px' } }, [['Streak', st.streak], ['Best', st.best], ['Trophies', fmt(P.trophies)], ['Rank', P.rank ? '#' + P.rank : '—']].map(([l, v]) => el('div', { class: 'card stat' }, el('b', null, v), el('small', null, l)))),
      el('div', { class: 'sec' }, 'Achievements'), el('div', { class: 'lg4' }, BADGES.map(([n, e, f]) => el('div', { class: 'badge ' + (f(P) ? '' : 'lock') }, el('i', null, e), n))),
      el('div', { class: 'sec' }, 'Shortcuts'), el('div', { class: 'two', style: { gridTemplateColumns: '1fr 1fr' } }, el('button', { class: 'btn dark', onclick: () => NX.go('friends') }, svg('users'), 'Friends'), el('button', { class: 'btn dark', onclick: () => NX.go('quests') }, svg('check'), 'Quests'), el('button', { class: 'btn dark', onclick: () => NX.go('teams') }, svg('star'), 'My team'), el('button', { class: 'btn dark', onclick: () => NX.go('fieldball') }, svg('games'), 'Pitch & ball'))], true), NX.navbar('profile'));
  };

  /* ---------- TEAMS (deck) + formation ---------- */
  S.teams = async () => {
    const P = NX.P; let team = P.team, form = P.form || 0; const fm = el('div', { class: 'fm' });
    const drawFm = () => fm.replaceChildren(...G.FORMS.map((f, i) => { const cv = document.createElement('canvas'); cv.width = 120; cv.height = 100; const x = cv.getContext('2d'); x.fillStyle = '#0d2a4d'; x.fillRect(0, 0, 120, 100); x.strokeStyle = 'rgba(150,210,255,.7)'; x.lineWidth = 2; x.strokeRect(2, 2, 116, 96); x.beginPath(); x.moveTo(2, 2); x.lineTo(118, 2); x.stroke(); for (const [nx, ny] of G.slots(i)) { x.fillStyle = '#4aa8ff'; x.beginPath(); x.arc(14 + nx * 92, 92 - ny / .5 * 80, 8, 0, 7); x.fill(); x.strokeStyle = '#fff'; x.stroke() } return el('button', { class: form === i ? 'sel' : '', onclick: async () => { form = i; await B.profile.update({ form: i }); drawFm() } }, cv, el('b', null, f[0]), el('span', { class: 'mut' }, f[1])) })); drawFm();
    const pick = teamPicker(() => team, async t => { team = t.id; await B.profile.update({ team: t.id }); sfx('ui') });
    return el('div', { class: 'scr' }, NX.topbar('Team & formation'), NX.page([el('div', { class: 'sec', style: { marginTop: '4px' } }, 'Your team'), ...pick, el('div', { class: 'sec' }, 'Formation'), fm]));
  };

  /* ---------- onboarding + edit profile use the same deck ---------- */
  S.onboard = () => {
    const P = NX.P; let team = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16, placeholder: 'Choose your name' });
    const pick = teamPicker(() => team, t => { team = t.id }, { cats: ['club', 'nat'] });
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), NX.page([el('h2', { class: 'gold', style: { textAlign: 'center', letterSpacing: '3px', marginTop: '20px' } }, 'CREATE YOUR PLAYER'), el('p', { class: 'mut', style: { textAlign: 'center' } }, 'Pick a name and your favourite team'), name, el('div', { style: { height: '10px' } }), ...pick,
      el('button', { class: 'btn gold block cta', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: team, team }); NX.UI.seenIntro = 1; NX.saveUI(); NX.go('home', null, { root: 1 }) }) }, 'Let\'s go')]));
  };
  S.editprofile = async () => {
    const P = NX.P; let av = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16 }), pick = teamPicker(() => av, t => { av = t.id }, { cats: ['club', 'nat', 'car', 'lux', 'spt'] });
    return el('div', { class: 'scr' }, NX.topbar('Edit profile'), NX.page([el('div', { class: 'mut', style: { margin: '4px 2px 6px' } }, 'Display name'), name, el('div', { class: 'sec' }, 'Avatar'), ...pick, el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: av }); NX.toast('Saved', 'ok'); NX.back() }) }, 'Save')]));
  };

  /* ---------- SHOP (deck) ---------- */
  S.shop = async p => {
    let tab = (p && p.tab) || 'balls', keep = 0; const wrap = el('div', { class: 'dkw' }), tabs = el('div', { class: 'tabs' }), head = el('div', { class: 'row', style: { gap: '10px', margin: '6px 0 10px' } });
    const T = [['balls', 'Balls'], ['fields', 'Pitches'], ['chests', 'Chests']].concat(B.features && B.features.billing ? [['packs', 'Coins']] : []); if (!T.some(t => t[0] === tab)) tab = 'balls';
    const priceNode = i => i.cur === 'money' ? i.price : [el('img', { src: A(i.cur === 'gems' ? 'gem' : 'coin'), style: { width: '18px', height: '18px' } }), fmt(i.price)];
    const draw = async reset => {
      const items = await B.shop.items(); NX.P = await B.profile.get();
      head.replaceChildren(el('div', { class: 'card pad', style: { flex: 1 } }, NX.cur(NX.P.coins)), el('div', { class: 'card pad', style: { flex: 1 } }, NX.cur(NX.P.gems, 'gems')));
      tabs.replaceChildren(...T.map(([k, l]) => el('button', { class: tab === k ? 'on' : '', onclick: () => { tab = k; draw(true) } }, l)));
      const type = { balls: 'ball', fields: 'field', chests: 'chest', packs: 'pack' }[tab], sel = items.filter(i => i.type === type);
      if (!sel.length) { wrap.replaceChildren(el('div', { class: 'empty' }, 'Nothing here yet')); return }
      const buy = i => e => NX.busy(e.currentTarget, async () => { const r = await B.shop.buy(i.id); if (r.rewards) NX.rewards('Chest opened', r.rewards.map(rw => ({ img: rw.type === 'coins' ? A('coin') : rw.type === 'gems' ? A('gem') : rw.type === 'ball' ? 'assets/balls/s' + rw.key + '.webp' : 'assets/fields/t_' + rw.key + '.webp', label: rw.type === 'coins' || rw.type === 'gems' ? '+' + fmt(rw.amount) : rw.name })), () => draw()); else { NX.toast('Purchased!', 'ok'); draw() } });
      const act = i => (i.type === 'ball' || i.type === 'field') && i.owned ? (i.equipped ? el('div', { class: 'eq act' }, svg('check'), 'Equipped') : el('button', { class: 'btn dark act', onclick: e => NX.busy(e.currentTarget, async () => { await B.shop.equip(i.type, i.key); draw() }) }, 'Equip')) : el('button', { class: 'btn gold act', onclick: buy(i) }, priceNode(i));
      const d = NX.deck({ items: sel, index: reset ? 0 : keep, cls: type === 'field' ? 'fld' : '', onChange: c => { keep = c }, card: i => [el('img', { src: i.img, alt: '', draggable: 'false' }), el('b', null, i.name), i.sub ? el('small', null, i.sub) : null, act(i)] });
      wrap.replaceChildren(d.el) };
    await draw(true); NX.live.shop = () => { };
    return el('div', { class: 'scr' }, NX.topbar('Shop', gearBtn(), () => NX.go('home', null, { root: 1 })), NX.page([head, tabs, el('div', { style: { height: '8px' } }), wrap, el('p', { class: 'dkh' }, 'SWIPE UP / DOWN')], true), NX.navbar('shop'));
  };

  /* ---------- PITCH & BALL (deck) ---------- */
  S.fieldball = async () => {
    let tab = 'balls', keep = { balls: 0, fields: 0 }; const wrap = el('div', { class: 'dkw' }), tabs = el('div', { class: 'tabs' }), info = el('div', { class: 'card pad', style: { margin: '8px 0' } });
    const draw = async reset => {
      const it = await B.shop.items(), bs = it.filter(i => i.type === 'ball'), fs = it.filter(i => i.type === 'field'), eb = bs.find(b => b.equipped) || bs[0], cols = G.TR[eb.key].c;
      info.replaceChildren(el('div', { class: 'row' }, el('img', { src: eb.img, style: { width: '44px' } }), el('div', { style: { flex: 1 } }, el('b', null, eb.name), el('div', { class: 'mut', style: { fontSize: '12px' } }, 'Light trail: ' + G.TRN[eb.key]))), el('div', { class: 'trail-prev', style: { background: 'linear-gradient(90deg,transparent,' + cols.join(',') + ')' } }));
      tabs.replaceChildren(...[['balls', 'Balls'], ['fields', 'Pitches']].map(([k, l]) => el('button', { class: tab === k ? 'on' : '', onclick: () => { tab = k; draw() } }, l)));
      const list = tab === 'balls' ? bs : fs, type = tab === 'balls' ? 'ball' : 'field';
      const use = async i => { if (i.owned) { if (!i.equipped) await B.shop.equip(type, i.key); draw() } else NX.confirm('Unlock ' + i.name, 'Buy for ' + fmt(i.price) + ' coins?', 'Buy', async () => { try { await B.shop.buy(i.id); await B.shop.equip(type, i.key) } catch (e) { NX.err(e) } draw() }) };
      const d = NX.deck({ items: list, index: keep[tab], cls: type === 'field' ? 'fld' : '', onChange: c => { keep[tab] = c }, onTap: use,
        card: i => [el('img', { src: i.img, alt: '', draggable: 'false' }), el('b', null, i.name.replace(' Pitch', '')), i.equipped ? el('small', { class: 'eqd' }, '✓ EQUIPPED') : i.owned ? el('small', null, 'TAP TO EQUIP') : el('span', { class: 'lkd' }, svg('lock'), fmt(i.price))] });
      wrap.replaceChildren(d.el) };
    await draw();
    return el('div', { class: 'scr' }, NX.topbar('Pitch & ball'), NX.page([tabs, wrap, el('p', { class: 'dkh' }, 'SWIPE UP / DOWN'), info]));
  };

  /* ---------- wrappers: keep old screens, swap leftovers of the old look ---------- */
  const wrap = (name, fn) => { const o = S[name]; if (!o) return; S[name] = async (...a) => { const n = await o(...a); fn(n); return n } };
  wrap('daily', n => n.querySelectorAll('img[src*="start_rocket"]').forEach(i => { i.src = A('gift'); i.style.width = '130px'; i.style.height = '130px' }));
  { const o = S.auth; if (o) S.auth = p => { const n = o(p), lg = n.querySelector('.lg'); if (lg) lg.replaceChildren(el('img', { class: 'lgo', src: A('logo'), alt: 'BERMUDA NXG' })); return n } }
  wrap('league', n => n.querySelectorAll('img[src*="g_league"]').forEach(i => { i.src = A('k_trophy'); i.style.width = '64px' }));
  wrap('wallet', n => { n.querySelectorAll('img[src*="i_gift"]').forEach(i => i.src = A('gift')) });
})();
