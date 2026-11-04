'use strict';
const { matchMaker } = require('@colyseus/core'), L = require('../lib'), SB = require('../supabase'), { bad, now } = require('../util'), U = require('./users'), { signTicket } = require('../auth'), economy = require('./economy');

/**
 * Match Service - Handles match creation, reporting, and settlement
 * Supports 1v1, 2v2, 3v3 matches using Supabase
 */

/**
 * Create a match document and Colyseus match room
 */
async function create(o) {
  const allPlayers = o.allPlayers || [o.a, o.b];
  const teamSize = o.teamSize || 1;
  
  // Get all player info
  const players = await Promise.all(allPlayers.map(uid => SB.getUserById(uid)));
  
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
  
  // Create match document in Supabase
  const matchData = {
    room_id: o.roomId || null,
    teams: teams,
    team_size: teamSize,
    mode: o.mode || (teamSize === 1 ? '1v1' : teamSize === 2 ? '2v2' : '3v3'),
    settings: settings,
    ranked: !!o.ranked,
    status: 'playing',
    reports: {},
    score: [0, 0],
    team0_score: 0,
    team1_score: 0
  };
  
  const doc = await SB.createMatch(matchData);
  
  // Create Colyseus match room
  const room = await matchMaker.createRoom('match', {
    matchId: doc.id,
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
      ticket: signTicket(uid, 'match:' + doc.id)
    });
  }
  
  console.log(`[Match] Created ${doc.id} for ${allPlayers.length} players (${teamSize}v${teamSize})`);
  
  return { matchId: doc.id, doc, reservations };
}

/**
 * Get view of match for a specific player
 */
function viewFor(doc, uid, reservation) {
  const teamIndex = doc.teams?.[0]?.includes(uid) ? 0 : 1;
  const teammates = (doc.teams?.[teamIndex] || []).filter(id => id !== uid);
  const opponents = (doc.teams?.[1 - teamIndex] || []);
  
  return {
    matchId: doc.id,
    role: 'guest',
    teamIndex,
    teammates: teammates,
    opponents: opponents,
    settings: doc.settings,
    ranked: doc.ranked,
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
  let disputed = false;
  
  if (d.matchId) {
    match = await SB.getMatchById(d.matchId);
    if (!match) throw bad('Match not found', 404);
    
    const allPlayers = [...(match.teams?.[0] || []), ...(match.teams?.[1] || [])];
    if (!allPlayers.includes(uid)) throw bad('Not your match', 403);
    if (match.reports?.[uid]) throw bad('Already reported');
    
    // Check match age
    const createdAt = new Date(match.created_at);
    const age = (Date.now() - createdAt.getTime()) / 1000;
    if (won && age < 60) throw bad('Result rejected (match too short)');
    
    ranked = match.ranked || false;
    
    // Check for disputes
    const opponentId = Object.keys(match.reports || {}).find(id => id !== uid);
    if (opponentId) {
      const oppReport = match.reports[opponentId];
      if (oppReport && (oppReport.gf !== goalsAgainst || oppReport.ga !== goalsFor)) {
        disputed = true;
      }
    }
    
    // Update match reports
    const updatedReports = { ...match.reports, [uid]: { gf: goalsFor, ga: goalsAgainst, won, t: now() } };
    await SB.supabase.from('matches').update({ reports: updatedReports }).eq('id', match.id);
    
  } else if (d.mode === 'bot') {
    bot = true;
  } else {
    throw bad('Missing matchId');
  }
  
  // Calculate rewards and update user
  const out = await mutateUser(u => {
    let oppTr = null;
    if (match && !bot) {
      const opponentId = [...(match.teams?.[0] || []), ...(match.teams?.[1] || [])].find(id => id !== uid);
      if (oppTr == null) oppTr = u.trophies || 0;
    }
    if (oppTr == null) oppTr = u.trophies;
    
    if (bot) {
      const b = u.bots?.date === L.today() ? u.bots : { date: L.today(), n: 0 };
      if (b.n >= 15) {
        return { 
          xp: 0, coins: 0, trophies: 0, totalTrophies: u.trophies, 
          level: u.level, levelUp: false, levelsGained: 0, 
          note: 'Daily bot reward limit reached' 
        };
      }
      u.bots = { date: b.date, n: b.n + 1 };
    }
    
    const rw = L.matchRewards({ won, gf: goalsFor, ranked, friendly: !ranked, tournament: false, bot });
    
    let trophyDelta = 0;
    if (ranked && !disputed && oppTr != null) {
      trophyDelta = L.trophyDelta(u.trophies, oppTr, won);
    }
    
    const newTrophies = Math.max(0, u.trophies + trophyDelta);
    trophyDelta = newTrophies - u.trophies;
    
    u.stats = u.stats || { played: 0, wins: 0, losses: 0, goals: 0, conceded: 0, streak: 0, best: 0 };
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
    
    const levelsGained = disputed ? 0 : L.addXp(u, rw.xp);
    
    if (!disputed) u.coins += rw.coins;
    u.trophies = newTrophies;
    
    economy.ensureQuests(u);
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
      disputed
    };
  }, uid);
  
  // Try to settle the match if all reports are in
  if (match) {
    settle(match.id).catch(e => console.error('settle error', e));
  }
  
  return out;
}

async function mutateUser(fn, uid) {
  const u = await SB.getUserById(uid);
  if (!u) throw bad('User not found', 404);
  
  const result = fn(u);
  
  await SB.updateUser(uid, {
    stats: u.stats,
    coins: u.coins,
    trophies: u.trophies,
    xp: u.xp,
    level: u.level,
    quests: u.quests,
    bots: u.bots
  });
  
  return result;
}

/**
 * Settle match when all players have reported
 */
async function settle(matchId) {
  const m = await SB.getMatchById(matchId);
  if (!m || m.settled) return null;
  
  const totalPlayers = [...(m.teams?.[0] || []), ...(m.teams?.[1] || [])].length;
  const receivedReports = Object.keys(m.reports || {}).length;
  
  if (receivedReports < totalPlayers) return null;
  
  let team0Score = 0;
  let team1Score = 0;
  
  for (const [uid, report] of Object.entries(m.reports)) {
    const teamIndex = m.teams?.[0]?.includes(uid) ? 0 : 1;
    if (teamIndex === 0) team0Score += report.gf;
    else team1Score += report.ga;
  }
  
  let winner = null;
  if (team0Score > team1Score) winner = 0;
  else if (team1Score > team0Score) winner = 1;
  
  await SB.updateMatch(matchId, {
    settled: true,
    winner,
    team0_score: team0Score,
    team1_score: team1Score,
    status: 'done',
    finished_at: new Date().toISOString()
  });
  
  console.log(`[Match] Settled ${matchId}: Team 0 (${team0Score}) vs Team 1 (${team1Score}), Winner: ${winner}`);
  
  return { win: winner, sa: team0Score, sb: team1Score };
}

/**
 * Forfeit match when player disconnects/leaves
 */
async function forfeit(matchId, uid) {
  const m = await SB.getMatchById(matchId);
  if (!m) return null;
  
  const updatedReports = { ...m.reports, [uid]: { gf: 0, ga: 0, won: false, forfeit: true, t: now() } };
  await SB.supabase.from('matches').update({ reports: updatedReports }).eq('id', matchId);
  
  return settle(matchId);
}

module.exports = { create, viewFor, report, settle, forfeit };