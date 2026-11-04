// NEXORA NXG - Server Configuration with Supabase
'use strict';

try { require('dotenv').config() } catch (e) {}

const env = process.env;
const prod = env.NODE_ENV === 'production';

const cfg = {
  // Environment
  PROD: prod,
  DEV: !prod,
  DEBUG: env.DEBUG === 'true',

  // Server
  PORT: +env.PORT || 2567,
  HOST: env.HOST || '0.0.0.0',

  // Supabase (Database & Auth)
  SUPABASE_URL: env.SUPABASE_URL || 'https://cqbtbgdkgmcbhaoktcwy.supabase.co',
  SUPABASE_SERVICE_KEY: env.SUPABASE_SERVICE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxYnRiZ2RrZ21jYmhhb2t0Y3d5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5Mzc5ODY5OCwiZXhwIjoyMTA5Mzc0Njk4fQ.MtGfRTRX7M5zH3J_P7TROvBcPvUyQXyFwQ_33CDoTuQ',
  SUPABASE_ANON_KEY: env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxYnRiZ2RrZ21jYmhhb2t0Y3d5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3OTg2OTgsImV4cCI6MjA5Mzc0Njk4fQ.aUN_wwmo8GZF44S2SRSzsHwohUhKIMAx0fKxN19G-yQ',

  // Security
  JWT_SECRET: env.JWT_SECRET || 'bermuda2024secretkeynxg2024securetoken',
  TICKET_SECRET: env.TICKET_SECRET || 'bermudaticket2024nxgsecret2024key',
  SESSION_SECRET: env.SESSION_SECRET || 'bermudases2024token12345secure',
  BCRYPT_ROUNDS: +env.BCRYPT_ROUNDS || 10,
  
  // CORS
  CORS_ORIGIN: (env.CORS_ORIGIN || '*').split(',').map(s => s.trim()),
  
  // Rate limiting
  RATE_LIMIT: +env.RATE_LIMIT || 100,
  RATE_WINDOW: +env.RATE_WINDOW || 60000
};

module.exports = cfg;