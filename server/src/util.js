'use strict';
class HttpError extends Error { constructor(status, message) { super(message); this.status = status } }
const bad = (m, s) => new HttpError(s || 400, m);
const clean = (s, n) => String(s == null ? '' : s).replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, n);
const now = () => new Date();
const sleep = ms => new Promise(r => setTimeout(r, ms));
/* tiny in-memory rate limiter: key -> max hits per windowMs */
const hits = new Map();
function limit(key, max, windowMs) { const t = Date.now(), a = (hits.get(key) || []).filter(x => t - x < windowMs); if (a.length >= max) { hits.set(key, a); return false } a.push(t); hits.set(key, a); return true }
setInterval(() => { const t = Date.now(); for (const [k, a] of hits) if (!a.some(x => t - x < 120000)) hits.delete(k) }, 60000).unref();
module.exports = { HttpError, bad, clean, now, sleep, limit };
