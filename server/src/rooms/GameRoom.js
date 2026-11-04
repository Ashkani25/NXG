'use strict';
const { Room, ServerError } = require('@colyseus/core'), { verifyTicket } = require('../auth'), { clean, limit } = require('../util'), U = require('../services/users'), MM = require('../services/match'), { C } = require('../db');
const cfg = require('../config');

/**
 * GameRoom - Multiplayer Room for 2/4/6 players
 * Supports: 1v1, 2v2, 3v3 game modes
 * 
 * Features:
 * - Private/public rooms
 * - Ready system
 * - Host controls (settings, kick, start)
 * - Chat
 * - Spectator mode
 * - Auto-cleanup on disconnect
 */
class GameRoom extends Room {
  // Default to 2 players (1v1), can be configured
  maxClients = 6;
  
  onCreate(options) {
    this.code = options.code || this.generateCode();
    this.hostId = options.hostId;
    this.capacity = options.capacity || 2; // 2, 4, or 6
    this.maxClients = this.capacity;
    
    // Teams configuration
    this.teamSize = this.capacity / 2;
    
    // Room state
    this.state = {
      code: this.code,
      name: options.name || `${options.hostName}'s Room`,
      public: !!options.public,
      status: 'waiting', // waiting, starting, playing, finished
      capacity: this.capacity,
      teamSize: this.teamSize,
      hostId: this.hostId,
      settings: {
        field: options.settings?.field || 'stadium',
        ball: options.settings?.ball || 0,
        matchTime: options.settings?.matchTime || 300,
        turnTime: options.settings?.turnTime || 15
      },
      players: [], // Array of player info
      spectators: [],
      ready: {}, // playerId -> boolean
      matchId: null
    };
    
    this.setMetadata({
      code: this.code,
      name: this.state.name,
      public: this.state.public,
      capacity: this.capacity,
      status: this.state.status,
      hostId: this.hostId,
      settings: this.state.settings
    });
    
    this.setPrivate(!this.state.public);
    
    // Message handlers
    this.onMessage('ready', (client, message) => {
      const playerId = client.userData?.uid || client.sessionId;
      this.state.ready[playerId] = !!message?.ready;
      this.syncState();
    });
    
    this.onMessage('chat', (client, message) => {
      const text = clean(message?.text, 100);
      if (!text || !limit('rc:' + (client.userData?.uid || client.sessionId), 5, 5000)) return;
      this.broadcast('chat', {
        id: Date.now() + '' + Math.random(),
        text,
        t: Date.now(),
        from: {
          id: client.userData?.uid || client.sessionId,
          name: client.userData?.name || 'Anonymous',
          team: client.userData?.team || 0
        }
      }, { except: client });
    });
    
    this.onMessage('update_settings', (client, message) => {
      if (client.userData?.uid !== this.hostId) return;
      if (this.state.status !== 'waiting') return;
      
      if (message?.field) this.state.settings.field = clean(message.field, 30);
      if (message?.ball !== undefined) this.state.settings.ball = Math.max(0, Math.min(35, message.ball));
      if ([180, 300, 420, 600].includes(message?.matchTime)) {
        this.state.settings.matchTime = message.matchTime;
      }
      
      this.state.ready = {}; // Reset ready on settings change
      this.updateMetadata();
      this.syncState();
    });
    
    this.onMessage('start', async (client, message) => {
      if (client.userData?.uid !== this.hostId) {
        client.send('error', { message: 'Only the host can start the match' });
        return;
      }
      
      if (this.state.status !== 'waiting') {
        client.send('error', { message: 'Match already started' });
        return;
      }
      
      const readyCount = Object.values(this.state.ready).filter(Boolean).length;
      if (readyCount < this.capacity) {
        client.send('error', { message: 'Not all players are ready' });
        return;
      }
      
      try {
        await this.startMatch();
      } catch (e) {
        client.send('error', { message: e.message });
      }
    });
    
    this.onMessage('leave', (client) => {
      this.handleLeave(client);
    });
    
    this.onMessage('kick', (client, message) => {
      if (client.userData?.uid !== this.hostId) return;
      const targetId = message?.playerId;
      if (!targetId) return;
      
      const target = this.clients.find(c => 
        (c.userData?.uid || c.sessionId) === targetId
      );
      if (target && target.userData?.uid !== this.hostId) {
        target.send('kicked', { reason: 'Removed by host' });
        target.leave();
      }
    });
    
    console.log(`[GameRoom:${this.code}] Created by ${this.hostId}, capacity: ${this.capacity}`);
  }
  
  async onAuth(client, options) {
    // Verify ticket for authenticated users
    if (options?.ticket) {
      const uid = verifyTicket(options.ticket, 'gameroom:' + this.code);
      if (!uid) throw new ServerError(403, 'Invalid room ticket');
      const u = await C.users.findOne({ _id: uid }, { projection: { passHash: 0 } });
      if (!u) throw new ServerError(404, 'Player not found');
      return { uid, pub: U.pub(u) };
    }
    
    // Guest access for public rooms
    if (!this.state.public) {
      throw new ServerError(403, 'Private room requires authentication');
    }
    
    return {
      uid: 'guest_' + client.sessionId,
      pub: { id: 'guest_' + client.sessionId, name: 'Guest', level: 1, trophies: 0 }
    };
  }
  
  onJoin(client, options, auth) {
    const userData = auth || {};
    const playerIndex = this.state.players.length;
    const team = playerIndex < this.teamSize ? 0 : 1;
    const slotInTeam = playerIndex % this.teamSize;
    
    client.userData = {
      uid: userData.uid || client.sessionId,
      name: userData.name || userData.pub?.name || 'Player',
      team,
      slotInTeam,
      pub: userData.pub
    };
    
    // Add player to room
    this.state.players.push({
      id: client.userData.uid,
      name: client.userData.name,
      team,
      slotInTeam,
      connected: true
    });
    
    // If room is now full, lock it
    if (this.state.players.length >= this.capacity) {
      this.lock();
    }
    
    this.syncState();
    console.log(`[GameRoom:${this.code}] ${client.userData.name} joined as team ${team}, slot ${slotInTeam}`);
  }
  
  onLeave(client, consented) {
    this.handleLeave(client);
  }
  
  handleLeave(client) {
    const uid = client.userData?.uid;
    if (!uid) return;
    
    const playerIndex = this.state.players.findIndex(p => p.id === uid);
    if (playerIndex >= 0) {
      this.state.players.splice(playerIndex, 1);
    }
    
    delete this.state.ready[uid];
    
    // If host left, transfer to next player or close room
    if (uid === this.hostId) {
      if (this.state.players.length > 0) {
        this.hostId = this.state.players[0].id;
        this.state.hostId = this.hostId;
      } else {
        this.state.status = 'finished';
        this.disconnect();
        return;
      }
    }
    
    // Unlock room if it was locked and players left
    if (this.state.players.length < this.capacity && this.locked) {
      this.unlock();
    }
    
    this.syncState();
    console.log(`[GameRoom:${this.code}] ${client.userData?.name || uid} left`);
  }
  
  async startMatch() {
    this.state.status = 'starting';
    this.syncState();
    
    // Create match document
    const team0Players = this.state.players.filter(p => p.team === 0).map(p => p.id);
    const team1Players = this.state.players.filter(p => p.team === 1).map(p => p.id);
    
    const matchOptions = {
      players: [team0Players[0], team1Players[0]], // Primary players
      allPlayers: this.state.players.map(p => p.id),
      teamSize: this.teamSize,
      settings: this.state.settings,
      roomCode: this.code,
      roomId: this.roomId
    };
    
    const created = await MM.create(matchOptions);
    this.state.matchId = created.matchId;
    this.state.status = 'playing';
    
    // Notify all clients with seat reservations
    for (const client of this.clients) {
      const uid = client.userData?.uid;
      if (uid && created.reservations[uid]) {
        client.send('match_start', {
          matchId: created.matchId,
          reservation: created.reservations[uid],
          settings: this.state.settings,
          teams: {
            team0: team0Players,
            team1: team1Players
          }
        });
      }
    }
    
    this.updateMetadata();
    this.syncState();
    
    // Schedule room cleanup after match ends
    setTimeout(() => {
      if (this.state.status === 'playing' || this.state.status === 'finished') {
        this.resetRoom();
      }
    }, (this.state.settings.matchTime + 60) * 1000);
  }
  
  resetRoom() {
    this.state.status = 'waiting';
    this.state.matchId = null;
    this.state.ready = {};
    this.updateMetadata();
    this.syncState();
  }
  
  syncState() {
    this.broadcast('room_state', this.state);
  }
  
  updateMetadata() {
    this.setMetadata({
      code: this.code,
      name: this.state.name,
      public: this.state.public,
      capacity: this.capacity,
      status: this.state.status,
      hostId: this.hostId,
      settings: this.state.settings,
      players: this.state.players.length,
      matchId: this.state.matchId
    });
  }
  
  generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    return code;
  }
  
  getPublicState() {
    return {
      code: this.code,
      name: this.state.name,
      capacity: this.capacity,
      players: this.state.players.length,
      status: this.state.status,
      settings: this.state.settings,
      hostId: this.hostId
    };
  }
}

module.exports = GameRoom;
