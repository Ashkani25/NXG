// Regenerate the Finger Soccer golden vector:  node --experimental-strip-types test/games/tools/fs_golden.mjs
import * as P from './fs_physics_ref.ts';
const bs = P.kickoff();
P.applyShot(bs, { bodyId: 2, dirX: 0.05, dirY: -1, power: 0.8 });
const r = P.simulate(bs); P.snap(bs);
console.log('shot1 scorer', r.scorer, 'steps', r.steps, 'hash', P.stateHash(bs), 'd2', bs[2].x, bs[2].y, 'ball', bs[10].x, bs[10].y);
P.applyShot(bs, { bodyId: 7, dirX: 0.1, dirY: 1, power: 0.7 });
const r2 = P.simulate(bs); P.snap(bs);
console.log('shot2 scorer', r2.scorer, 'steps', r2.steps, 'hash', P.stateHash(bs));
