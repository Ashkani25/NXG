'use strict';
try { require('dotenv').config() } catch (e) { /* dotenv optional: docker passes env directly */ }
const env = process.env, prod = env.NODE_ENV === 'production';
const cfg = {
  PROD: prod, PORT: +env.PORT || 2567, MONGO_URL: env.MONGO_URL || 'mongodb://127.0.0.1:27017', DB_NAME: env.DB_NAME || 'bermudanxg',
  JWT_SECRET: env.JWT_SECRET || 'dev-only-secret', TICKET_SECRET: env.TICKET_SECRET || 'dev-only-ticket-secret',
  CORS_ORIGIN: (env.CORS_ORIGIN || '*').split(',').map(s => s.trim()), GOOGLE_CLIENT_ID: env.GOOGLE_CLIENT_ID || '',
  ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY || '', AI_MODEL: env.AI_MODEL || 'claude-sonnet-5-5', MATCH_SECONDS: 300, TURN_SECONDS: 15
};
if (prod && (cfg.JWT_SECRET === 'dev-only-secret' || cfg.TICKET_SECRET === 'dev-only-ticket-secret')) throw new Error('Set JWT_SECRET and TICKET_SECRET in production');
module.exports = cfg;
