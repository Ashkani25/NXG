/* UI core: DOM helper, icons, router, modal, toast, persisted UI settings */
(() => {
  'use strict';
  const NX = window.NX = { G: window.NexoraGame, B: window.NexoraBackend, CFG: window.NEXORA_CONFIG, screens: {}, stack: [], P: null };
  const $ = (s, r) => (r || document).querySelector(s);
  const el = (t, a, ...c) => {
    const e = document.createElement(t);
    if (a) for (const k in a) { const v = a[k]; if (v == null || v === false) continue; if (k === 'class') e.className = v; else if (k === 'html') e.innerHTML = v; else if (k.slice(0, 2) === 'on') e.addEventListener(k.slice(2), v); else if (k === 'style' && typeof v === 'object') Object.assign(e.style, v); else e.setAttribute(k, v === true ? '' : v) }
    for (const x of c.flat(9)) if (x != null && x !== false) e.append(x.nodeType ? x : document.createTextNode(x));
    return e;
  };
  const PATH = {
    home: '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
    games: '<rect x="2.5" y="7" width="19" height="10" rx="5"/><path d="M7 10v4M5 12h4"/><circle cx="15.5" cy="11" r=".9"/><circle cx="18" cy="13" r=".9"/>',
    shop: '<path d="M3 4h2.5l2.2 10.5h10.6L20.5 7H6.2"/><circle cx="9.5" cy="19" r="1.4"/><circle cx="17" cy="19" r="1.4"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4.5 4.2-6.5 8-6.5s7 2 8 6.5"/>',
    gift: '<rect x="3.5" y="8" width="17" height="4" rx="1"/><path d="M5 12v8h14v-8M12 8v12M12 8c-1-3.500-5-4-5-1.600C7 8 9 8 12 8zM12 8c1-3.500 5-4 5-1.600C17 8 15 8 12 8z"/>',
    bell: '<path d="M6 17V11a6 6 0 0 1 12 0v6l1.500 2h-15zM10 21a2 2 0 0 0 4 0"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.500v3M12 18.500v3M2.500 12h3M18.500 12h3M5.300 5.300l2.100 2.100M16.600 16.600l2.100 2.100M18.700 5.300l-2.100 2.100M7.400 16.600l-2.100 2.100"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', chev: '<path d="M9 5l7 7-7 7"/>', back: '<path d="M15 5l-7 7 7 7"/>',
    search: '<circle cx="11" cy="11" r="6.500"/><path d="M16 16l5 5"/>', send: '<path d="M3 11.500L21 4l-6.500 17-3-7z"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.500 11a6.500 6.500 0 0 0 13 0M12 17.500V21"/>',
    spk: '<path d="M4 9.500h3.500L13 5v14l-5.500-4.500H4z"/><path d="M16.500 8.500a5 5 0 0 1 0 7M19 6a8.500 8.500 0 0 1 0 12"/>',
    check: '<path d="M5 12.500l4.500 4.500L19 7.500"/>', lock: '<rect x="5" y="10.500" width="14" height="10" rx="2"/><path d="M8 10.500V8a4 4 0 0 1 8 0v2.500"/>',
    star: '<path d="M12 3l2.700 5.600 6.100.8-4.500 4.200 1.100 6.100L12 16.800 6.600 19.700l1.100-6.100L3.200 9.400l6.100-.8z" fill="currentColor"/>',
    trophy: '<path d="M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v1.500A3.500 3.500 0 0 0 7.500 11M17 6h3v1.500A3.500 3.500 0 0 1 16.500 11M12 14v4M8 20h8"/>',
    users: '<circle cx="9" cy="8" r="3.500"/><path d="M2.500 20c.8-3.800 3.400-5.500 6.500-5.500s5.700 1.700 6.500 5.500M16 4.800a3.400 3.400 0 0 1 0 6.400M18 14.800c2 .7 3.200 2.400 3.600 5"/>',
    chat: '<path d="M4 5h16v11H9l-5 4z"/>', close: '<path d="M6 6l12 12M18 6L6 18"/>', play: '<path d="M8 5l11 7-11 7z" fill="currentColor"/>',
    pause: '<path d="M8 5v14M16 5v14" stroke-width="3"/>', cal: '<rect x="3.500" y="5" width="17" height="15" rx="2.500"/><path d="M3.500 10h17M8 3v4M16 3v4"/>',
    emo: '<circle cx="12" cy="12" r="8.500"/><path d="M8.500 14c1 1.600 2.200 2.300 3.500 2.300s2.500-.7 3.500-2.300"/><circle cx="9.300" cy="9.800" r=".8"/><circle cx="14.700" cy="9.800" r=".8"/>',
    out: '<path d="M10 4H5v16h5M15 8l4 4-4 4M19 12H9"/>', copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
    edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>', refresh: '<path d="M20 11a8 8 0 1 0-2.300 5.700M20 4v7h-7"/>', heart: '<path d="M12 20s-7.500-4.600-7.500-10A4.300 4.300 0 0 1 12 7.600 4.300 4.300 0 0 1 19.500 10C19.500 15.400 12 20 12 20z"/>', fb: '<path d="M14 8h3V4h-3a4 4 0 0 0-4 4v3H7v4h3v6h4v-6h3l1-4h-4V8.500"/>'
  };
  NX.svg = (n, cls) => { const s = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('class', 'i ' + (cls || '')); s.innerHTML = PATH[n] || ''; return s };
  NX.ico = (n, cls) => el('img', { class: cls || 'ic0', alt: '', src: 'assets/ui2/' + 'g_' + n + '.webp', draggable: 'false' });
  NX.icoSrc = n => 'assets/ui2/' + 'g_' + n + '.webp';
  NX.fmt = n => Number(n || 0).toLocaleString('en-US');
  NX.$ = $; NX.el = el;
  NX.teamImg = id => (NX.G.T(id) || NX.G.T('club0')).src;
  NX.teamName = id => (NX.G.T(id) || {}).name || '';

  /* ----- persisted UI settings ----- */
  const KEY = 'nexora_ui_v2';
  NX.UI = Object.assign({ theme: 'gold', snd: 1, mus: 1, vib: 1, gfx: 'high', mic: 0, spk: 1, seenIntro: 0 }, (() => { try { return JSON.parse(localStorage.getItem(KEY)) || {} } catch (e) { return {} } })());
  NX.saveUI = () => { try { localStorage.setItem(KEY, JSON.stringify(NX.UI)) } catch (e) { } const S = NX.G.SET; S.snd = NX.UI.snd; S.mus = NX.UI.mus; S.vib = NX.UI.vib; document.body.dataset.theme = 'gold'; NX.G.musicSync() };
  NX.saveUI();

  /* ----- toast / modal ----- */
  NX.toast = (msg, kind) => { const t = el('div', { class: 'tst ' + (kind || '') }, msg); $('#toasts').append(t); setTimeout(() => { t.style.transition = '.3s'; t.style.opacity = 0; setTimeout(() => t.remove(), 300) }, 2300) };
  NX.err = e => NX.toast((e && e.message) || String(e), 'bad');
  NX.modal = (content, opts) => {
    opts = opts || {}; const root = $('#modals'), box = el('div', { class: 'mbox' }, content), m = el('div', { class: 'mdl ' + (opts.sheet ? 'sheet' : ''), onclick: e => { if (e.target === m && !opts.sticky) close() } }, box);
    const close = () => { m.remove(); opts.onclose && opts.onclose() }; box.close = close; m.close = close; root.append(m); return m
  };
  NX.confirm = (title, text, yes, onYes, danger) => { const m = NX.modal([el('h3', null, title), el('p', null, text), el('div', { class: 'acts' }, el('button', { class: 'btn dark', onclick: () => m.close() }, 'Cancel'), el('button', { class: 'btn ' + (danger ? 'red' : 'gold'), onclick: () => { m.close(); onYes() } }, yes))]); return m };
  NX.rewards = (title, list, cb) => {
    const m = NX.modal([el('h3', { class: 'gold' }, title), el('div', { class: 'rew' }, list.map((r, i) => el('div', { style: { animationDelay: i * .12 + 's' } }, r.img ? el('img', { src: r.img }) : null, el('span', null, r.label)))), el('button', { class: 'btn gold block', onclick: () => { m.close(); cb && cb() } }, 'Awesome!')], { sticky: true }); return m
  };

  /* ----- router ----- */
  const app = () => $('#app');
  NX.mount = node => { const a = app(); a.replaceChildren(node) };
  NX.go = (name, params, opts) => {
    opts = opts || {}; if (opts.root) NX.stack = []; NX.stack.push({ name, params }); NX.render(); };
  NX.back = () => { if (NX.stack.length > 1) NX.stack.pop(); NX.render() };
  NX.render = async () => {
    const cur = NX.stack[NX.stack.length - 1]; if (!cur) return; NX.cleanup(); try { NX.P = await NX.B.profile.get() } catch (e) { }
    const fn = NX.screens[cur.name]; if (!fn) return console.error('no screen', cur.name); const node = await fn(cur.params || {}); if (NX.stack[NX.stack.length - 1] === cur) { NX.mount(node); NX.G.sfx('ui') } };
  const cleanups = []; NX.onLeave = f => cleanups.push(f); NX.cleanup = () => { while (cleanups.length) { try { cleanups.pop()() } catch (e) { } } };
  NX.refreshProfile = async () => { NX.P = await NX.B.profile.get() };
  NX.topbar = (title, right, onBack) => el('div', { class: 'top' }, el('button', { class: 'ibtn', onclick: onBack || NX.back }, NX.svg('back')), el('h2', { class: 'gold' }, title), right || el('div', { class: 'sp' }));
  NX.page = (children, nav) => el('div', { class: 'page ' + (nav ? 'nav' : '') }, children);
  NX.navbar = active => {
    const t = (id, g, label) => el('button', { class: active === id ? 'on' : '', onclick: () => NX.go(id, null, { root: 1 }) }, el('img', { src: 'assets/nx2/g_' + g + '.webp', alt: '' }), el('span', null, label));
    return el('div', { class: 'navbar' }, t('home', 'home', 'HOME'), t('profile', 'profile', 'PROFILE'), t('wallet', 'wallet', 'WALLET'), t('shop', 'cart', 'SHOP'), t('league', 'trophy', 'LEAGUES'))
  };
  NX.avatar = (p, cls, showLv) => el('div', { class: 'av ' + (cls || '') }, el('img', { src: NX.teamImg(p.avatar), alt: '' }), showLv ? el('div', { class: 'lv' }, NX.svg('star'), p.level) : null, p.online && !showLv ? el('i', { class: 'on' }) : null);
  NX.cur = (v, type) => el('span', { class: 'cur' }, el('img', { src: type === 'gems' ? 'assets/nx3/gem.webp' : 'assets/nx3/coin.webp', alt: '' }), NX.fmt(v));
  NX.leagueImg = () => 'assets/ui/wing_hex.webp';
  NX.online = () => !!(NX.B.features && NX.B.features.online);
  NX.needOnline = () => { NX.toast('Connect to the online server to use this feature'); return false };
  NX.offlineScreen = (title, text) => el('div', { class: 'scr' }, NX.topbar(title), NX.page(el('div', { class: 'empty', style: { paddingTop: '80px' } }, NX.ico('lobby', 'ic0'), el('p', null, text || 'This feature needs the online server.'))));
  NX.sleep = ms => new Promise(r => setTimeout(r, ms));
  NX.busy = async (btn, fn) => { if (btn.classList.contains('dis')) return; btn.classList.add('dis'); try { return await fn() } catch (e) { NX.err(e) } finally { btn.classList.remove('dis') } };
  /* keep wallet fresh */
  NX.B.onProfile(async () => { const c = NX.stack[NX.stack.length - 1]; if (c && NX.live && NX.live[c.name]) NX.live[c.name]() });
  NX.live = {};
})();
