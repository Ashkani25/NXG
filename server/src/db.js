// NEXORA NXG - MongoDB-style stub for PostgreSQL migration
// This provides a MongoDB-like C object for code still using MongoDB patterns
'use strict';

const { query, getUserById, updateUser, createUser, createMatch, getMatchById, updateMatch, createRoom, getRoomByCode, getPublicRooms, updateRoom, addFriend, getFriends, createNotification, getNotifications } = require('./supabase');

// In-memory stores for when PostgreSQL queries aren't suitable
const memoryStore = {
  users: new Map(),
  tournaments: new Map(),
  friends: new Map(),
  dms: new Map(),
  dmMessages: new Map()
};

// MongoDB-style collection wrapper
class MongoCollection {
  constructor(name, pgFn, memoryKey) {
    this.name = name;
    this.pgFn = pgFn;
    this.memoryKey = memoryKey;
  }

  find(query = {}) {
    return new MongoCursor(this, query, 'find');
  }

  findOne(query = {}, options = {}) {
    return this.find(query).limit(1).toArray().then(arr => arr[0] || null);
  }

  insertOne(doc) {
    const id = Math.random().toString(36).slice(2, 10);
    const docWithId = { ...doc, _id: id };
    if (this.memoryKey) {
      memoryStore[this.memoryKey].set(id, docWithId);
    }
    return { insertedId: id, acknowledged: true };
  }

  updateOne(query, update, options = {}) {
    // Stub - returns mock result
    return { matchedCount: 1, modifiedCount: 1, acknowledged: true };
  }

  deleteOne(query) {
    return { deletedCount: 1, acknowledged: true };
  }

  countDocuments(query = {}) {
    return Promise.resolve(0);
  }
}

class MongoCursor {
  constructor(collection, query, operation) {
    this.collection = collection;
    this.query = query;
    this.operation = operation;
    this._limit = 0;
    this._sort = null;
    this._projection = null;
  }

  sort(spec) {
    this._sort = spec;
    return this;
  }

  limit(n) {
    this._limit = n;
    return this;
  }

  projection(spec) {
    this._projection = spec;
    return this;
  }

  toArray() {
    return Promise.resolve([]);
  }
}

// C object - MongoDB-style collections
const C = {
  users: new MongoCollection('users', getUserById, 'users'),
  tournaments: new MongoCollection('tournaments', null, 'tournaments'),
  friends: new MongoCollection('friends', null, 'friends'),
  dms: new MongoCollection('dms', null, 'dms'),
  dm_messages: new MongoCollection('dm_messages', null, 'dmMessages')
};

// mutate function - MongoDB-style atomic update
async function mutate(collection, id, fn) {
  const doc = await collection.findOne({ _id: id });
  if (!doc) throw new Error('Document not found');
  const updated = fn(doc);
  // In this stub, we don't persist changes - this is just for validation
  return updated;
}

// Export everything in the format expected by the rest of the code
module.exports = {
  C,
  mutate
};
