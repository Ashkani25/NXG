'use strict';

/**
 * Supabase PostgreSQL Client for BERMUDA NXG
 * 
 * Database schema for multiplayer football game
 */

const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://cqbtbgdkgmcbhaoktcwy.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxYnRiZ2RrZ21jYmhhb2t0Y3d5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5Mzc5ODY5OCwiZXhwIjoyMTA5Mzc0Njk4fQ.MtGfRTRX7M5zH3J_P7TROvBcPvUyQXyFwQ_33CDoTuQ';

const supabase = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  },
  realtime: {
    enabled: false
  }
});

// Database schema initialized manually via Supabase CLI
// No initialization needed - tables already created

// Helper functions
async function createUser(userData) {
  const shortId = 'NX-' + Math.random().toString(36).slice(-6).toUpperCase();
  
  const { data, error } = await supabase
    .from('users')
    .insert({
      email: userData.email || null,
      username: userData.username,
      short_id: shortId,
      avatar: userData.avatar || 'club0',
      team: userData.team || 'club0',
      stats: { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 },
      equip: { ball: 4, field: 'stadium' },
      owned: { balls: [0, 4, 5], fields: ['stadium'], teams: [] },
      quests: { date: new Date().toISOString().slice(0, 10), list: [] }
    })
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function getUserById(id) {
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', id)
    .single();
  
  if (error) return null;
  return data;
}

async function getUserByEmail(email) {
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('email', email)
    .single();
  
  if (error) return null;
  return data;
}

async function updateUser(id, updates) {
  const { data, error } = await supabase
    .from('users')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

// Room functions
async function createRoom(roomData) {
  const { data, error } = await supabase
    .from('rooms')
    .insert(roomData)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function getRoomByCode(code) {
  const { data, error } = await supabase
    .from('rooms')
    .select('*')
    .eq('code', code)
    .single();
  
  if (error) return null;
  return data;
}

async function getPublicRooms() {
  const { data, error } = await supabase
    .from('rooms')
    .select('*')
    .eq('is_public', true)
    .eq('status', 'waiting')
    .order('created_at', { ascending: false })
    .limit(30);
  
  if (error) return [];
  return data || [];
}

async function updateRoom(id, updates) {
  const { data, error } = await supabase
    .from('rooms')
    .update(updates)
    .eq('id', id)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

// Match functions
async function createMatch(matchData) {
  const { data, error } = await supabase
    .from('matches')
    .insert(matchData)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function getMatchById(id) {
  const { data, error } = await supabase
    .from('matches')
    .select('*')
    .eq('id', id)
    .single();
  
  if (error) return null;
  return data;
}

async function updateMatch(id, updates) {
  const { data, error } = await supabase
    .from('matches')
    .update(updates)
    .eq('id', id)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function updateMatchReport(matchId, userId, report) {
  const { data: existing } = await supabase
    .from('match_reports')
    .select('id')
    .eq('match_id', matchId)
    .eq('user_id', userId)
    .single();
  
  if (existing) {
    // Update existing report
    const { data, error } = await supabase
      .from('match_reports')
      .update(report)
      .eq('id', existing.id)
      .select()
      .single();
    
    if (error) throw error;
    return data;
  } else {
    // Create new report
    const { data, error } = await supabase
      .from('match_reports')
      .insert({ match_id: matchId, user_id: userId, ...report })
      .select()
      .single();
    
    if (error) throw error;
    return data;
  }
}

// Friends functions
async function addFriend(userId, friendId) {
  const { data, error } = await supabase
    .from('friends')
    .insert({ user_id: userId, friend_id: friendId, status: 'pending' })
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function getFriends(userId) {
  const { data, error } = await supabase
    .from('friends')
    .select('*, friend:users!friends_friend_id_fkey(*)')
    .or(`user_id.eq.${userId},friend_id.eq.${userId}`)
    .eq('status', 'accepted');
  
  if (error) return [];
  return data || [];
}

// Notification functions
async function createNotification(notifData) {
  const { data, error } = await supabase
    .from('notifications')
    .insert(notifData)
    .select()
    .single();
  
  if (error) throw error;
  return data;
}

async function getNotifications(userId) {
  const { data, error } = await supabase
    .from('notifications')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(50);
  
  if (error) return [];
  return data || [];
}

// Session functions
async function createSession(userId) {
  const token = require('crypto').randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + 60 * 24 * 60 * 60 * 1000); // 60 days
  
  const { data, error } = await supabase
    .from('sessions')
    .insert({
      user_id: userId,
      token,
      expires_at: expiresAt.toISOString()
    })
    .select()
    .single();
  
  if (error) throw error;
  return { ...data, user_id: userId };
}

async function verifySession(token) {
  const { data, error } = await supabase
    .from('sessions')
    .select('*, user:users(*)')
    .eq('token', token)
    .gt('expires_at', new Date().toISOString())
    .single();
  
  if (error || !data) return null;
  return data;
}

module.exports = {
  supabase,
  initializeDatabase,
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
  updateMatchReport,
  addFriend,
  getFriends,
  createNotification,
  getNotifications,
  createSession,
  verifySession
};
