'use strict';
const { matchMaker } = require('@colyseus/core'), L = require('../lib'), { bad, clean } = require('../util'), U = require('./users'), { signTicket } = require('../auth');

const CH = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// Generate 6-character room code
const code6 = () => Array.from({ length: 6 }, () => CH[Math.floor(Math.random() * CH.length)]).join('');

// Get all gamerooms from Colyseus
const all = async () => matchMaker.query({ name: 'gameroom' });

// Find room by code
const byCode = async code => (await all()).find(r => r.metadata && r.metadata.code === code);

/**
 * Create a game room
 * @param {string} uid - Host user ID
 * @param {Object} o - Options
 * @param {string} [o.name] - Room name
 * @param {boolean} [o.public] - Is room public
 * @param {number} [o.capacity] - Max players (2, 4, or 6)
 * @param {string} [o.field] - Field ID
 * @param {number} [o.ball] - Ball ID
 * @param {number} [o.matchTime] - Match duration in seconds
 */
async function create(uid, o = {}) {
  const u = await U.getUser(uid);
  
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
    if (!(await byCode(c))) { code = c; break; }
  }
  if (!code) throw bad('Could not create room, try again');
  
  // Create room in Colyseus
  const room = await matchMaker.createRoom('gameroom', {
    code,
    name: clean(o.name, 24) || u.name + "'s Room",
    public: !!o.public,
    hostId: uid,
    hostName: u.name,
    hostPub: U.pub(u),
    capacity,
    teamSize,
    settings: {
      field,
      ball,
      matchTime,
      turnTime: 15
    }
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
 * @param {string} uid - User ID
 * @param {string} code - Room code
 */
async function join(uid, code) {
  code = clean(code, 6).toUpperCase();
  const r = await byCode(code);
  
  if (!r) throw bad('Room not found', 404);
  if (r.locked) throw bad('Room is locked');
  if (r.clients >= r.maxClients) throw bad('Room is full');
  
  const reservation = await matchMaker.reserveSeatFor(r, {
    uid,
    ticket: signTicket(uid, 'gameroom:' + code)
  });
  
  return { code, reservation, capacity: r.maxClients };
}

/**
 * List public rooms available to join
 */
async function list() {
  const rooms = await all();
  
  return rooms
    .filter(r => r.metadata?.public && !r.locked && r.clients < r.maxClients)
    .sort((a, b) => b.createdAt - a.createdAt)
    .slice(0, 50)
    .map(r => ({
      code: r.metadata.code,
      name: r.metadata.name,
      host: r.metadata.hostPub,
      capacity: r.maxClients,
      players: r.clients,
      field: r.metadata.settings?.field,
      matchTime: Math.round((r.metadata.settings?.matchTime || 300) / 60),
      mode: r.metadata.capacity === 2 ? '1v1' : r.metadata.capacity === 4 ? '2v2' : '3v3'
    }));
}

/**
 * Get active rooms count (for stats)
 */
async function activeCount() {
  const rooms = await all();
  return rooms.filter(r => r.metadata?.status === 'waiting' || r.metadata?.status === 'playing').length;
}

module.exports = { create, join, list, activeCount };
