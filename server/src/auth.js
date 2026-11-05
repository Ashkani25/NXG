'use strict';
const jwt = require('jsonwebtoken'), bcrypt = require('bcryptjs'), cfg = require('./config'), SB = require('./supabase'), { bad } = require('./util');
const signToken = uid => jwt.sign({ uid }, cfg.JWT_SECRET, { expiresIn: '60d' });
const verifyToken = t => { try { return jwt.verify(String(t || ''), cfg.JWT_SECRET).uid || null } catch (e) { return null } };
/* short-lived seat ticket: proves to a Colyseus room that the SERVER (not the client) reserved this seat for this user */
const signTicket = (uid, scope) => jwt.sign({ uid, scope }, cfg.TICKET_SECRET, { expiresIn: '3m' });
const verifyTicket = (t, scope) => { try { const p = jwt.verify(String(t || ''), cfg.TICKET_SECRET); return p.scope === scope ? p.uid : null } catch (e) { return null } };
const hash = pw => bcrypt.hash(pw, 10), same = (pw, h) => bcrypt.compare(pw, h);
async function requireUser(req, _res, next) { try { const h = req.headers.authorization || '', uid = verifyToken(h.startsWith('Bearer ') ? h.slice(7) : '');
  if (!uid) throw bad('Please sign in', 401); const u = await SB.getUserById(uid); if (!u) throw bad('Account not found', 401); if (u.banned) throw bad('Account suspended', 403); req.uid = uid; req.user = u; next() } catch (e) { next(e) } }
let gclient = null;
async function verifyGoogle(idToken) { if (!cfg.GOOGLE_CLIENT_ID) throw bad('Google sign-in is not configured', 501); const { OAuth2Client } = require('google-auth-library'); gclient = gclient || new OAuth2Client(cfg.GOOGLE_CLIENT_ID);
  const t = await gclient.verifyIdToken({ idToken, audience: cfg.GOOGLE_CLIENT_ID }); const p = t.getPayload(); return { googleId: p.sub, email: p.email, name: p.name } }
module.exports = { signToken, verifyToken, signTicket, verifyTicket, hash, same, requireUser, verifyGoogle };
