process.env.JWT_SECRET = 'x'.repeat(40); process.env.TICKET_SECRET = 'y'.repeat(40);
const assert = require('assert'), A = require('../src/auth');
const t = A.signToken('u1'); assert.strictEqual(A.verifyToken(t), 'u1'); assert.strictEqual(A.verifyToken(t + 'x'), null);
const k = A.signTicket('u1', 'match:abc'); assert.strictEqual(A.verifyTicket(k, 'match:abc'), 'u1'); assert.strictEqual(A.verifyTicket(k, 'match:other'), null); assert.strictEqual(A.verifyTicket(t, 'match:abc'), null);
console.log('auth ok');
