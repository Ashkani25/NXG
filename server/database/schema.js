// NEXORA NXG - Database Schema
// MongoDB Collections Definition

const collections = {
  // ============ USER MANAGEMENT ============
  users: {
    indexes: [
      { key: { email: 1 }, unique: true, sparse: true },
      { key: { nameLower: 1 } },
      { key: { shortId: 1 }, unique: true },
      { key: { trophies: -1 } },
      { key: { level: -1 } },
      { key: { createdAt: -1 } },
      { key: { banned: 1 } }
    ],
    validator: {
      $jsonSchema: {
        bsonType: 'object',
        required: ['_id', 'name', 'nameLower', 'shortId', 'createdAt'],
        properties: {
          _id: { bsonType: 'string' },
          email: { bsonType: 'string' },
          passHash: { bsonType: 'string' },
          guest: { bsonType: 'bool' },
          name: { bsonType: 'string', maxLength: 16 },
          nameLower: { bsonType: 'string' },
          shortId: { bsonType: 'string' },
          avatar: { bsonType: 'string' },
          team: { bsonType: 'string' },
          form: { bsonType: 'int' },
          level: { bsonType: 'int', minimum: 1 },
          xp: { bsonType: 'int', minimum: 0 },
          trophies: { bsonType: 'int' },
          rank: { bsonType: 'int' },
          bio: { bsonType: 'string', maxLength: 80 },
          country: { bsonType: 'string', maxLength: 3 },
          stats: {
            bsonType: 'object',
            properties: {
              played: { bsonType: 'int' },
              wins: { bsonType: 'int' },
              losses: { bsonType: 'int' },
              goals: { bsonType: 'int' },
              conceded: { bsonType: 'int' },
              streak: { bsonType: 'int' },
              best: { bsonType: 'int' }
            }
          },
          coins: { bsonType: 'int' },
          gems: { bsonType: 'int' },
          daily: {
            bsonType: 'object',
            properties: {
              day: { bsonType: 'int' },
              last: { bsonType: 'string' },
              streak: { bsonType: 'int' }
            }
          },
          quests: {
            bsonType: 'object',
            properties: {
              date: { bsonType: 'string' },
              list: { bsonType: 'array' }
            }
          },
          challenges: {
            bsonType: 'object',
            properties: {
              date: { bsonType: 'string' },
              weeklyDate: { bsonType: 'string' },
              daily: { bsonType: 'array' },
              weekly: { bsonType: 'array' }
            }
          },
          equip: {
            bsonType: 'object',
            properties: {
              ball: { bsonType: 'int' },
              field: { bsonType: 'string' },
              team: { bsonType: 'string' }
            }
          },
          owned: {
            bsonType: 'object',
            properties: {
              balls: { bsonType: 'array' },
              fields: { bsonType: 'array' },
              teams: { bsonType: 'array' }
            }
          },
          friends: { bsonType: 'array' },
          blocked: { bsonType: 'array' },
          notifications: {
            bsonType: 'object',
            properties: {
              settings: { bsonType: 'object' },
              tokens: { bsonType: 'array' }
            }
          },
          ai: {
            bsonType: 'object',
            properties: {
              date: { bsonType: 'string' },
              n: { bsonType: 'int' }
            }
          },
          banned: { bsonType: 'bool' },
          banReason: { bsonType: 'string' },
          createdAt: { bsonType: 'date' },
          lastSeen: { bsonType: 'date' },
          v: { bsonType: 'int' }
        }
      }
    }
  },

  // ============ SESSIONS ============
  sessions: {
    indexes: [
      { key: { userId: 1 } },
      { key: { token: 1 }, unique: true },
      { key: { expiresAt: 1 }, expireAfterSeconds: 0 }
    ]
  },

  // ============ SOCIAL ============
  follows: {
    indexes: [
      { key: { a: 1, at: -1 } },
      { key: { b: 1, at: -1 } },
      { key: { _id: 1 }, unique: true }
    ]
  },

  likes: {
    indexes: [
      { key: { a: 1, b: 1 }, unique: true }
    ]
  },

  friends: {
    indexes: [
      { key: { users: 1, status: 1 } },
      { key: { to: 1, status: 1 } },
      { key: { from: 1, status: 1 } }
    ]
  },

  // ============ MESSAGES ============
  dms: {
    indexes: [
      { key: { users: 1, lastAt: -1 } },
      { key: { _id: 1 }, unique: true }
    ]
  },

  dm_messages: {
    indexes: [
      { key: { pair: 1, at: -1 } },
      { key: { at: -1 } }
    ]
  },

  global_chat: {
    indexes: [
      { key: { at: -1 } }
    ],
    validator: {
      $jsonSchema: {
        bsonType: 'object',
        required: ['uid', 'name', 'text', 'at'],
        properties: {
          uid: { bsonType: 'string' },
          name: { bsonType: 'string' },
          avatar: { bsonType: 'string' },
          team: { bsonType: 'string' },
          level: { bsonType: 'int' },
          text: { bsonType: 'string', maxLength: 200 },
          at: { bsonType: 'date' }
        }
      }
    }
  },

  // ============ GROUPS & CHANNELS ============
  groups: {
    indexes: [
      { key: { owner: 1 } },
      { key: { members: 1 } },
      { key: { createdAt: -1 } }
    ]
  },

  group_members: {
    indexes: [
      { key: { groupId: 1, uid: 1 }, unique: true },
      { key: { uid: 1 } },
      { key: { groupId: 1, role: 1 } }
    ]
  },

  group_messages: {
    indexes: [
      { key: { groupId: 1, at: -1 } },
      { key: { at: -1 } }
    ]
  },

  channels: {
    indexes: [
      { key: { owner: 1 } },
      { key: { members: 1 } },
      { key: { type: 1, createdAt: -1 } }
    ]
  },

  channel_members: {
    indexes: [
      { key: { channelId: 1, uid: 1 }, unique: true },
      { key: { uid: 1 } }
    ]
  },

  channel_messages: {
    indexes: [
      { key: { channelId: 1, at: -1 } },
      { key: { at: -1 } }
    ]
  },

  // ============ MATCHES & ROOMS ============
  rooms: {
    indexes: [
      { key: { code: 1 }, unique: true },
      { key: { hostId: 1 } },
      { key: { status: 1, createdAt: -1 } },
      { key: { isPublic: 1, status: 1 } }
    ]
  },

  matches: {
    indexes: [
      { key: { createdAt: 1 }, expireAfterSeconds: 60 * 86400 },
      { key: { players: 1 } },
      { key: { tournamentId: 1 } },
      { key: { leagueId: 1 } }
    ]
  },

  match_reports: {
    indexes: [
      { key: { matchId: 1, uid: 1 }, unique: true }
    ]
  },

  // ============ COMPETITIVE ============
  leagues: {
    indexes: [
      { key: { season: 1, division: 1 } },
      { key: { status: 1, startsAt: 1 } }
    ]
  },

  league_standings: {
    indexes: [
      { key: { leagueId: 1, rank: 1 }, unique: true },
      { key: { uid: 1 } }
    ]
  },

  tournaments: {
    indexes: [
      { key: { status: 1, startsAt: 1 } },
      { key: { createdBy: 1, status: 1 } },
      { key: { officialKey: 1, status: 1 } }
    ]
  },

  tournament_players: {
    indexes: [
      { key: { tournamentId: 1, uid: 1 }, unique: true },
      { key: { uid: 1 } }
    ]
  },

  cups: {
    indexes: [
      { key: { status: 1, startsAt: 1 } }
    ]
  },

  cup_matches: {
    indexes: [
      { key: { cupId: 1, round: 1 } }
    ]
  },

  // ============ ECONOMY ============
  gift_codes: {
    indexes: [
      { key: { code: 1 }, unique: true },
      { key: { expiresAt: 1 }, expireAfterSeconds: 0 },
      { key: { maxUses: 1, usedCount: 1 } }
    ]
  },

  gift_redemptions: {
    indexes: [
      { key: { code: 1, uid: 1 }, unique: true },
      { key: { uid: 1 } },
      { key: { redeemedAt: -1 } }
    ]
  },

  shop_transactions: {
    indexes: [
      { key: { uid: 1, createdAt: -1 } },
      { key: { type: 1 } }
    ]
  },

  // ============ CHALLENGES ============
  challenges: {
    indexes: [
      { key: { type: 1, active: 1 } },
      { key: { expiresAt: 1 }, expireAfterSeconds: 0 }
    ]
  },

  challenge_progress: {
    indexes: [
      { key: { uid: 1, challengeId: 1 }, unique: true },
      { key: { uid: 1, type: 1 } }
    ]
  },

  // ============ FILES ============
  uploads: {
    indexes: [
      { key: { uid: 1, createdAt: -1 } },
      { key: { groupId: 1 } },
      { key: { channelId: 1 } },
      { key: { messageId: 1 } }
    ]
  },

  // ============ NOTIFICATIONS ============
  notifications: {
    indexes: [
      { key: { uid: 1, t: -1 } },
      { key: { uid: 1, read: 1 } }
    ]
  },

  // ============ AI ============
  ai_conversations: {
    indexes: [
      { key: { uid: 1, updatedAt: -1 } },
      { key: { createdAt: -1 } }
    ]
  },

  ai_messages: {
    indexes: [
      { key: { conversationId: 1, createdAt: 1 } }
    ]
  },

  // ============ ADMIN & SYSTEM ============
  audit_logs: {
    indexes: [
      { key: { uid: 1, action: 1, createdAt: -1 } },
      { key: { targetUid: 1, createdAt: -1 } },
      { key: { type: 1, createdAt: -1 } }
    ]
  },

  bans: {
    indexes: [
      { key: { uid: 1 } },
      { key: { expiresAt: 1 }, expireAfterSeconds: 0 },
      { key: { bannedBy: 1 } }
    ]
  },

  reports: {
    indexes: [
      { key: { status: 1, createdAt: -1 } },
      { key: { reporterId: 1 } },
      { key: { targetId: 1 } }
    ]
  },

  // ============ LOCKS & JOBS ============
  locks: {
    indexes: [
      { key: { _id: 1 }, unique: true },
      { key: { until: 1 }, expireAfterSeconds: 0 }
    ]
  },

  scheduled_jobs: {
    indexes: [
      { key: { name: 1, scheduledFor: 1 } },
      { key: { status: 1, scheduledFor: 1 } }
    ]
  }
};

module.exports = collections;
