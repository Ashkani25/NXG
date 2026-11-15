// The unified, deterministic physics world of the 'stars' profile.
//
// One fixed step (kPhys.step, 240 Hz) is split into adaptive substeps (the fastest body moves <= subPx per
// substep). Each substep:
//   1. rules + friction (exact flow, clean sleep)
//   2. continuous collision: repeatedly find the EARLIEST time of impact among all body pairs and every body vs
//      the boundary (rails, corner arcs, posts, nets), advance everything to it, resolve that contact; then advance
//      the rest of the substep (bounded number of events)
//   3. positional correction (slop + percentage, iterations) and containment
//   4. visual roll of the ball, proportional to the distance it actually travelled
// Pure IEEE arithmetic (+ fdlibm exp / sin / cos) in a fixed order: bit-identical on every peer (online lockstep).
import 'dart:math' as math;

import 'body.dart';
import 'boundary_collision.dart';
import 'collision_detector.dart';
import 'collision_resolver.dart';
import 'friction.dart';
import 'physics_config.dart';

/// Receives contact events (engine sounds / particles / net ripple, or the trajectory preview).
abstract class PhysicsListener {
  void onPair(Body a, Body b, double vn);
  void onStatic(Body o, EdgeKind kind, double vn);
  void afterSubstep();
}

class PhysicsWorld {
  final PhysicsConfig c;
  final Boundary bd;
  final List<Body> bodies;
  PhysicsListener? listener;

  /// ball inside the net after a goal: soft net (phase goal)
  bool goalHold = false;

  /// disc goal eject rule (a slow disc inside a goal is walked back out)
  bool eject = true;

  PhysicsWorld(this.c, this.bd, this.bodies, {this.listener});

  bool get allAsleep {
    for (final b in bodies) {
      if (!b.asleep) return false;
    }
    return true;
  }

  int substepsFor(double dt) {
    var v2 = 0.0;
    for (final b in bodies) {
      final s2 = b.vx * b.vx + b.vy * b.vy;
      if (s2 > v2) v2 = s2;
    }
    if (v2 == 0) return 0;
    final n = (math.sqrt(v2) * dt / c.subPx).ceil();
    return n < 1 ? 1 : (n > c.subMax ? c.subMax : n);
  }

  /// one fixed step
  void step(double dt) {
    if (eject) {
      for (final b in bodies) {
        if (!b.isBall) _ejectRule(b);
      }
    }
    var n = substepsFor(dt);
    if (n == 0) {
      for (final b in bodies) {
        if (_inBank(b)) n = 1;
      }
    }
    if (n == 0) {
      // everything asleep: nothing moves, nothing is corrected (no micro-movement at rest)
      listener?.afterSubstep();
      return;
    }
    final h = dt / n;
    for (var i = 0; i < n; i++) {
      _sub(h);
      listener?.afterSubstep();
    }
  }

  final List<double> _x0 = [], _y0 = [];

  void _sub(double h) {
    final B = bodies, nb = B.length;
    if (_x0.length != nb) {
      _x0
        ..clear()
        ..addAll(List.filled(nb, 0.0));
      _y0
        ..clear()
        ..addAll(List.filled(nb, 0.0));
    }
    for (var i = 0; i < nb; i++) {
      final b = B[i];
      _x0[i] = b.x;
      _y0[i] = b.y;
      applyFriction(b, h, c);
      _bank(b, h);
    }
    // ---- continuous collision ----
    var t = 0.0;
    for (var ev = 0; ev < c.maxEvents; ev++) {
      final left = h - t;
      if (left <= 0) break;
      var best = left + 1;
      var kind = 0; // 1 pair, 2 seg, 3 post, 4 arc
      Body? ba, bb;
      Object? obs;
      for (var i = 0; i < nb; i++) {
        final a = B[i];
        final aw = !a.asleep;
        for (var k = i + 1; k < nb; k++) {
          final b = B[k];
          if (!aw && b.asleep) continue;
          // broad phase: can they meet within the window?
          final reach = a.r + b.r + (a.vx.abs() + a.vy.abs() + b.vx.abs() + b.vy.abs()) * left;
          final dx = b.x - a.x, dy = b.y - a.y;
          if (dx > reach || dx < -reach || dy > reach || dy < -reach) continue;
          final tt = toiPair(a, b, left);
          if (tt >= 0 && tt < best) {
            best = tt;
            kind = 1;
            ba = a;
            bb = b;
          }
        }
        if (!aw) continue;
        for (final s in bd.segs) {
          final tt = toiSeg(a, s, left);
          if (tt >= 0 && tt < best) {
            best = tt;
            kind = 2;
            ba = a;
            obs = s;
          }
        }
        for (final p in bd.posts) {
          final tt = toiPost(a, p, left);
          if (tt >= 0 && tt < best) {
            best = tt;
            kind = 3;
            ba = a;
            obs = p;
          }
        }
        for (final ar in bd.arcs) {
          final tt = toiArc(a, ar, left);
          if (tt >= 0 && tt < best) {
            best = tt;
            kind = 4;
            ba = a;
            obs = ar;
          }
        }
      }
      if (kind == 0) break;
      _advance(best);
      t += best;
      final a = ba!;
      switch (kind) {
        case 1:
          final vn = resolvePair(a, bb!, c);
          if (vn > 0) listener?.onPair(a, bb, vn);
        case 2:
          final s = obs as Seg;
          final vn = resolveStatic(a, s.nx, s.ny, s.kind, c, goalHold: goalHold);
          if (vn > 0) listener?.onStatic(a, s.kind, vn);
        case 3:
          final p = obs as Post;
          var nx = a.x - p.x, ny = a.y - p.y;
          final d = math.sqrt(nx * nx + ny * ny);
          nx /= d;
          ny /= d;
          final vn = resolveStatic(a, nx, ny, EdgeKind.post, c, goalHold: goalHold);
          if (vn > 0) listener?.onStatic(a, EdgeKind.post, vn);
        default:
          final ar = obs as Arc;
          var nx = ar.cx - a.x, ny = ar.cy - a.y;
          final d = math.sqrt(nx * nx + ny * ny);
          nx /= d;
          ny /= d;
          final vn = resolveStatic(a, nx, ny, EdgeKind.corner, c, goalHold: goalHold);
          if (vn > 0) listener?.onStatic(a, EdgeKind.corner, vn);
      }
    }
    if (t < h) _advance(h - t);
    // ---- positional correction ----
    for (var it = 0; it < c.posIters; it++) {
      for (var i = 0; i < nb; i++) {
        final a = B[i];
        for (var k = i + 1; k < nb; k++) {
          correctPair(a, B[k], c);
        }
      }
    }
    for (var i = 0; i < nb; i++) {
      final b = B[i];
      if (b.asleep && b.x == _x0[i] && b.y == _y0[i]) continue;
      correctStatic(b, bd);
      bd.contain(b);
      if (b.isBall) _roll(b, b.x - _x0[i], b.y - _y0[i], h);
    }
  }

  /// corner bank: a body touching (within bankZone of) a rounded corner is eased back towards play, so nothing can
  /// come to rest or stay pinned in a corner. Acts only in the corner pockets.
  Arc? _bankArc(Body b) {
    for (final a in bd.arcs) {
      final qx = b.x - a.cx, qy = b.y - a.cy;
      if (qx * a.sx <= 0 || qy * a.sy <= 0) continue;
      final rr = a.rad - b.r, dd = qx * qx + qy * qy;
      if (dd < (rr - c.bankZone) * (rr - c.bankZone)) continue;
      return a;
    }
    return null;
  }

  bool _inBank(Body b) => _bankArc(b) != null;

  void _bank(Body b, double h) {
    final a = _bankArc(b);
    if (a == null) return;
    final qx = b.x - a.cx, qy = b.y - a.cy;
    final d = math.sqrt(qx * qx + qy * qy), k = c.bankAcc * h / d;
    b.vx -= qx * k;
    b.vy -= qy * k;
  }

  void _advance(double dt) {
    if (dt <= 0) return;
    for (final b in bodies) {
      if (b.vx == 0 && b.vy == 0) continue;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
    }
  }

  /// visual rolling only (never feeds back into the motion): rotation = distance travelled / radius
  void _roll(Body b, double dx, double dy, double h) {
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-9) {
      b.w = 0;
      return;
    }
    b.wax = -dy / d;
    b.way = dx / d;
    b.w = d / b.r / h;
    rotateRoll(b.R, b.wax, b.way, d / b.r);
  }

  /// rule kept from v0.6: a disc that drifts slowly into a goal is walked back out onto the pitch
  void _ejectRule(Body b) {
    final g0 = b.gout;
    if (g0 != null) {
      final dq = g0.d * (b.y - g0.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g0.d * c.ejectSpeed;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
      return;
    }
    for (final g in bd.goals) {
      final dp = g.d * (b.y - g.y);
      if (dp > b.r * .3 && b.x > g.x1 && b.x < g.x2 && b.vx * b.vx + b.vy * b.vy < c.ejectBelow * c.ejectBelow) {
        b.gout = g;
        return;
      }
    }
  }
}
