/* v6: 3D feel for the app screens (tilt/parallax + coverflow). Pure visual; safe to delete. */
(() => {
  'use strict';
  const app = document.getElementById('app'); if (!app) return;
  let gx = 0, gy = 0, tx = 0, ty = 0, gyro = false, raf = 0;
  const set = () => { raf = 0; gx += (tx - gx) * .12; gy += (ty - gy) * .12; app.style.setProperty('--px', gx.toFixed(3)); app.style.setProperty('--py', gy.toFixed(3)); if (Math.abs(tx - gx) + Math.abs(ty - gy) > .004) raf = requestAnimationFrame(set) };
  const kick = () => { if (!raf) raf = requestAnimationFrame(set) };
  addEventListener('pointermove', e => { if (gyro) return; tx = e.clientX / innerWidth * 2 - 1; ty = e.clientY / innerHeight * 2 - 1; kick() }, { passive: true });
  addEventListener('deviceorientation', e => { if (e.gamma == null) return; gyro = true; tx = Math.max(-1, Math.min(1, e.gamma / 28)); ty = Math.max(-1, Math.min(1, (e.beta - 45) / 28)); kick() }, { passive: true });
  /* coverflow for horizontal carousels (.hs > .mode) */
  const flow = hs => {
    const r = hs.getBoundingClientRect(), c = r.left + r.width / 2;
    for (const m of hs.children) {
      const b = m.getBoundingClientRect(), d = Math.max(-1, Math.min(1, (b.left + b.width / 2 - c) / (r.width * .62)));
      m.style.setProperty('--ry', (-d * 26).toFixed(1) + 'deg'); m.style.setProperty('--tz', (-Math.abs(d) * 46).toFixed(0) + 'px'); m.style.setProperty('--sc', (1 - Math.abs(d) * .06).toFixed(3));
    }
  };
  const hook = hs => {
    if (hs.__fx) return; hs.__fx = 1; let t = 0;
    const go = () => { t = 0; flow(hs) };
    hs.addEventListener('scroll', () => { if (!t) t = requestAnimationFrame(go) }, { passive: true });
    flow(hs); setTimeout(() => flow(hs), 120); setTimeout(() => flow(hs), 600);
  };
  const scan = () => app.querySelectorAll('.hs').forEach(hook);
  new MutationObserver(scan).observe(app, { childList: true, subtree: true });
  scan();
})();
