'use strict';
const { ObjectId } = require('mongodb'), { matchMaker } = require('@colyseus/core'), L = require('../lib'), { C, mutate } = require('../db'), { bad, now } = require('../util'), U = require('./users'), { signTicket } = require('../auth'), economy = require('./economy');

/**
 * Match Service - Handles match creation, reporting, and settlement
 * Supports 1v1, 2v2, 3v3 matches
 */

/**
 * Create a match document and Colyseus match room
 * @param {Object} o - Match options
 * @param {string[]} o.allPlayers - All player IDs in the match
 * @param {number} o.teamSize - Number of players per team (1, 2, or 3)
 * @param {Object} o.settings - Match settings (field, ball, time)
 * @param {boolean} o.ranked - Is this a ranked match
 * @param {string} o.roomCode - Room code if from custom room
 */
async function create(o) {
  const allPlayers = o.allPlayers || [o.a, o.b];
  const teamSize = o.teamSize || 1;
  
  // Get all player info
  const players = await Promise.all(allPlayers.map(uid => U.getUser(uid)));
  
  const _id = new ObjectId().toHexString();
  const hostId = allPlayers[0];
  
  // Build teams
  const teams = [[], []];
  allPlayers.forEach((uid, i) => {
    const teamIndex = i < teamSize ? 0 : 1;
    teams[teamIndex].push(uid);
  });
  
  // Merge settings with defaults
  const settings = Object.assign({
    field: players[0]?.equip?.field || 'stadium',
    ball: players[0]?.equip?.ball || 0,
    matchTime: 300,
    turnTime: 15
  }, o.settings || {});
  
  // Create match document
  const doc = {
    _id,
    v: 0,
    players: allPlayers,
    teams,
    teamSize,
    hostId,
    pub: {},
    settings,
    ranked: !!o.ranked,
    friendly: !!o.friendly,
    tournamentId: o.tournamentId || null,
    fixtureId: o.fixtureId || null,
    roomCode: o.roomCode || null,
    roomId: o.roomId || null,
    mode: o.mode || '1v1',
    status: 'playing',
    reports: {},
    createdAt: now()
  };
  
  // Add public player info
  for (const p of players) {
    if (p) doc.pub[p._id] = U.pub(p);
  }
  
  await C.matches.insertOne(doc);
  
  // Create Colyseus match room
  const room = await matchMaker.createRoom('match', {
    matchId: _id,
    capacity: teamSize * 2,
    teams,
    settings,
    matchTime: settings.matchTime,
    turnTime: settings.turnTime
  });
  
  // Create seat reservation for each player
  const reservations = {};
  for (const uid of allPlayers) {
    reservations[uid] = await matchMaker.reserveSeatFor(room, {
      uid,
      ticket: signTicket(uid, 'match:' + _id)
    });
  }
  
  console.log(`[Match] Created ${_id} for ${allPlayers.length} players (${teamSize}v${teamSize})`);
  
  return { matchId: _id, doc, reservations };
}

/**
 * Get view of match for a specific player
 */
function viewFor(doc, uid, reservation) {
  const teamIndex = doc.teams?.[0]?.includes(uid) ? 0 : 1;
  const teammates = (doc.teams?.[teamIndex] || []).filter(id => id !== uid);
  const opponents = (doc.teams?.[1 - teamIndex] || []);
  
  return {
    matchId: doc._id,
    role: doc.hostId === uid ? 'host' : 'guest',
    teamIndex,
    teammates: teammates.map(id => doc.pub[id]).filter(Boolean),
    opponents: opponents.map(id => doc.pub[id]).filter(Boolean),
    settings: doc.settings,
    ranked: doc.ranked,
    friendly: doc.friendly,
    tournamentId: doc.tournamentId,
    reservation,
    mode: doc.mode
  };
}

/**
 * Report match result from a player
 */
async function report(uid, d) {
  const goalsFor = Math.max(0, Math.min(99, d.goalsFor | 0));
  const goalsAgainst = Math.max(0, Math.min(99, d.goalsAgainst | 0));
  const won = !!d.won;
  
  let match = null;
  let bot = false;
  let ranked = false;
  let friendly = false;
  let tournament = false;
  let disputed = false;
  
  if (d.matchId) {
    match = await C.matches.findOne({ _id: String(d.matchId) });
    if (!match) throw bad('Match not found', 404);
    if (!match.players.includes(uid)) throw bad('Not your match', 403);
    if (match.reports?.[uid]) throw bad('Already reported');
    
    // Check match age
    const age = (Date.now() - match.createdAt.getTime()) / 1000;
    if (won && age < 60) throw bad('Result rejected (match too short)');
    
    ranked = match.ranked;
    friendly = match.friendly;
    tournament = !!match.tournamentId;
    
    // Check for disputes (opponent reported different score)
    const opponentId = match.players.find(id => id !== uid);
    const opponentReport = match.reports?.[opponentId];
    
    if (opponentReport && (opponentReport.gf !== goalsAgainst || opponentReport.ga !== goalsFor)) {
      disputed = true;
    }
    
    // Store this player's report
    const result = await C.matches.updateOne(
      { _id: match._id, [`reports.${uid}`]: { $exists: false } },
      { 
        $set: { 
          [`reports.${uid}`]: { 
            gf: goalsFor, 
            ga: goalsAgainst, 
            won, 
            t: now() 
          },
          ...(disputed ? { disputed: true } : {})
        }
      }
    );
    
    if (!result.matchedCount) throw bad('Already reported');
  } else if (d.mode === 'bot') {
    bot = true;
  } else {
    throw bad('Missing matchId');
  }
  
  // Calculate rewards and update user
  const out = await mutate(C.users, uid, u => {
    // Get opponent's trophy count for ELO calculation
    let oppTr = null;
    if (match && !bot) {
      const opponentId = match.players.find(id => id !== uid);
      const oppDoc = match.pub?.[opponentId];
      if (oppDoc) oppTr = oppDoc.trophies || 0;
    }
    if (oppTr == null) oppTr = u.trophies;
    
    // Bot match limits
    if (bot) {
      const b = u.bots?.date === L.today() ? u.bots : { date: L.today(), n: 0 };
      if (b.n >= 15) {
        return { 
          xp: 0, coins: 0, trophies: 0, totalTrophies: u.trophies, 
          level: u.level, levelUp: false, levelsGained: 0, 
          xpNow: u.xp, levelBefore: u.level, 
          note: 'Daily bot reward limit reached' 
        };
      }
      u.bots = { date: b.date, n: b.n + 1 };
    }
    
    // Calculate rewards
    const rw = L.matchRewards({ won, gf: goalsFor, ranked, friendly, tournament, bot });
    
    // Trophy change for ranked matches
    let trophyDelta = 0;
    if (ranked && !disputed && oppTr != null) {
      trophyDelta = L.trophyDelta(u.trophies, oppTr, won);
    }
    
    const newTrophies = Math.max(0, u.trophies + trophyDelta);
    trophyDelta = newTrophies - u.trophies;
    const beforeLevel = u.level;
    
    // Update stats
    u.stats.played++;
    u.stats.goals += goalsFor;
    u.stats.conceded += goalsAgainst;
    
    if (won) {
      u.stats.wins++;
      u.stats.streak++;
      u.stats.best = Math.max(u.stats.best, u.stats.streak);
    } else {
      u.stats.losses++;
      u.stats.streak = 0;
    }
    
    // XP and level up
    const levelsGained = disputed ? 0 : L.addXp(u, rw.xp);
    
    // Add coins (not for disputed results)
    if (!disputed) u.coins += rw.coins;
    
    // Update trophies
    u.trophies = newTrophies;
    
    // Ensure daily quests exist
    economy.ensureQuests(u);
    
    // Update quest progress
    for (const q of u.quests?.list || []) {
      if (q.type === 'play') q.have = Math.min(q.need, q.have + 1);
      if (q.type === 'win' && won) q.have = Math.min(q.need, q.have + 1);
      if (q.type === 'goals') q.have = Math.min(q.need, q.have + goalsFor);
    }
    
    return {
      xp: disputed ? 0 : rw.xp,
      coins: disputed ? 0 : rw.coins,
      trophies: trophyDelta,
      totalTrophies: newTrophies,
      level: u.level,
      levelUp: levelsGained > 0,
      levelsGained,
      xpNow: u.xp,
      levelBefore: beforeLevel,
      disputed
    };
  });
  
  // Try to settle the match if all reports are in
  if (match) {
    settle(match._id).catch(e => console.error('settle error', e));
  }
  
  return out;
}

/**
 * Settle match when all players have reported
 */
async function settle(matchId) {
  const m = await C.matches.findOne({ _id: matchId });
  if (!m || m.settled) return null;
  
  const totalPlayers = m.players.length;
  const requiredReports = totalPlayers;
  const receivedReports = Object.keys(m.reports || {}).length;
  
  // Not enough reports yet
  if (receivedReports < requiredReports) return null;
  
  // Calculate final result
  let team0Score = 0;
  let team1Score = 0;
  
  for (const [uid, report] of Object.entries(m.reports)) {
    const teamIndex = m.teams?.[0]?.includes(uid) ? 0 : 1;
    if (teamIndex === 0) {
      team0Score += report.gf;
    } else {
      team1Score += report.ga;
    }
  }
  
  // Determine winner
  let winner = null;
  if (team0Score > team1Score) winner = 0;
  else if (team1Score > team0Score) winner = 1;
  
  // Update match as settled
  const result = await C.matches.updateOne(
    { _id: matchId, settled: { $ne: true } },
    { 
      $set: { 
        settled: true, 
        winner,
        team0Score,
        team1Score,
        status: 'done' 
      } 
    }
  );
  
  if (!result.matchedCount) return null;
  
  // Notify room if exists
  if (m.roomId) {
    try {
      await matchMaker.remoteRoomCall(m.roomId, 'matchDone');
    } catch (e) {}
  }
  
  // Notify tournament if exists
  if (m.tournamentId) {
    try {
      const T = require('./tournaments');
      const winnerId = winner !== null ? m.teams[winner][0] : null;
      T.result(m.tournamentId, m.fixtureId, winnerId, m.teams[0][0], m.teams[1][0], team0Score, team1Score);
    } catch (e) {}
  }
  
  console.log(`[Match] Settled ${matchId}: Team 0 (${team0Score}) vs Team 1 (${team1Score}), Winner: ${winner}`);
  
  return { win: winner, sa: team0Score, sb: team1Score };
}

/**
 * Forfeit match when player disconnects/leaves
 */
async function forfeit(matchId, uid) {
  await C.matches.updateOne(
    { _id: matchId, [`reports.${uid}`]: { $exists: false } },
    { 
      $set: { 
        [`reports.${uid}`]: { 
          gf: 0, 
          ga: 0, 
          won: false, 
          forfeit: true, 
          t: now() 
        } 
      } 
    }
  );
  
  return settle(matchId);
}

module.exports = { create, viewFor, report, settle, forfeit };
