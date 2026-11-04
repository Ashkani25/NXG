'use strict';
const { ObjectId } = require('mongodb'), L = require('../lib'), { C } = require('../db'), { bad, clean, now } = require('../util');
const shortId = id => 'NX-' + id.slice(-6).toUpperCase();
function newUser({ email, passHash, googleId, guest, name }) { const _id = new ObjectId().toHexString(); name = clean(name, 16) || 'Player' + L.rnd(1000, 9999);
  return { _id, v: 0, email: email || undefined, passHash: passHash || undefined, googleId: googleId || undefined, guest: !!guest, name, nameLower: name.toLowerCase(), shortId: shortId(_id), avatar: 'club0', team: 'club0', form: 0, level: 1, trophies: 0, bio: '', country: '',
    followers: 0, following: 0, likes: 0, stats: { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 }, equip: { ball: 4, field: 'stadium' },
    coins: 1500, gems: 20, xp: 0, owned: { balls: L.FREE_BALLS.slice(), fields: L.FREE_FIELDS.slice(), teams: [L.VIP_FREE] }, daily: { day: 0, last: '' }, quests: L.newQuests(), bots: { date: '', n: 0 }, ai: { date: '', n: 0 }, createdAt: now() } }
const pub = u => ({ id: u._id, name: u.name, avatar: u.avatar, team: u.team, form: u.form || 0, level: u.level, trophies: u.trophies, bio: u.bio || '', country: u.country || '', stats: u.stats, followers: u.followers || 0, following: u.following || 0, likes: u.likes || 0, shortId: u.shortId });
const me = u => Object.assign(pub(u), { coins: u.coins, gems: u.gems, xp: u.xp, xpNeed: L.XP_NEED(u.level), owned: u.owned, equip: u.equip, daily: u.daily, quests: u.quests, email: u.email || null, guest: !!u.guest, created: u.createdAt && u.createdAt.getTime ? u.createdAt.getTime() : 0 });
/* every non-mutate write to a user doc must bump v so optimistic transactions notice it */
const bump = (uid, inc) => C.users.updateOne({ _id: uid }, { $inc: Object.assign({ v: 1 }, inc || {}) });
const getUser = async id => { const u = await C.users.findOne({ _id: String(id) }, { projection: { passHash: 0 } }); if (!u) throw bad('Player not found', 404); return u };
module.exports = { newUser, pub, me, bump, getUser };
