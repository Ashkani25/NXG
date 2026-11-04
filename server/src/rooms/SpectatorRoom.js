'use strict';
const { Room, ServerError } = require('@colyseus/core');

/**
 * SpectatorRoom - Watch ongoing matches without participating
 * 
 * Features:
 * - Join as spectator to any active match
 * - Receive real-time game state updates
 * - No game input allowed (read-only)
 * - Count of spectators broadcasted
 */
class SpectatorRoom extends Room {
  maxClients = 100; // Many spectators allowed
  
  onCreate(options) {
    this.matchId = options.matchId;
    this.setPrivate(true); // Not publicly listed
    
    this.state = {
      matchId: this.matchId,
      status: 'spectating',
      spectators: 0,
      score: [0, 0],
      timeLeft: options.timeLeft || 300,
      teams: options.teams || [[], []]
    };
    
    this.onMessage('chat', (client, data) => {
      // Spectator chat (optional - can be disabled)
      const text = String(data?.text || '').slice(0, 50);
      if (!text) return;
      
      this.broadcast('spectator_chat', {
        id: Date.now() + '' + Math.random(),
        text,
        from: client.userData?.name || 'Spectator',
        t: Date.now()
      }, { except: client });
    });
    
    console.log(`[SpectatorRoom:${this.matchId}] Created`);
  }
  
  onAuth(client, options) {
    // Any user can spectate (no special auth needed)
    // But they should have a valid session
    return {
      name: options?.name || 'Spectator_' + client.sessionId.slice(0, 6)
    };
  }
  
  onJoin(client, options, auth) {
    client.userData = {
      name: auth?.name || 'Spectator'
    };
    
    this.state.spectators++;
    
    client.send('spectate_start', {
      matchId: this.matchId,
      teams: this.state.teams,
      score: this.state.score,
      timeLeft: this.state.timeLeft,
      settings: this.state.settings
    });
    
    console.log(`[SpectatorRoom:${this.matchId}] ${client.userData.name} joined (${this.state.spectators} spectators)`);
  }
  
  onLeave(client) {
    this.state.spectators = Math.max(0, this.state.spectators - 1);
    console.log(`[SpectatorRoom:${this.matchId}] ${client.userData?.name} left (${this.state.spectators} remaining)`);
  }
  
  // Methods called by MatchRoom to sync state to spectators
  updateScore(score) {
    this.state.score = score;
    this.broadcast('score_update', { score });
  }
  
  updateTime(timeLeft) {
    this.state.timeLeft = timeLeft;
    this.broadcast('time_update', { timeLeft });
  }
  
  broadcastGoal(team, scorer) {
    this.broadcast('goal', { team, scorer, score: this.state.score });
  }
  
  broadcastEvent(type, data) {
    this.broadcast('event', { type, ...data });
  }
  
  matchEnded(winner, score) {
    this.state.status = 'ended';
    this.broadcast('match_end', { winner, score });
    
    // Close spectator room after delay
    setTimeout(() => this.disconnect(), 30000);
  }
}

module.exports = SpectatorRoom;
