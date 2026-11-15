// Contact response: mass-based normal impulses with controlled restitution, Coulomb tangential friction, the
// controlled rail "impact boost", and stable positional correction (slop + percentage, sleeping bodies immovable).
import 'dart:math' as math;

import 'body.dart';
import 'boundary_collision.dart';
import 'physics_config.dart';

/// restitution of a body-body contact with the attribute modifiers (striker strength + power, struck resistance)
double pairRestitution(Body a, Body b, double nx, double ny, PhysicsConfig c) {
  final ballPair = a.isBall || b.isBall;
  var e = ballPair ? c.eDiscBall : c.eDiscDisc;
  // striker = the body closing in faster along the normal (n points a -> b)
  final sa = a.vx * nx + a.vy * ny, sb = -(b.vx * nx + b.vy * ny);
  final st = sa >= sb ? a : b, hit = identical(st, a) ? b : a;
  if (!st.isBall) e += c.strengthE * statLerp(st.attrs.strength, -1, 1) + c.powerHitE * (st.pf - 1);
  if (!hit.isBall) e -= c.resistE * statLerp(hit.attrs.resist, -1, 1);
  return e < c.eMin ? c.eMin : (e > c.eMax ? c.eMax : e);
}

/// resolve a touching pair (|b - a| ~ ra + rb). Returns the approach speed (> 0) or 0 when nothing was applied.
double resolvePair(Body a, Body b, PhysicsConfig c) {
  var nx = b.x - a.x, ny = b.y - a.y;
  final d = math.sqrt(nx * nx + ny * ny);
  if (d < 1e-9) {
    nx = 0;
    ny = 1;
  } else {
    nx /= d;
    ny /= d;
  }
  final rvx = b.vx - a.vx, rvy = b.vy - a.vy;
  final vn = rvx * nx + rvy * ny;
  if (vn >= 0) return 0;
  final sm = a.im + b.im;
  final e = -vn < c.vRest ? 0.0 : pairRestitution(a, b, nx, ny, c);
  final j = -(1 + e) * vn / sm;
  a.vx -= j * nx * a.im;
  a.vy -= j * ny * a.im;
  b.vx += j * nx * b.im;
  b.vy += j * ny * b.im;
  // tangential Coulomb friction (|jt| <= mu j), never reverses the sliding direction
  final tx = rvx - vn * nx, ty = rvy - vn * ny, vt = math.sqrt(tx * tx + ty * ty);
  if (vt > 1e-9 && c.muContact > 0) {
    final jt = math.min(c.muContact * j, vt / sm);
    final ux = tx / vt, uy = ty / vt;
    a.vx += jt * ux * a.im;
    a.vy += jt * uy * a.im;
    b.vx -= jt * ux * b.im;
    b.vy -= jt * uy * b.im;
  }
  // the ball carries the power factor of the disc that struck it (rail boost)
  if (a.isBall && !b.isBall) a.pf = b.pf;
  if (b.isBall && !a.isBall) b.pf = a.pf;
  _cap(a, c);
  _cap(b, c);
  return -vn;
}

void _cap(Body o, PhysicsConfig c) {
  final s2 = o.vx * o.vx + o.vy * o.vy;
  if (s2 > c.vCap * c.vCap) {
    final k = c.vCap / math.sqrt(s2);
    o.vx *= k;
    o.vy *= k;
  }
}

/// Response of a body against static geometry with inward unit normal (nx, ny).
///   normal out = |vn| * e  + boost,  boost = boostK * pf * cos(incidence) * |vn|   (none for resting contacts)
///   tangential: Coulomb friction mu * (1 + e) * |vn|, never reversing the slide
///   |v_out| <= keepMax * |v_in| and <= vCap: a rebound can never gain energy, repeated rebounds only lose it.
/// Returns the approach (normal) speed, 0 when the body was not approaching.
double resolveStatic(Body o, double nx, double ny, EdgeKind kind, PhysicsConfig c, {bool goalHold = false}) {
  final vn = o.vx * nx + o.vy * ny;
  if (vn >= 0) return 0;
  final an = -vn;
  final tx = o.vx - vn * nx, ty = o.vy - vn * ny;
  final vin = math.sqrt(o.vx * o.vx + o.vy * o.vy);
  double e;
  var boost = 0.0;
  if (an < c.vRest) {
    e = 0; // resting / grazing contact: no bounce, no boost (no vibration against a rail)
  } else if (goalHold && o.isBall && kind == EdgeKind.net) {
    e = c.eGoalHold;
  } else {
    e = switch (kind) {
      EdgeKind.post => c.ePost,
      EdgeKind.corner => c.eCorner,
      EdgeKind.net => c.eNet,
      EdgeKind.rail => o.isBall ? c.eRailBall : c.eRailDisc,
    };
    if (kind != EdgeKind.net) boost = c.boostK * o.pf * (an / vin);
  }
  var vno = an * (e + boost);
  // tangential friction
  final vt = math.sqrt(tx * tx + ty * ty);
  var kt = 1.0;
  if (vt > 1e-9) {
    final mu = c.muRail * o.muMul * (kind == EdgeKind.corner ? c.muCornerK : 1);
    final dv = math.min(vt, mu * (1 + e) * an);
    kt = (vt - dv) / vt;
  }
  var ox = tx * kt + vno * nx, oy = ty * kt + vno * ny;
  final vout = math.sqrt(ox * ox + oy * oy), lim = math.min(c.keepMax * vin, c.vCap);
  if (vout > lim && vout > 0) {
    final k = lim / vout;
    ox *= k;
    oy *= k;
  }
  o.vx = ox;
  o.vy = oy;
  return an;
}

/// push two overlapping bodies apart: (pen - slop) * posPercent, split by inverse mass. A sleeping body is
/// immovable here (it never drifts while at rest); two sleeping bodies are left alone.
void correctPair(Body a, Body b, PhysicsConfig c) {
  final dx = b.x - a.x, dy = b.y - a.y, m = a.r + b.r;
  final dd = dx * dx + dy * dy;
  if (dd >= (m - c.slop) * (m - c.slop)) return;
  final aw = !a.asleep, bw = !b.asleep;
  if (!aw && !bw) return;
  final d = math.sqrt(dd);
  var ux = 0.0, uy = 1.0;
  if (d > 1e-9) {
    ux = dx / d;
    uy = dy / d;
  }
  final pen = (m - d - c.slop) * c.posPercent;
  final ia = aw ? a.im : 0.0, ib = bw ? b.im : 0.0, s = ia + ib;
  a.x -= ux * pen * ia / s;
  a.y -= uy * pen * ia / s;
  b.x += ux * pen * ib / s;
  b.y += uy * pen * ib / s;
}

/// push a body out of static geometry it overlaps (exact, the overlap is only ever float-sized)
void correctStatic(Body o, Boundary bd) {
  for (final s in bd.segs) {
    final dc = (o.x - s.ax) * s.nx + (o.y - s.ay) * s.ny;
    if (dc < 0 || dc >= o.r) continue;
    final q = (o.x - s.ax) * s.ux + (o.y - s.ay) * s.uy;
    if (q < 0 || q > s.len) continue;
    o.x += s.nx * (o.r - dc);
    o.y += s.ny * (o.r - dc);
  }
  for (final p in bd.posts) {
    final dx = o.x - p.x, dy = o.y - p.y, m = o.r + p.rad, dd = dx * dx + dy * dy;
    if (dd >= m * m || dd < 1e-18) continue;
    final d = math.sqrt(dd);
    o.x = p.x + dx / d * m;
    o.y = p.y + dy / d * m;
  }
  for (final a in bd.arcs) {
    final rr = a.rad - o.r, qx = o.x - a.cx, qy = o.y - a.cy;
    if (qx * a.sx < 0 || qy * a.sy < 0) continue;
    final dd = qx * qx + qy * qy;
    if (dd <= rr * rr) continue;
    final d = math.sqrt(dd);
    o.x = a.cx + qx / d * rr;
    o.y = a.cy + qy / d * rr;
  }
}
