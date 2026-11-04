'use strict';
const L = require('../lib'), SB = require('../supabase'), { bad, clean, now } = require('../util');

function newUser({ email, passHash, guest, name }) { 
  name = clean(name, 16) || 'Player' + L.rnd(1000, 9999);
  return { 
    email: email || null, 
    passHash: passHash || null, 
    guest: !!guest, 
    name, 
    avatar: 'club0', 
    team: 'club0', 
    form: 0, 
    level: 1, 
    trophies: 0, 
    bio: '', 
    country: '',
    followers: 0, 
    following: 0, 
    likes: 0, 
    stats: { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 }, 
    equip: { ball: 4, field: 'stadium' },
    coins: 1500, 
    gems: 20, 
    xp: 0, 
    owned: { balls: L.FREE_BALLS.slice(), fields: L.FREE_FIELDS.slice(), teams: [L.VIP_FREE] }, 
    daily: { day: 0, last: '' }, 
    quests: L.newQuests(), 
    bots: { date: '', n: 0 }, 
    ai: { date: '', n: 0 }
  };
}

const pub = u => ({ 
  id: u.id, 
  name: u.username || u.name, 
  avatar: u.avatar, 
  team: u.team, 
  form: u.form || 0, 
  level: u.level, 
  trophies: u.trophies, 
  bio: u.bio || '', 
  country: u.country || '', 
  stats: u.stats, 
  followers: u.followers || 0, 
  following: u.following || 0, 
  likes: u.likes || 0, 
  shortId: u.short_id 
});

const me = u => Object.assign(pub(u), { 
  coins: u.coins, 
  gems: u.gems, 
  xp: u.xp, 
  xpNeed: L.XP_NEED(u.level), 
  owned: u.owned, 
  equip: u.equip, 
  daily: u.daily, 
  quests: u.quests, 
  email: u.email || null, 
  guest: !!u.guest, 
  created: u.created_at ? new Date(u.created_at).getTime() : 0 
});

const bump = async (uid, inc) => {
  const updates = {};
  for (const [k, v] of Object.entries(inc || {})) updates[k] = v;
  await SB.updateUser(uid, updates);
};

const getUser = async id => { 
  const u = await SB.getUserById(String(id)); 
  if (!u) throw bad('Player not found', 404); 
  return u; 
};

module.exports = { newUser, pub, me, bump, getUser };