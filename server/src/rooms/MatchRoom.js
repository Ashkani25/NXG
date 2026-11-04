'use strict';
const { Room, ServerError } = require('@colyseus/core'), { verifyTicket } = require('../auth'), { C } = require('../db'), MM = require('../services/match');
const cfg = require('../config');

/**
 * MatchRoom - Authoritative match room for 2/4/6 players
 * 
 * Features:
 * - Server-authoritative timer
 * - Shot validation
 * - Goal detection and scoring
 * - Score synchronization
 * - Disconnect/reconnect handling
 * - Match result reporting
 */
class MatchRoom extends Room {
  // Dynamic capacity based on match settings
  maxClients = 6;
  
  onCreate(options) {
    this.matchId = options.matchId;
    this.maxClients = options.capacity || 2;
    this.teamSize = (options.capacity || 2) / 2;
    
    // Load match document from database
    this.match = null;
    this.clients = new Map(); // sessionId -> client info
    
    this.state = {
      matchId: this.matchId,
      status: 'loading', // loading, countdown, playing, paused, finished
      score: [0, 0],
      timeLeft: options.matchTime || 300,
      turn: 0, // Which team's turn (0 or 1)
      turnTimeLeft: options.turnTime || 15,
      teams: options.teams || [[], []],
      settings: options.settings || {},
      spectators: 0,
      events: [] // Goal events, etc.
    };
    
    // Set private (not listed) - clients join via reservation
    this.setPrivate(true);
    
    // Relay messages from clients (validates and broadcasts)
    this.onMessage('shot', (client, data) => this.handleShot(client, data));
    this.onMessage('settled', (client, data) => this.handleSettled(client, data));
    this.onMessage('goal', (client, data) => this.handleGoal(client, data));
    this.onMessage('timeout', (client) => this.handleTimeout(client));
    this.onMessage('emote', (client, data) => this.handleEmote(client, data));
    this.onMessage('ready', (client) => this.handleReady(client));
    this.onMessage('pause', (client) => this.handlePause(client));
    
    // Match timer - broadcast every second
    this.clock.setInterval(() => {
      if (this.state.status === 'playing') {
        this.state.timeLeft = Math.max(0, this.state.timeLeft - 1);
        this.state.turnTimeLeft = Math.max(0, this.state.turnTimeLeft - 1);
        
        if (this.state.timeLeft <= 0) {
          this.endMatch();
        } else if (this.state.turnTimeLeft <= 0) {
          // Turn timeout - auto-skip
          this.nextTurn();
        }
        
        this.broadcast('clock', { 
          timeLeft: this.state.timeLeft,
          turnTimeLeft: this.state.turnTimeLeft,
          turn: this.state.turn
        });
      }
    }, 1000);
    
    this.autoDispose = false; // Keep room after match ends for results
    console.log(`[MatchRoom:${this.matchId}] Created, capacity: ${this.maxClients}`);
  }
  
  async onAuth(client, options) {
    const ticket = options?.ticket;
    if (!ticket) throw new ServerError(403, 'Missing ticket');
    
    const uid = verifyTicket(ticket, 'match:' + this.matchId);
    if (!uid) throw new ServerError(403, 'Invalid match ticket');
    
    // Verify this user is in the match
    if (!this.match?.players.includes(uid)) {
      throw new ServerError(403, 'Not your match');
    }
    
    const user = await C.users.findOne({ _id: uid }, { projection: { passHash: 0 } });
    if (!user) throw new ServerError(404, 'Player not found');
    
    return { uid, pub: {
      id: user._id,
      name: user.name,
      team: this.getTeamForPlayer(uid),
      level: user.level,
      trophies: user.trophies
    }};
  }
  
  onJoin(client, options, auth) {
    const authData = auth || client.auth || {};
    const uid = authData.uid || client.sessionId;
    
    this.clients.set(client.sessionId, {
      uid,
      name: authData.pub?.name || 'Player',
      team: authData.pub?.team || 0,
      connected: true,
      ready: false
    });
    
    // Add to teams if not already there
    const team = authData.pub?.team || 0;
    if (!this.state.teams[team].includes(uid)) {
      this.state.teams[team].push(uid);
    }
    
    // Check if all players joined
    const expectedPlayers = this.maxClients;
    if (this.clients.size >= expectedPlayers && this.state.status === 'loading') {
      this.startCountdown();
    }
    
    console.log(`[MatchRoom:${this.matchId}] ${authData.pub?.name} joined team ${team}`);
  }
  
  onLeave(client, consented) {
    const clientInfo = this.clients.get(client.sessionId);
    if (!clientInfo) return;
    
    clientInfo.connected = false;
    
    if (!consented) {
      // Try to reconnect within 15 seconds
      this.allowReconnection(client, 15);
      return;
    }
    
    // Permanent leave - check if match can continue
    const stillConnected = [...this.clients.values()].filter(c => c.connected).length;
    if (stillConnected < 2) {
      this.handleMatchAbandon();
    }
  }
  
  handleShot(client, data) {
    // Validate shot data
    if (!data || typeof data.power !== 'number' || typeof data.angle !== 'number') {
      return;
    }
    
    // Relay shot to other players
    this.broadcast('shot', {
      uid: client.auth?.uid || client.sessionId,
      team: this.clients.get(client.sessionId)?.team,
      power: Math.max(0, Math.min(100, data.power)),
      angle: data.angle,
      t: Date.now()
    }, { except: client });
  }
  
  handleSettled(client, data) {
    // Ball settled after shot
    this.broadcast('settled', {
      uid: client.auth?.uid || client.sessionId,
      position: data?.position,
      t: Date.now()
    }, { except: client });
  }
  
  handleGoal(client, data) {
    // Goal scored - validated by server (not client)
    const team = data?.team ?? this.clients.get(client.sessionId)?.team;
    if (team === undefined) return;
    
    const scoringTeam = team; // Which team scored
    const concedingTeam = 1 - scoringTeam;
    
    this.state.score[scoringTeam]++;
    this.state.events.push({
      type: 'goal',
      team: scoringTeam,
      scorer: client.auth?.uid || client.sessionId,
      score: [...this.state.score],
      t: Date.now()
    });
    
    this.broadcast('goal', {
      team: scoringTeam,
      score: this.state.score,
      scorer: client.auth?.uid || client.sessionId
    });
    
    // Check for match end (sudden death - next goal wins if tied at time)
    if (this.state.timeLeft <= 0) {
      if (this.state.score[0] !== this.state.score[1]) {
        this.endMatch();
      }
      // If tied, continue with sudden death
    }
  }
  
  handleTimeout(client) {
    // Player ran out of time for their turn
    this.nextTurn();
  }
  
  handleEmote(client, data) {
    const text = String(data?.text || '').slice(0, 50);
    if (!text) return;
    
    this.broadcast('emote', {
      uid: client.auth?.uid || client.sessionId,
      text,
      t: Date.now()
    });
  }
  
  handleReady(client) {
    const clientInfo = this.clients.get(client.sessionId);
    if (clientInfo) {
      clientInfo.ready = true;
    }
    
    // Check if all players are ready
    const allReady = [...this.clients.values()].every(c => c.connected && c.ready);
    if (allReady && this.state.status === 'paused') {
      this.resumeMatch();
    }
  }
  
  handlePause(client) {
    // Only allow pause if configured and not during sudden death
    if (this.state.timeLeft > 30) {
      this.state.status = 'paused';
      this.broadcast('paused', { by: client.auth?.uid });
    }
  }
  
  nextTurn() {
    this.state.turn = 1 - this.state.turn;
    this.state.turnTimeLeft = this.state.settings?.turnTime || 15;
    
    this.broadcast('turn_change', {
      turn: this.state.turn,
      turnTimeLeft: this.state.turnTimeLeft
    });
  }
  
  startCountdown() {
    this.state.status = 'countdown';
    this.broadcast('countdown', { duration: 3 });
    
    setTimeout(() => {
      if (this.state.status === 'countdown') {
        this.state.status = 'playing';
        this.broadcast('match_start', { timeLeft: this.state.timeLeft });
      }
    }, 3000);
  }
  
  resumeMatch() {
    this.state.status = 'playing';
    this.broadcast('match_resumed', {});
  }
  
  endMatch() {
    if (this.state.status === 'finished') return;
    
    this.state.status = 'finished';
    
    // Determine winner
    let winner = null;
    if (this.state.score[0] > this.state.score[1]) {
      winner = 0;
    } else if (this.state.score[1] > this.state.score[0]) {
      winner = 1;
    }
    
    this.broadcast('match_end', {
      score: this.state.score,
      winner,
      reason: 'time'
    });
    
    // Report results to database
    this.reportResults();
    
    // Close room after delay
    setTimeout(() => {
      this.disconnect();
    }, 10000);
  }
  
  handleMatchAbandon() {
    this.state.status = 'finished';
    
    const connectedClients = [...this.clients.values()].filter(c => c.connected);
    if (connectedClients.length === 0) {
      // Everyone left - no result
      this.disconnect();
      return;
    }
    
    // Remaining player wins by forfeit
    const winnerTeam = connectedClients[0].team;
    
    this.broadcast('match_end', {
      score: this.state.score,
      winner: winnerTeam,
      reason: 'forfeit'
    });
    
    this.reportResults(winnerTeam);
    
    setTimeout(() => this.disconnect(), 5000);
  }
  
  async reportResults(forcedWinner = null) {
    try {
      const team0Players = this.state.teams[0];
      const team1Players = this.state.teams[1];
      
      // Report for each player
      for (const uid of [...team0Players, ...team1Players]) {
        const isWinner = forcedWinner !== null 
          ? forcedWinner === (team0Players.includes(uid) ? 0 : 1)
          : winner === (team0Players.includes(uid) ? 0 : 1);
        
        const playerTeam = team0Players.includes(uid) ? 0 : 1;
        const goalsFor = this.state.score[playerTeam];
        const goalsAgainst = this.state.score[1 - playerTeam];
        
        await MM.report(uid, {
          matchId: this.matchId,
          won: isWinner,
          goalsFor,
          goalsAgainst
        });
      }
    } catch (e) {
      console.error('[MatchRoom] Failed to report results:', e);
    }
  }
  
  getTeamForPlayer(uid) {
    if (this.state.teams[0].includes(uid)) return 0;
    if (this.state.teams[1].includes(uid)) return 1;
    return 0;
  }
}

module.exports = MatchRoom;
