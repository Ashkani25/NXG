'use strict';

const { Client } = require('pg');

// Session Pooler connection (for Railway deployment)
const DATABASE_URL = 'postgresql://postgres.cqbtbgdkgmcbhaoktcwy:owfCZONVNmm8elTF@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres';

const client = new Client({
  connectionString: DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function connect() {
  if (!client._connected) {
    await client.connect();
    client._connected = true;
    console.log('[DB] Connected to Supabase PostgreSQL!');
  }
}

// Initialize connection
connect().catch(console.error);

// Helper functions
async function query(sql, params = []) {
  await connect();
  const res = await client.query(sql, params);
  return res;
}

async function createUser(userData) {
  const shortId = 'NX-' + Math.random().toString(36).slice(-6).toUpperCase();
  const result = await query(
    `INSERT INTO users (username, short_id, avatar, team, stats, equip, owned, quests) 
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) 
     RETURNING *`,
    [
      userData.username || 'Guest',
      shortId,
      userData.avatar || 'club0',
      userData.team || 'club0',
      JSON.stringify({ played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 }),
      JSON.stringify({ ball: 4, field: 'stadium' }),
      JSON.stringify({ balls: [0, 4, 5], fields: ['stadium'], teams: [] }),
      JSON.stringify({ date: new Date().toISOString().slice(0, 10), list: [] })
    ]
  );
  return result.rows[0];
}

async function getUserById(id) {
  const result = await query('SELECT * FROM users WHERE id = $1', [id]);
  return result.rows[0] || null;
}

async function getUserByEmail(email) {
  const result = await query('SELECT * FROM users WHERE email = $1', [email]);
  return result.rows[0] || null;
}

async function updateUser(id, updates) {
  const keys = Object.keys(updates);
  const values = Object.values(updates);
  const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
  const result = await query(
    `UPDATE users SET ${setClause}, updated_at = NOW() WHERE id = $1 RETURNING *`,
    [id, ...values]
  );
  return result.rows[0];
}

async function createRoom(roomData) {
  const result = await query(
    `INSERT INTO rooms (code, name, host_id, host_pub, capacity, team_size, status, is_public, settings)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *`,
    [
      roomData.code,
      roomData.name,
      roomData.host_id,
      roomData.host_pub ? JSON.stringify(roomData.host_pub) : null,
      roomData.capacity || 2,
      roomData.team_size || 1,
      'waiting',
      roomData.is_public || false,
      JSON.stringify(roomData.settings || { field: 'stadium', ball: 0, matchTime: 300 })
    ]
  );
  return result.rows[0];
}

async function getRoomByCode(code) {
  const result = await query('SELECT * FROM rooms WHERE code = $1', [code]);
  return result.rows[0] || null;
}

async function getPublicRooms() {
  const result = await query(
    "SELECT * FROM rooms WHERE is_public = true AND status = 'waiting' ORDER BY created_at DESC LIMIT 30"
  );
  return result.rows;
}

async function updateRoom(id, updates) {
  const keys = Object.keys(updates);
  const values = Object.values(updates);
  const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
  const result = await query(
    `UPDATE rooms SET ${setClause} WHERE id = $1 RETURNING *`,
    [id, ...values]
  );
  return result.rows[0];
}

async function createMatch(matchData) {
  const result = await query(
    `INSERT INTO matches (room_id, teams, team_size, mode, settings, ranked, status, score)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
    [
      matchData.room_id || null,
      JSON.stringify(matchData.teams || [[], []]),
      matchData.team_size || 1,
      matchData.mode || '1v1',
      JSON.stringify(matchData.settings || { field: 'stadium', ball: 0, matchTime: 300 }),
      matchData.ranked || false,
      'playing',
      JSON.stringify([0, 0])
    ]
  );
  return result.rows[0];
}

async function getMatchById(id) {
  const result = await query('SELECT * FROM matches WHERE id = $1', [id]);
  return result.rows[0] || null;
}

async function updateMatch(id, updates) {
  const keys = Object.keys(updates);
  const values = Object.values(updates);
  const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
  const result = await query(
    `UPDATE matches SET ${setClause} WHERE id = $1 RETURNING *`,
    [id, ...values]
  );
  return result.rows[0];
}

async function addFriend(userId, friendId) {
  const result = await query(
    `INSERT INTO friends (user_id, friend_id, status) VALUES ($1, $2, 'pending')
     ON CONFLICT (user_id, friend_id) DO NOTHING RETURNING *`,
    [userId, friendId]
  );
  return result.rows[0];
}

async function getFriends(userId) {
  const result = await query(
    `SELECT f.*, u.username, u.avatar, u.trophies, u.level
     FROM friends f 
     JOIN users u ON u.id = f.friend_id 
     WHERE (f.user_id = $1 OR f.friend_id = $1) AND f.status = 'accepted'`,
    [userId]
  );
  return result.rows;
}

async function createNotification(notifData) {
  const result = await query(
    `INSERT INTO notifications (user_id, title, body, kind, data) VALUES ($1, $2, $3, $4, $5) RETURNING *`,
    [
      notifData.user_id,
      notifData.title,
      notifData.body || '',
      notifData.kind || 'info',
      JSON.stringify(notifData.data || {})
    ]
  );
  return result.rows[0];
}

async function getNotifications(userId) {
  const result = await query(
    'SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
    [userId]
  );
  return result.rows;
}

module.exports = {
  client,
  connect,
  query,
  createUser,
  getUserById,
  getUserByEmail,
  updateUser,
  createRoom,
  getRoomByCode,
  getPublicRooms,
  updateRoom,
  createMatch,
  getMatchById,
  updateMatch,
  addFriend,
  getFriends,
  createNotification,
  getNotifications
};
