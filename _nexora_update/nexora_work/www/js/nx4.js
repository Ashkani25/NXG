/* NX v10: new card menu, horizontal flip decks, frame team picker, video-only intro, league fix. Loaded last. */
(() => {
  'use strict';
  const NX = window.NX, { el, svg, fmt, B, G } = NX, S = NX.screens, A = n => 'assets/nx3/' + n + '.webp';
  const sfx = n => { try { G.sfx(n) } catch (e) { } };
  const gearBtn = () => el('button', { class: 'ibtn', 'aria-label': 'Settings', onclick: () => NX.go('settings') }, el('img', { src: A('gear'), alt: '' }));

  /* ---------- intro = ONLY the uploaded video, then main menu ---------- */
  /* ---------- horizontal page-flip deck (same feel as the main menu) ---------- */
  NX.deck = o => {
    const items = o.items, N = items.length, nodes = new Map(), clamp = i => Math.max(0, Math.min(N - 1, i)); let pos = clamp(o.index || 0), tgt = Math.round(pos), vel = 0, raf = 0, lastT = 0, st = null, moved = false, ctr = -1;
    const cnt = el('div', { class: 'dkc' }), root = el('div', { class: 'dk hz' });
    const arrow = (c, d) => el('button', { class: 'dka ' + c, 'aria-label': d < 0 ? 'Previous' : 'Next', onclick: () => go(Math.round(tgt) + d) }, el('img', { src: A(d < 0 ? 'a_left' : 'a_right'), alt: '' }));
    root.append(arrow('l', -1), arrow('r', 1), cnt);
    const place = (n, d) => { const ad = Math.abs(d);
      n.style.transform = 'translate3d(-50%,-50%,0) translate3d(' + (d * 66).toFixed(1) + '%,0,' + (-ad * 90).toFixed(0) + 'px) rotateY(' + (-d * 30).toFixed(1) + 'deg) scale(' + (1 - Math.min(ad, 2) * .1).toFixed(3) + ')';
      n.style.opacity = ad > 2.2 ? 0 : (1 - ad * .2).toFixed(2); n.style.zIndex = 100 - Math.round(ad * 10); n.style.pointerEvents = ad < .6 ? 'auto' : 'none' };
    const layout = () => { const c = Math.round(pos), lo = Math.max(0, Math.floor(pos) - 2), hi = Math.min(N - 1, Math.ceil(pos) + 2);
      for (const [i, n] of nodes) if (i < lo || i > hi) { n.remove(); nodes.delete(i) }
      for (let i = lo; i <= hi; i++) { let n = nodes.get(i); if (!n) { n = el('div', { class: 'dcard' + (o.cls ? ' ' + o.cls : ''), 'data-i': i }, o.card(items[i], i)); nodes.set(i, n); root.append(n) } place(n, i - pos) }
      if (c !== ctr) { ctr = c; for (const [i, n] of nodes) n.classList.toggle('ctr', i === c); cnt.textContent = (c + 1) + ' / ' + N; o.onChange && o.onChange(c, items[c]) } };
    const tick = t => { const dt = Math.min(.035, (t - lastT) / 1000 || .016); lastT = t; vel += ((tgt - pos) * 300 - vel * 23) * dt; pos += vel * dt; layout();
      if (Math.abs(tgt - pos) > .0015 || Math.abs(vel) > .004) raf = requestAnimationFrame(tick); else { pos = tgt; vel = 0; raf = 0; layout() } };
    const kick = () => { if (!raf) { lastT = performance.now(); raf = requestAnimationFrame(tick) } };
    const go = i => { i = clamp(i); if (i !== tgt) sfx('ui'); tgt = i; kick() };
    const STEP = () => Math.max(120, root.clientWidth * .42);
    root.addEventListener('pointerdown', e => { if (e.target.closest('.dka') || e.target.closest('.act')) return; st = { x: e.clientX, p: pos, t: performance.now(), id: e.pointerId }; moved = false; vel = 0; if (raf) { cancelAnimationFrame(raf); raf = 0 } });
    root.addEventListener('pointermove', e => { if (!st) return; const dx = e.clientX - st.x; if (!moved && Math.abs(dx) > 7) { moved = true; try { root.setPointerCapture(st.id) } catch (x) { } }
      if (moved) { let p = st.p - dx / STEP(); if (p < 0) p *= .35; if (p > N - 1) p = N - 1 + (p - N + 1) * .35; pos = p; layout() } });
    root.addEventListener('pointerup', e => { if (!st) return; const dx = e.clientX - st.x, v = -dx / Math.max(1, performance.now() - st.t);
      if (moved) { tgt = clamp(Math.round(pos + Math.max(-3, Math.min(3, v * 1.1)))); if (tgt !== ctr) sfx('ui'); kick() } st = null });
    root.addEventListener('pointercancel', () => { if (st && moved) { tgt = Math.round(pos); kick() } st = null });
    root.addEventListener('click', e => { if (moved) { moved = false; return } const c = e.target.closest('.dcard'); if (!c || e.target.closest('.act') || e.target.closest('.dka')) return; const i = +c.dataset.i; if (i === Math.round(tgt)) o.onTap && o.onTap(items[i], i); else go(i) });
    root.addEventListener('wheel', e => { e.preventDefault(); go(Math.round(tgt) + ((e.deltaX || e.deltaY) > 0 ? 1 : -1)) }, { passive: false });
    layout();
    return { el: root, go, index: () => Math.round(tgt), refresh: () => { for (const [i, n] of nodes) n.replaceChildren(...[].concat(o.card(items[i], i))) } };
  };

  /* ---------- team picker: team logo sits inside the circle of the new frame ---------- */
  const teamPicker = (get, set, opt) => {
    opt = opt || {}; const cats = G.CATS.filter(c => !opt.cats || opt.cats.includes(c[0])); const k0 = G.CATS[G.catOf(get())][0]; let cat = Math.max(0, cats.findIndex(c => c[0] === k0)), deck;
    const tabs = el('div', { class: 'tabs' }), wrap = el('div', { class: 'dkw' });
    const build = () => {
      tabs.replaceChildren(...cats.map((c, i) => el('button', { class: cat === i ? 'on' : '', onclick: () => { cat = i; build() } }, c[1])));
      const items = G.TEAMS.filter(t => t.cat === cats[cat][0]).slice(0, opt.max || 999), idx = Math.max(0, items.findIndex(t => t.id === get()));
      const owns = t => t.cat !== 'vip' || ((NX.P.owned && NX.P.owned.teams) || [G.VIP_FREE]).includes(t.id);
      deck = NX.deck({ items, index: idx, cls: 'frm', card: (t, i) => { const on = get() === t.id, lk = !owns(t); return [
        el('div', { class: 'fhole' }, el('img', { src: t.src, alt: '', draggable: 'false' })), el('img', { class: 'fimg', src: A(t.cat === 'vip' ? 'frame_vip' : 'frame'), alt: '', draggable: 'false' }),
        el('b', { class: 'fname' }, t.name), el('div', { class: 'fsl' }, el('span', null, '#' + (i + 1)), el('span', null, cats[cat][1]),
          lk ? el('span', { class: 'lkp' }, '🔒 ' + fmt(G.vipPrice(t.id))) : el('span', { class: on ? 'on' : '' }, on ? '✓ ' + 'USED' : 'TAP'))] },
        onTap: async t => { if (!owns(t)) { const price = G.vipPrice(t.id); NX.confirm('Unlock ' + t.name, 'VIP disc — buy for ' + fmt(price) + ' gems?', 'Buy', async () => { try { await B.shop.buy('team:' + t.id); NX.P = await B.profile.get(); sfx('ui'); NX.toast('Unlocked ' + t.name, 'ok'); await set(t); deck.refresh() } catch (e) { NX.toast(e.message || 'Purchase failed') } }); return } await set(t); deck.refresh() } });
      wrap.replaceChildren(deck.el); };
    build(); return [tabs, el('div', { style: { height: '8px' } }), wrap, el('p', { class: 'dkh' }, 'SWIPE LEFT / RIGHT')];
  };
  const FORMS = (get, set) => { const fm = el('div', { class: 'fm' });
    const draw = () => fm.replaceChildren(...G.FORMS.map((f, i) => { const cv = document.createElement('canvas'); cv.width = 120; cv.height = 100; const x = cv.getContext('2d'); x.fillStyle = '#0d2a4d'; x.fillRect(0, 0, 120, 100); x.strokeStyle = 'rgba(150,210,255,.7)'; x.lineWidth = 2; x.strokeRect(2, 2, 116, 96); for (const [nx, ny] of G.slots(i)) { x.fillStyle = '#4aa8ff'; x.beginPath(); x.arc(14 + nx * 92, 92 - ny / .5 * 80, 8, 0, 7); x.fill(); x.strokeStyle = '#fff'; x.stroke() } return el('button', { class: get() === i ? 'sel' : '', onclick: async () => { await set(i); draw() } }, cv, el('b', null, f[0]), el('span', { class: 'mut' }, f[1])) })); draw(); return fm };

  S.teams = async () => { const P = NX.P; let team = P.team, form = P.form || 0;
    const pick = teamPicker(() => team, async t => { team = t.id; await B.profile.update({ team: t.id }); sfx('ui') }), fm = FORMS(() => form, async i => { form = i; await B.profile.update({ form: i }) });
    return el('div', { class: 'scr' }, NX.topbar('Team & formation'), NX.page([...pick, el('div', { class: 'sec' }, 'Formation'), fm])) };
  S.onboard = () => { const P = NX.P; let team = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16, placeholder: 'Choose your name' });
    const pick = teamPicker(() => team, t => { team = t.id }, { cats: ['club', 'nat'] });
    return el('div', { class: 'scr' }, el('div', { class: 'bgmagic' }), NX.page([el('h2', { class: 'gold', style: { textAlign: 'center', letterSpacing: '3px', marginTop: '20px' } }, 'CREATE YOUR PLAYER'), name, el('div', { style: { height: '10px' } }), ...pick,
      el('button', { class: 'btn gold block cta', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: team, team }); NX.UI.seenIntro = 1; NX.saveUI(); NX.go('home', null, { root: 1 }) }) }, 'Let\'s go')])) };
  S.editprofile = async () => { const P = NX.P; let av = P.avatar; const name = el('input', { class: 'inp', value: P.name, maxlength: 16 }), pick = teamPicker(() => av, t => { av = t.id }, { cats: ['club', 'nat', 'car', 'lux', 'spt'] });
    return el('div', { class: 'scr' }, NX.topbar('Edit profile'), NX.page([el('div', { class: 'mut', style: { margin: '4px 2px 6px' } }, 'Display name'), name, el('div', { class: 'sec' }, 'Avatar'), ...pick, el('button', { class: 'btn gold block', onclick: e => NX.busy(e.currentTarget, async () => { await B.profile.update({ name: name.value, avatar: av }); NX.toast('Saved', 'ok'); NX.back() }) }, 'Save')])) };

  /* ---------- HOME: five big cards, nothing else competing ---------- */
  S.home = async () => {
    const P = NX.P, unread = await B.notifications.unread(), on = await B.presence.onlineCount(), online = NX.online();
    const coinsV = el('b', null, fmt(P.coins)), gemsV = el('b', null, fmt(P.gems));
    const goShop = () => NX.go('shop', { tab: B.features && B.features.billing ? 'packs' : 'chests' }, { root: 1 });
    const pill = (img, val, fn) => el('div', { class: 'cu4' }, el('img', { src: A(img), alt: '' }), val, el('button', { class: 'plus', 'aria-label': 'Add', onclick: fn }, '+'));
    const need = fn => online ? fn : () => NX.needOnline();
    const cards = [
      { art: 'c_friends', go: need(() => NX.go('friends')), dim: !online }, { art: 'c_tournaments', go: need(() => NX.go('tournaments')), dim: !online },
      { art: 'c_play', main: true, go: () => online ? NX.flow.quick() : NX.flow.botSetup() },
      { art: 'c_rankings', go: () => NX.go('league') }, { art: 'c_discs', go: () => NX.go('teams') }];
    let cur = 2; const cs = el('div', { class: 'cs4' });
    const render = () => [...cs.children].forEach((c, i) => { const d = i - cur, ad = Math.abs(d); c.classList.toggle('main', d === 0); c.style.zIndex = 20 - ad; c.style.opacity = ad > 2 ? 0 : 1 - ad * .14; c.style.pointerEvents = ad > 2 ? 'none' : 'auto';
      c.style.transform = 'translate3d(-50%,0,0) translateX(' + (d * 62) + '%) translateZ(' + (-ad * 80) + 'px) rotateY(' + (-d * 26) + 'deg) scale(' + (d === 0 ? 1.06 : .86 - (ad - 1) * .06) + ')' });
    cards.forEach((c, i) => cs.append(el('div', { class: 'cc4' + (c.dim ? ' dim' : ''), onclick: () => { if (i === cur) c.go(); else { cur = i; render(); sfx('ui') } } }, el('img', { src: A(c.art), alt: '', draggable: 'false' }))));
    let sx = null; cs.addEventListener('pointerdown', e => { sx = e.clientX }); cs.addEventListener('pointerup', e => { if (sx == null) return; const dx = e.clientX - sx; sx = null; if (Math.abs(dx) > 34) { cur = Math.max(0, Math.min(cards.length - 1, cur + (dx < 0 ? 1 : -1))); render(); sfx('ui') } }); cs.addEventListener('pointercancel', () => { sx = null });
    const arrow = (dir, ic) => el('button', { class: 'ar4 ' + dir, 'aria-label': dir === 'l' ? 'Previous' : 'Next', onclick: () => { cur = Math.max(0, Math.min(cards.length - 1, cur + (dir === 'l' ? -1 : 1))); render(); sfx('ui') } }, el('img', { src: A(ic), alt: '' }));
    const root = el('div', { class: 'scr home' }, NX.page([
      el('div', { class: 'hb4' },
        el('div', { class: 'r1' }, el('div', { class: 'me', onclick: () => NX.go('profile', null, { root: 1 }) }, el('div', { class: 'avw' }, el('img', { class: 'crw', src: A('crown'), alt: '' }), NX.avatar(P, 'sm')),
          el('div', { class: 'mt' }, el('b', { class: 'nm' }, P.name), el('span', { class: 'xpl' }, 'Lv. ' + P.level), el('div', { class: 'bar' }, el('i', { style: { width: Math.min(100, P.xp / P.xpNeed * 100) + '%' } })))),
          el('button', { class: 'rb2', 'aria-label': 'Notifications', onclick: () => NX.go('notifications') }, el('img', { src: A('bell'), alt: '' }), unread ? el('em', null, unread > 9 ? '9+' : unread) : null),
          el('button', { class: 'rb2', 'aria-label': 'Settings', onclick: () => NX.go('settings') }, el('img', { src: A('gear'), alt: '' }))),
        el('div', { class: 'r2' }, pill('coin', coinsV, goShop), pill('gem', gemsV, goShop))),
      el('div', { class: 'logo4' }, el('img', { src: A('logo'), alt: 'BERMUDA NXG' }), on ? el('small', null, fmt(on) + ' ONLINE') : null),
      el('div', { class: 'stage4' }, cs, arrow('l', 'a_left'), arrow('r', 'a_right'))], true), NX.navbar('home')); render();
    NX.live.home = async () => { const p = await B.profile.get(); NX.P = p; coinsV.textContent = fmt(p.coins); gemsV.textContent = fmt(p.gems) };
    return root;
  };

  for (const k of ['shop', 'fieldball']) { const o = S[k]; if (o) S[k] = async (...a) => { const n = await o(...a); n.querySelectorAll('.dkh').forEach(h => h.textContent = 'SWIPE LEFT / RIGHT'); return n } }

  /* ---------- LEAGUE: bottom bar + back to home (it used to trap the player) ---------- */
  { const o = S.league; S.league = async (...a) => { const n = await o(...a); const bk = n.querySelector('.top .ibtn'); if (bk) bk.onclick = () => NX.go('home', null, { root: 1 }); const pg = n.querySelector('.page'); if (pg) pg.classList.add('nav'); n.append(NX.navbar('league')); return n } }

  /* ---------- PROFILE: mock-up details (online dot + NX GAME mark) ---------- */
  { const o = S.profile; S.profile = async (...a) => { const n = await o(...a); const pav = n.querySelector('.pav'), pcd = n.querySelector('.pcd');
    if (pcd) pcd.prepend(el('i', { class: 'odot' })); if (pav) pav.after(el('div', { class: 'wm' }, 'NX GAME')); return n } }
})();
