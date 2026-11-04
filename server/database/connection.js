// NEXORA NXG - Database Connection & Initialization
'use strict';

const { MongoClient } = require('mongodb');
const cfg = require('../config');
const schema = require('./schema');

let client = null;
let db = null;
const C = {};

async function connect() {
  client = new MongoClient(cfg.MONGO_URL, {
    maxPoolSize: cfg.DB_POOL_SIZE || 30,
    minPoolSize: 5,
    maxIdleTimeMS: 30000,
    connectTimeoutMS: 10000,
    socketTimeoutMS: 45000
  });

  await client.connect();
  db = client.db(cfg.DB_NAME);

  // Initialize collections with validators
  for (const [name, def] of Object.entries(schema)) {
    const collection = db.collection(name);
    
    // Check if collection exists
    const collections = await db.listCollections({ name }).toArray();
    if (collections.length === 0) {
      // Create collection with validator
      await db.createCollection(name, { validator: def.validator });
    }
    
    // Create indexes
    if (def.indexes) {
      for (const idx of def.indexes) {
        try {
          await collection.createIndex(idx.key, idx);
        } catch (e) {
          // Index might already exist with different options
          console.warn(`Index creation warning for ${name}:`, e.message);
        }
      }
    }
    
    C[name] = collection;
  }

  // Create compound indexes that might not be in schema
  await ensureCompoundIndexes();

  console.log(`[NEXORA DB] Connected to ${cfg.DB_NAME}`);
  return C;
}

async function ensureCompoundIndexes() {
  // Users specific indexes
  try {
    await C.users.createIndex({ trophies: -1, level: -1 });
  } catch (e) {}

  // Matches - ensure TTL is set properly
  try {
    await C.matches.createIndex(
      { createdAt: 1 },
      { expireAfterSeconds: 60 * 86400, partialFilterExpression: { status: 'completed' } }
    );
  } catch (e) {}
}

/* Optimistic transaction: fn mutates a draft copy; the write only lands if nobody changed the doc meanwhile (field v) */
async function mutate(col, id, fn, tries = 8) {
  for (;;) {
    const doc = await col.findOne({ _id: id });
    if (!doc) throw bad('Not found', 404);
    
    const draft = structuredClone(doc);
    const out = await fn(draft);
    draft.v = (doc.v || 0) + 1;

    const r = await col.replaceOne({ _id: id, v: doc.v || 0 }, draft);
    if (r.matchedCount === 1) return out;
    
    if (--tries <= 0) throw bad('Server busy, try again', 409);
  }
}

/* Cluster-safe "run once" for schedulers */
async function withLock(name, ttlMs, fn) {
  const until = new Date(Date.now() + ttlMs);
  try {
    const r = await C.locks.findOneAndUpdate(
      { _id: name, until: { $lt: new Date() } },
      { $set: { until } },
      { upsert: true }
    );
    void r;
  } catch (e) {
    return false; // duplicate key => another node holds it
  }
  await fn();
  return true;
}

/* Count documents with query */
async function count(col, query = {}) {
  return col.countDocuments(query);
}

/* Find one and update */
async function findOneAndUpdate(col, query, update, options = {}) {
  return col.findOneAndUpdate(query, update, { returnDocument: 'after', ...options });
}

/* Bulk write with ordered flag */
async function bulkWrite(col, operations, ordered = false) {
  return col.bulkWrite(operations, { ordered });
}

/* Aggregate pipeline helper */
async function aggregate(col, pipeline) {
  return col.aggregate(pipeline).toArray();
}

function close() {
  if (client) {
    client.close();
    client = null;
    db = null;
    Object.keys(C).forEach(k => delete C[k]);
    console.log('[NEXORA DB] Connection closed');
  }
}

module.exports = {
  C,
  connect,
  close,
  mutate,
  withLock,
  count,
  findOneAndUpdate,
  bulkWrite,
  aggregate
};
