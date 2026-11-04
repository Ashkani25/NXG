'use strict';
const { matchMaker } = require('@colyseus/core'), L = require('../lib'), { bad, clean } = require('../util'), U = require('./users'), { signTicket } = require('../auth');
const CH = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', code5 = () => Array.from({ length: 5 }, () => CH[Math.floor(Math.random() * CH.length)]).join('');
const all = async () => matchMaker.query({ name: 'gameroom' });
const byCode = async code => (await all()).find(r => r.metadata && r.metadata.code === code);
async function create(uid, o) { const u = await U.getUser(uid), mt = [180, 300, 420, 600].includes(+o.matchTime) ? +o.matchTime : 300, field = L.FIELDS.includes(o.field) ? o.field : u.equip.field; let code;
  for (let n = 0; n < 8; n++) { const c = code5(); if (!(await byCode(c))) { code = c; break } } if (!code) throw bad('Could not create a room, try again');
  const room = await matchMaker.createRoom('gameroom', { code, name: clean(o.name, 24) || u.name + "'s room", public: !!o.public, hostId: uid, hostPub: U.pub(u), settings: { field, ball: u.equip.ball, matchTime: mt, turnTime: 15 } });
  return { code, reservation: await matchMaker.reserveSeatFor(room, { uid, ticket: signTicket(uid, 'gameroom:' + code) }) } }
async function join(uid, code) { code = clean(code, 5).toUpperCase(); const r = await byCode(code); if (!r) throw bad('Room not found', 404); if (r.locked || r.clients >= r.maxClients) throw bad('Room is full');
  return { code, reservation: await matchMaker.reserveSeatFor(r, { uid, ticket: signTicket(uid, 'gameroom:' + code) }) } }
const list = async () => (await all()).filter(r => r.metadata && r.metadata.public && !r.locked && r.clients < r.maxClients).sort((a, b) => b.createdAt - a.createdAt).slice(0, 30)
  .map(r => ({ id: r.metadata.code, code: r.metadata.code, name: r.metadata.name, host: r.metadata.hostPub, field: r.metadata.settings.field, minutes: Math.round(r.metadata.settings.matchTime / 60), players: r.clients, max: 2 }));
module.exports = { create, join, list };
