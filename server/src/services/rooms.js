'use strict';
const { matchMaker } = require('@colyseus/core'), L = require('../lib'), { bad, clean } = require('../util'), SB = require('../supabase'), U = require('./users'), { signTicket } = require('../auth');

const CH = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// Generate 6-character room code
const code6 = () => Array.from({ length: 6 }, () => CH[Math.floor(Math.random() * CH.length)]).join('');

/**
 * Create a game room
 */
async function create(uid, o = {}) {
  const u = await SB.getUserById(uid);
  
  // Validate capacity
  const capacity = [2, 4, 6].includes(o.capacity) ? o.capacity : 2;
  const teamSize = capacity / 2;
  
  // Validate match time
  const matchTime = [180, 300, 420, 600].includes(+o.matchTime) ? +o.matchTime : 300;
  
  // Validate field
  const field = L.FIELDS.includes(o.field) ? o.field : (u.equip?.field || 'stadium');
  const ball = (o.ball !== undefined) ? Math.max(0, Math.min(35, o.ball)) : (u.equip?.ball || 0);
  
  // Generate unique 6-character code
  let code;
  for (let n = 0; n < 8; n++) {
    const c = code6();
    if (!(await SB.getRoomByCode(c))) { code = c; break; }
  }
  if (!code) throw bad('Could not create room, try again');
  
  // Create room in Colyseus
  const room = await matchMaker.createRoom('gameroom', {
    code,
    name: clean(o.name, 24) || u.username + "'s Room",
    public: !!o.public,
    hostId: uid,
    hostName: u.username,
    hostPub: U.pub(u),
    capacity,
    teamSize,
    settings: { field, ball, matchTime, turnTime: 15 }
  });
  
  // Create seat reservation for host
  const reservation = await matchMaker.reserveSeatFor(room, {
    uid,
    ticket: signTicket(uid, 'gameroom:' + code)
  });
  
  return { code, reservation, capacity, roomId: room.roomId };
}

/**
 * Join an existing room by code
 */
async function join(uid, code) {
  code = clean(code, 6).toUpperCase();
  const r = await SB.getRoomByCode(code);
  
  if (!r) throw bad('Room not found', 404);
  
  const reservation = await matchMaker.reserveSeatFor(r, {
    uid,
    ticket: signTicket(uid, 'gameroom:' + code)
  });
  
  return { code, reservation, capacity: r.capacity };
}

/**
 * List public rooms available to join
 */
async function list() {
  const rooms = await SB.getPublicRooms();
  
  return rooms.map(r => ({
    code: r.code,
    name: r.name,
    host: r.host_pub,
    capacity: r.capacity,
    players: 0, // Will be updated via Colyseus presence
    field: r.settings?.field,
    matchTime: Math.round((r.settings?.matchTime || 300) / 60),
    mode: r.capacity === 2 ? '1v1' : r.capacity === 4 ? '2v2' : '3v3'
  }));
}

/**
 * Get active rooms count
 */
async function activeCount() {
  const rooms = await SB.getPublicRooms();
  return rooms.filter(r => r.status === 'waiting' || r.status === 'playing').length;
}

module.exports = { create, join, list, activeCount };