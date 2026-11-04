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
  }
});

// Database schema initialization
async function initializeDatabase() {
  console.log('[Supabase] Initializing database schema...');
  
  // Create users table
  const { error: usersError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email TEXT UNIQUE,
        username TEXT NOT NULL,
        username_lower TEXT GENERATED ALWAYS AS (LOWER(username)) STORED,
        short_id TEXT UNIQUE,
        avatar TEXT DEFAULT 'club0',
        team TEXT DEFAULT 'club0',
        form INTEGER DEFAULT 0,
        level INTEGER DEFAULT 1,
        xp INTEGER DEFAULT 0,
        trophies INTEGER DEFAULT 0,
        bio TEXT DEFAULT '',
        country TEXT DEFAULT '',
        stats JSONB DEFAULT '{"played":0,"wins":0,"losses":0,"goals":0,"conceded":0,"streak":0,"best":0}',
        coins INTEGER DEFAULT 1500,
        gems INTEGER DEFAULT 20,
        equip JSONB DEFAULT '{"ball":4,"field":"stadium"}',
        owned JSONB DEFAULT '{"balls":[0,4,5],"fields":["stadium"],"teams":[]}',
        quests JSONB DEFAULT '{"date":"","list":[]}',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        v INTEGER DEFAULT 0
      );
    `
  });
  
  if (usersError) console.log('[Supabase] Users table (may exist):', usersError.message);
  
  // Create sessions table
  const { error: sessionsError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        token TEXT UNIQUE NOT NULL,
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `
  });
  
  if (sessionsError) console.log('[Supabase] Sessions table (may exist):', sessionsError.message);
  
  // Create rooms table
  const { error: roomsError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS rooms (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        host_id UUID REFERENCES users(id),
        capacity INTEGER DEFAULT 2,
        team_size INTEGER DEFAULT 1,
        status TEXT DEFAULT 'waiting',
        is_public BOOLEAN DEFAULT false,
        settings JSONB DEFAULT '{"field":"stadium","ball":0,"matchTime":300}',
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `
  });
  
  if (roomsError) console.log('[Supabase] Rooms table (may exist):', roomsError.message);
  
  // Create matches table
  const { error: matchesError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS matches (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        room_id UUID REFERENCES rooms(id),
        teams JSONB NOT NULL,
        team_size INTEGER DEFAULT 1,
        mode TEXT DEFAULT '1v1',
        score INTEGER[] DEFAULT '{0,0}',
        team0_score INTEGER DEFAULT 0,
        team1_score INTEGER DEFAULT 0,
        settings JSONB DEFAULT '{"field":"stadium","ball":0,"matchTime":300}',
        status TEXT DEFAULT 'playing',
        winner INTEGER,
        ranked BOOLEAN DEFAULT false,
        reports JSONB DEFAULT '{}',
        settled BOOLEAN DEFAULT false,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        finished_at TIMESTAMPTZ
      );
    `
  });
  
  if (matchesError) console.log('[Supabase] Matches table (may exist):', matchesError.message);
  
  // Create match_reports table
  const { error: reportsError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS match_reports (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        match_id UUID REFERENCES matches(id) ON DELETE CASCADE,
        user_id UUID REFERENCES users(id),
        goals_for INTEGER DEFAULT 0,
        goals_against INTEGER DEFAULT 0,
        won BOOLEAN DEFAULT false,
        forfeit BOOLEAN DEFAULT false,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `
  });
  
  if (reportsError) console.log('[Supabase] Match reports table (may exist):', reportsError.message);
  
  // Create friends table
  const { error: friendsError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS friends (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        friend_id UUID REFERENCES users(id) ON DELETE CASCADE,
        status TEXT DEFAULT 'pending',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(user_id, friend_id)
      );
    `
  });
  
  if (friendsError) console.log('[Supabase] Friends table (may exist):', friendsError.message);
  
  // Create direct_messages table
  const { error: dmError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS direct_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        sender_id UUID REFERENCES users(id),
        receiver_id UUID REFERENCES users(id),
        text TEXT NOT NULL,
        read BOOLEAN DEFAULT false,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `
  });
  
  if (dmError) console.log('[Supabase] Direct messages table (may exist):', dmError.message);
  
  // Create notifications table
  const { error: notifError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        body TEXT,
        kind TEXT,
        data JSONB DEFAULT '{}',
        read BOOLEAN DEFAULT false,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `
  });
  
  if (notifError) console.log('[Supabase] Notifications table (may exist):', notifError.message);
  
  // Create tournaments table
  const { error: tourneyError } = await supabase.rpc('exec', {
    query: `
      CREATE TABLE IF NOT EXISTS tournaments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        capacity INTEGER DEFAULT 8,
        status TEXT DEFAULT 'registration',
        bracket JSONB DEFAULT '{}',
        settings JSONB DEFAULT '{}',
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT NOW(),
        starts_at TIMESTAMPTZ
      );
    `
  });
  
  if (tourneyError) console.log('[Supabase] Tournaments table (may exist):', tourneyError.message);
  
  // Create indexes for performance
  await supabase.rpc('exec', {
    query: `
      CREATE INDEX IF NOT EXISTS idx_users_username ON users(username_lower);
      CREATE INDEX IF NOT EXISTS idx_users_trophies ON users(trophies DESC);
      CREATE INDEX IF NOT EXISTS idx_rooms_code ON rooms(code);
      CREATE INDEX IF NOT EXISTS idx_rooms_status ON rooms(status);
      CREATE INDEX IF NOT EXISTS idx_matches_room ON matches(room_id);
      CREATE INDEX IF NOT EXISTS idx_matches_created ON matches(created_at);
      CREATE INDEX IF NOT EXISTS idx_friends_user ON friends(user_id);
      CREATE INDEX IF NOT EXISTS idx_dm_sender ON direct_messages(sender_id);
      CREATE INDEX IF NOT EXISTS idx_dm_receiver ON direct_messages(receiver_id);
      CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id);
    `
  }).catch(() => {}); // Indexes may already exist
  
  console.log('[Supabase] Database schema initialized!');
}

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
