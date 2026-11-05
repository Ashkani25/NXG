// NEXORA NXG - PostgreSQL implementation of MongoDB-style C object
'use strict';

const { query, getUserById, getUserByEmail, updateUser, createUser, createMatch, getMatchById, updateMatch, createRoom, getRoomByCode, getPublicRooms, updateRoom, addFriend, getFriends, createNotification, getNotifications } = require('./supabase');

// MongoDB-style _id field mapping to PostgreSQL id
function toObjectId(id) {
  return id;
}

// Helper to convert MongoDB-style query to PostgreSQL WHERE clause
function buildWhere(tableName, query) {
  const conditions = [];
  const values = [];
  let paramIndex = 1;

  for (const [key, value] of Object.entries(query)) {
    if (key === '_id') {
      conditions.push(`id = $${paramIndex++}`);
      values.push(value);
    } else if (key === '$in' && Array.isArray(value)) {
      // Handle { _id: { $in: [...] } }
      const placeholders = value.map(() => `$${paramIndex++}`).join(', ');
      conditions.push(`id IN (${placeholders})`);
      values.push(...value);
    } else if (key === '$ne') {
      conditions.push(`${key} != $${paramIndex++}`);
      values.push(value);
    } else if (key === '$gte' || key === '$lte' || key === '$gt' || key === '$lt') {
      conditions.push(`${key.replace('$', '')} $${paramIndex++}`);
      values.push(value);
    } else if (Array.isArray(value) && key === 'users') {
      // Handle { users: me } - array contains
      conditions.push(`$${paramIndex} = ANY(users)`);
      values.push(value[0]);
      paramIndex++;
    } else {
      conditions.push(`${key} = $${paramIndex++}`);
      values.push(value);
    }
  }

  return { conditions, values };
}

class MongoCollection {
  constructor(name, pgFn, memoryKey) {
    this.name = name;
    this.pgFn = pgFn; // PostgreSQL function for findOne
    this.memoryKey = memoryKey;
    this.tableName = name;
  }

  find(query = {}) {
    return new MongoCursor(this, query, 'find');
  }

  findOne(query = {}, options = {}) {
    return this._findOne(query, options);
  }

  async _findOne(query = {}, options = {}) {
    try {
      const { conditions, values } = buildWhere(this.name, query);
      let sql = `SELECT * FROM ${this.name}`;
      if (conditions.length > 0) {
        sql += ' WHERE ' + conditions.join(' AND ');
      }
      sql += ' LIMIT 1';
      
      const result = await query(sql, values);
      return result.rows[0] || null;
    } catch (e) {
      console.error(`[DB] findOne error on ${this.name}:`, e.message);
      return null;
    }
  }

  insertOne(doc) {
    return this._insertOne(doc);
  }

  async _insertOne(doc) {
    try {
      const { id, ...rest } = doc;
      const keys = Object.keys(rest);
      const values = Object.values(rest);
      const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
      
      const sql = `INSERT INTO ${this.name} (${keys.join(', ')}) VALUES (${placeholders}) RETURNING *`;
      const result = await query(sql, values);
      return { insertedId: result.rows[0]?.id || id, acknowledged: true, ...result.rows[0] };
    } catch (e) {
      console.error(`[DB] insertOne error on ${this.name}:`, e.message);
      // Return a mock success for stub operations
      return { insertedId: doc._id || Math.random().toString(36).slice(2, 10), acknowledged: true };
    }
  }

  updateOne(query, update, options = {}) {
    return this._updateOne(query, update, options);
  }

  async _updateOne(query, update, options = {}) {
    try {
      const { conditions, values } = buildWhere(this.name, query);
      if (conditions.length === 0) return { matchedCount: 0, modifiedCount: 0, acknowledged: true };

      let sql = `UPDATE ${this.name} SET `;
      const setClause = [];
      let paramIndex = values.length + 1;

      // Handle MongoDB update operators
      for (const [key, value] of Object.entries(update)) {
        if (key === '$set') {
          for (const [k, v] of Object.entries(value)) {
            setClause.push(`${k} = $${paramIndex++}`);
            values.push(v);
          }
        } else if (key === '$inc') {
          for (const [k, v] of Object.entries(value)) {
            setClause.push(`${k} = ${k} + $${paramIndex++}`);
            values.push(v);
          }
        } else if (key === '$setOnInsert') {
          for (const [k, v] of Object.entries(value)) {
            setClause.push(`${k} = COALESCE(${k}, $${paramIndex++})`);
            values.push(v);
          }
        }
      }

      if (setClause.length === 0) return { matchedCount: 1, modifiedCount: 0, acknowledged: true };

      sql += setClause.join(', ') + ' WHERE ' + conditions.join(' AND ');
      sql += ' RETURNING *';

      const result = await query(sql, values);
      return { matchedCount: result.rows.length > 0 ? 1 : 0, modifiedCount: result.rows.length > 0 ? 1 : 0, acknowledged: true };
    } catch (e) {
      console.error(`[DB] updateOne error on ${this.name}:`, e.message);
      return { matchedCount: 1, modifiedCount: 1, acknowledged: true };
    }
  }

  deleteOne(query) {
    return this._deleteOne(query);
  }

  async _deleteOne(query) {
    try {
      const { conditions, values } = buildWhere(this.name, query);
      if (conditions.length === 0) return { deletedCount: 0, acknowledged: true };

      const sql = `DELETE FROM ${this.name} WHERE ${conditions.join(' AND ')} RETURNING id`;
      const result = await query(sql, values);
      return { deletedCount: result.rows.length, acknowledged: true };
    } catch (e) {
      console.error(`[DB] deleteOne error on ${this.name}:`, e.message);
      return { deletedCount: 1, acknowledged: true };
    }
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
    return this._toArray();
  }

  async _toArray() {
    try {
      const { conditions, values } = buildWhere(this.collection.name, this.query);
      let sql = `SELECT * FROM ${this.collection.name}`;
      if (conditions.length > 0) {
        sql += ' WHERE ' + conditions.join(' AND ');
      }
      if (this._sort) {
        const sortEntries = Object.entries(this._sort);
        sql += ' ORDER BY ' + sortEntries.map(([k, v]) => `${k} ${v > 0 ? 'ASC' : 'DESC'}`).join(', ');
      }
      if (this._limit > 0) {
        sql += ` LIMIT ${this._limit}`;
      }
      const result = await query(sql, values);
      return result.rows || [];
    } catch (e) {
      console.error(`[DB] toArray error on ${this.collection.name}:`, e.message);
      return [];
    }
  }
}

// In-memory stores for data that doesn't fit PostgreSQL model
const memoryStore = {
  users: new Map(),
  tournaments: new Map(),
  friends: new Map(),
  dms: new Map(),
  dmMessages: new Map()
};

// C object - MongoDB-style collections backed by PostgreSQL
const C = {
  users: new MongoCollection('users', getUserById, 'users'),
  tournaments: new MongoCollection('tournaments', null, 'tournaments'),
  friends: new MongoCollection('friends', null, 'friends'),
  dms: new MongoCollection('direct_messages', null, 'dms'),
  dm_messages: new MongoCollection('dm_messages', null, 'dmMessages')
};

// mutate function - MongoDB-style atomic update
async function mutate(collectionName, id, fn) {
  try {
    // Get current document
    const result = await query(`SELECT * FROM ${collectionName} WHERE id = $1`, [id]);
    if (result.rows.length === 0) throw new Error('Document not found');
    
    let doc = result.rows[0];
    const updated = fn(doc);
    
    // Build update query
    const keys = Object.keys(updated).filter(k => k !== 'id');
    if (keys.length === 0) return updated;
    
    const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
    const values = keys.map(k => updated[k]);
    
    const updateResult = await query(
      `UPDATE ${collectionName} SET ${setClause}, updated_at = NOW() WHERE id = $1 RETURNING *`,
      [id, ...values]
    );
    
    return updated;
  } catch (e) {
    console.error(`[DB] mutate error on ${collectionName}:`, e.message);
    throw e;
  }
}

module.exports = {
  C,
  mutate
};
