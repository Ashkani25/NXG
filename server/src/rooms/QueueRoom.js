'use strict';
const { Room, matchMaker, ServerError } = require('@colyseus/core'), { verifyToken } = require('../auth'), { C } = require('../db'), U = require('../services/users'), MM = require('../services/match');

/**
 * QueueRoom - Matchmaking queue for 1v1, 2v2, 3v3
 * 
 * Features:
 * - Queue by game mode (1v1, 2v2, 3v3)
 * - Trophy-based skill matching
 * - Auto-pairing when opponents found
 * - Queue cancellation
 * - Dynamic queue expansion (wait longer = wider skill range)
 */
class QueueRoom extends Room {
  maxClients = 2000; // Many players can be in queue
  
  onCreate() {
    this.waiting = {
      '1v1': new Map(), // sessionId -> { uid, trophies, joinedAt, client }
      '2v2': new Map(),
      '3v3': new Map()
    };
    
    this.autoDispose = false;
    
    // Run pairing check every second
    this.clock.setInterval(() => {
      this.pairQueue('1v1', 2);
      this.pairQueue('2v2', 4);
      this.pairQueue('3v3', 6);
    }, 1000);
    
    // Broadcast queue status every 5 seconds
    this.clock.setInterval(() => {
      this.broadcastQueueStatus();
    }, 5000);
    
    this.onMessage('cancel', (client) => {
      this.removeFromQueue(client);
      client.send('queue_canceled', {});
    });
    
    this.onMessage('status', (client) => {
      client.send('queue_status', this.getQueueStatus());
    });
    
    console.log('[QueueRoom] Started');
  }
  
  onAuth(client, options) {
    const token = options?.token;
    if (!token) throw new ServerError(401, 'Authentication required');
    
    const uid = verifyToken(token);
    if (!uid) throw new ServerError(401, 'Invalid token');
    
    const user = C.users.findOne({ _id: uid }, { projection: { trophies: 1, banned: 1, level: 1 } });
    if (!user || user.banned) throw new ServerError(403, 'Access denied');
    
    return { uid, trophies: user.trophies || 0, level: user.level || 1 };
  }
  
  onJoin(client, options, auth) {
    const mode = options?.mode || '1v1';
    const uid = auth.uid;
    
    // Remove from any existing queue first
    this.removeFromQueueByUid(uid);
    
    // Add to new queue
    this.waiting[mode].set(client.sessionId, {
      uid,
      trophies: auth.trophies || 0,
      level: auth.level || 1,
      joinedAt: Date.now(),
      client,
      mode
    });
    
    client.send('queue_joined', { mode, position: this.getPositionInQueue(mode, client.sessionId) });
    console.log(`[QueueRoom] ${uid} joined ${mode} queue`);
  }
  
  onLeave(client) {
    this.removeFromQueue(client);
  }
  
  removeFromQueue(client) {
    for (const mode of Object.keys(this.waiting)) {
      if (this.waiting[mode].has(client.sessionId)) {
        const entry = this.waiting[mode].get(client.sessionId);
        this.waiting[mode].delete(client.sessionId);
        console.log(`[QueueRoom] ${entry.uid} left ${mode} queue`);
        return;
      }
    }
  }
  
  removeFromQueueByUid(uid) {
    for (const mode of Object.keys(this.waiting)) {
      for (const [sessionId, entry] of this.waiting[mode]) {
        if (entry.uid === uid) {
          this.waiting[mode].delete(sessionId);
          return;
        }
      }
    }
  }
  
  pairQueue(mode, teamSize) {
    const queue = this.waiting[mode];
    if (queue.size < teamSize) return;
    
    const players = [...queue.values()].sort((a, b) => a.joinedAt - b.joinedAt);
    const used = new Set();
    
    // Group players into teams
    for (const player of players) {
      if (used.has(player.uid)) continue;
      
      // Find best match for this player
      let bestMatch = null;
      let bestDiff = Infinity;
      const waitTime = (Date.now() - player.joinedAt) / 1000;
      const maxRange = 200 + 25 * waitTime; // Expand range over time
      
      for (const other of players) {
        if (other === player || used.has(other.uid)) continue;
        
        const diff = Math.abs(other.trophies - player.trophies);
        if (diff < bestDiff && diff <= maxRange) {
          bestMatch = other;
          bestDiff = diff;
        }
      }
      
      if (!bestMatch) continue;
      
      used.add(player.uid);
      used.add(bestMatch.uid);
      
      // Create match for this pair
      this.createMatchForPair(player, bestMatch, mode, teamSize);
    }
  }
  
  async createMatchForPair(player1, player2, mode, teamSize) {
    const teamSizeActual = teamSize / 2;
    
    // For now, create 1v1 match (can be extended for 2v2/3v3)
    // In a full implementation, we would wait for more players
    // or matchmake into teams first
    
    const players = [player1.uid, player2.uid];
    const settings = {
      matchTime: 300,
      turnTime: 15,
      field: 'stadium',
      ball: 0
    };
    
    try {
      const created = await MM.create({
        a: player1.uid,
        b: player2.uid,
        ranked: true,
        settings,
        mode
      });
      
      // Send match reservation to both players
      for (const [sessionId, entry] of this.waiting[mode]) {
        if (entry.uid === player1.uid || entry.uid === player2.uid) {
          entry.client.send('matched', {
            matchId: created.matchId,
            reservation: created.reservations[entry.uid],
            mode,
            teams: {
              team0: [player1.uid],
              team1: [player2.uid]
            },
            settings
          });
          
          // Remove from queue
          this.waiting[mode].delete(sessionId);
        }
      }
      
      console.log(`[QueueRoom] Match created: ${created.matchId}`);
    } catch (e) {
      console.error('[QueueRoom] Match creation failed:', e);
    }
  }
  
  getPositionInQueue(mode, sessionId) {
    const queue = this.waiting[mode];
    const sorted = [...queue.entries()].sort((a, b) => a[1].joinedAt - b[1].joinedAt);
    const pos = sorted.findIndex(([sid]) => sid === sessionId);
    return pos >= 0 ? pos + 1 : 0;
  }
  
  getQueueStatus() {
    return {
      '1v1': this.waiting['1v1'].size,
      '2v2': this.waiting['2v2'].size,
      '3v3': this.waiting['3v3'].size,
      total: this.waiting['1v1'].size + this.waiting['2v2'].size + this.waiting['3v3'].size
    };
  }
  
  broadcastQueueStatus() {
    const status = this.getQueueStatus();
    for (const client of this.clients) {
      client.send('queue_update', status);
    }
  }
  
  getPublicInfo() {
    return {
      name: 'Matchmaking Queue',
      mode: 'matchmaking',
      players: this.getQueueStatus().total,
      status: 'open'
    };
  }
}

module.exports = QueueRoom;
