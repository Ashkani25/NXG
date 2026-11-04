// NEXORA NXG - Server Configuration
'use strict';

try { require('dotenv').config() } catch (e) {}

const env = process.env;
const prod = env.NODE_ENV === 'production';

// Validate required environment variables in production
if (prod) {
  const required = ['JWT_SECRET', 'TICKET_SECRET', 'MONGO_URL'];
  for (const key of required) {
    if (!env[key]) throw new Error(`Missing required environment variable: ${key}`);
  }
}

const cfg = {
  // Environment
  PROD: prod,
  DEV: !prod,
  DEBUG: env.DEBUG === 'true',

  // Server
  PORT: +env.PORT || 2567,
  HOST: env.HOST || '0.0.0.0',

  // Database
  MONGO_URL: env.MONGO_URL || 'mongodb://127.0.0.1:27017',
  DB_NAME: env.DB_NAME || 'nexoranxg',
  DB_POOL_SIZE: +env.DB_POOL_SIZE || 30,

  // Security
  JWT_SECRET: env.JWT_SECRET || 'dev-only-jwt-secret-change-in-production',
  TICKET_SECRET: env.TICKET_SECRET || 'dev-only-ticket-secret-change-in-production',
  SESSION_SECRET: env.SESSION_SECRET || 'dev-only-session-secret',
  BCRYPT_ROUNDS: +env.BCRYPT_ROUNDS || 12,
  
  // CORS
  CORS_ORIGIN: (env.CORS_ORIGIN || '*').split(',').map(s => s.trim()),
  
  // Rate Limiting
  RATE_LIMIT_WINDOW: +env.RATE_LIMIT_WINDOW || 60000,
  RATE_LIMIT_MAX: +env.RATE_LIMIT_MAX || 100,

  // Game Settings
  MATCH_SECONDS: 300,
  TURN_SECONDS: 15,
  MAX_PLAYERS_PER_ROOM: 6,
  SPECTATOR_LIMIT: 50,

  // AI Settings (AUHI AI or Anthropic)
  AI_PROVIDER: env.AI_PROVIDER || 'anthropic',
  ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY || '',
  AI_MODEL: env.AI_MODEL || 'claude-sonnet-4-5',
  AI_MAX_TOKENS: +env.AI_MAX_TOKENS || 500,
  AI_DAILY_LIMIT: +env.AI_DAILY_LIMIT || 40,
  AUHI_API_KEY: env.AUHI_API_KEY || '',
  AUHI_API_URL: env.AUHI_API_URL || '',

  // File Upload
  UPLOAD_DIR: env.UPLOAD_DIR || './uploads',
  MAX_UPLOAD_SIZE: +env.MAX_UPLOAD_SIZE || 10 * 1024 * 1024, // 10MB
  ALLOWED_FILE_TYPES: [
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'audio/mpeg', 'audio/wav', 'audio/ogg',
    'video/mp4', 'video/webm',
    'application/pdf',
    'text/plain'
  ],

  // Reward Limits
  DAILY_BOT_MATCHES: 15,
  DAILY_AI_REQUESTS: 40,

  // XP & Economy
  XP_BASE: 300,
  XP_PER_LEVEL: 350,
  COINS_WIN_BONUS: 120,
  COINS_LOSS_BONUS: 30,
  COINS_PER_LEVEL: 100,

  // Leagues (trophy thresholds)
  LEAGUES: [
    { id: 'bronze', name: 'Bronze', min: 0, color: '#c98a52' },
    { id: 'silver', name: 'Silver', min: 500, color: '#cfd6e2' },
    { id: 'gold', name: 'Gold', min: 1000, color: '#ffd56b' },
    { id: 'platinum', name: 'Platinum', min: 1800, color: '#7fe3ff' },
    { id: 'diamond', name: 'Diamond', min: 2800, color: '#8fa8ff' },
    { id: 'master', name: 'Master', min: 4000, color: '#d58bff' },
    { id: 'legend', name: 'Legend', min: 6000, color: '#ff7a5c' }
  ],

  // Daily Rewards
  DAILY_REWARDS: [
    { coins: 100 }, { coins: 150 }, { coins: 200 }, { gems: 5 },
    { coins: 300 }, { coins: 400 }, { coins: 600, gems: 10 }
  ],

  // Match Times (seconds)
  MATCH_TIMES: [180, 300, 420, 600],

  // Gift Code Settings
  GIFT_CODE_LENGTH: 12,
  GIFT_CODE_CHARS: 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',

  // Admin
  ADMIN_API_KEY: env.ADMIN_API_KEY || '',

  // Google OAuth (optional)
  GOOGLE_CLIENT_ID: env.GOOGLE_CLIENT_ID || '',
  GOOGLE_CLIENT_SECRET: env.GOOGLE_CLIENT_SECRET || ''
};

module.exports = cfg;
