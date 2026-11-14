// Disc Football offline AI — port of engine.gd _ai_decide (levels 0 easy, 1 normal, 2 hard).
// Pure Dart. Uses only the engine's seedable rng, so bot matches are deterministic per seed.
import 'dart:math' as math;

import 'engine.dart';

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// Distance from point p to segment a-b.
double segDist(double px, double py, double ax, double ay, double bx, double by) {
  final double vx = bx - ax;
  final double vy = by - ay;
  double l2 = vx * vx + vy * vy;
  if (l2 == 0) l2 = 1.0;
  double t = ((px - ax) * vx + (py - ay) * vy) / l2;
  t = _clamp(t, 0, 1);
  final double qx = px - (ax + vx * t);
  final double qy = py - (ay + vy * t);
  return math.sqrt(qx * qx + qy * qy);
}

bool _clear(Engine e, Body p, double x, double y) {
  for (final Body o in e.bodies) {
    if (o == p || o == e.ball) continue;
    if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
  }
  return true;
}

class _Cand {
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk, this.i);
  final Body p;
  final double dx;
  final double dy;
  final double sc;
  final double dist;
  final bool atk;
  final int i;
}

/// Godot engine.gd _ai_decide: candidate shots (strike the ball toward one of three points of the
/// target goal mouth, or just clear the ball), scored, stable-sorted, picked from a pool sized by
/// difficulty (4 / 2 / 1) with gaussian aim error (0.14 / 0.06 / 0.016 rad).
AiPlan? decideAiShot(Engine e) {
  final Body ball = e.ball;
  final int me = e.turn;
  final List<Body> mine = <Body>[
    for (final Body b in e.bodies)
      if (b.team == me && b != ball) b,
  ];
  final Goal og = e.goals[1 - me];
  final Goal target = e.goals[me == 1 ? 1 : 0];
  final int lvl = math.max(0, math.min(2, e.cfg.aiLvl));
  final double sg = const <double>[0.14, 0.06, 0.016][lvl];
  final double gw = (target.x2 - target.x1) / 2;
  final List<_Cand> cands = <_Cand>[];
  for (final Body p in mine) {
    for (final double ox in const <double>[-0.55, 0.0, 0.55]) {
      final double tx = e.cx + ox * gw;
      final double ty = target.y;
      double ux = tx - ball.x;
      double uy = ty - ball.y;
      double ul = math.sqrt(ux * ux + uy * uy);
      if (ul == 0) ul = 1.0;
      ux /= ul;
      uy /= ul;
      final double ccx = ball.x - ux * (p.r + ball.r + 1);
      final double ccy = ball.y - uy * (p.r + ball.r + 1);
      double vx = ccx - p.x;
      double vy = ccy - p.y;
      final double dist = math.sqrt(vx * vx + vy * vy);
      if (dist < 8) continue;
      vx /= dist;
      vy /= dist;
      final double al = vx * ux + vy * uy;
      if (al < 0.2 || !_clear(e, p, ccx, ccy)) continue;
      int blk = 0;
      for (final Body o in e.bodies) {
        if (o.team == me || o == ball) continue;
        if (segDist(o.x, o.y, ball.x, ball.y, tx, ty) < ball.r + o.r + 6) blk += 1;
      }
      final double sc = 100 * al - dist * 0.03 - blk * 28 + ((ball.y - ty).abs() < 420 ? 25.0 : 0.0);
      cands.add(_Cand(p, vx, vy, sc, dist, true, cands.length));
    }
    double wx = ball.x - p.x;
    double wy = ball.y - p.y;
    final double dist2 = math.sqrt(wx * wx + wy * wy);
    if (dist2 > 8) {
      wx /= dist2;
      wy /= dist2;
      if (_clear(e, p, ball.x, ball.y)) {
        final double toOwn = (wy * (og.y - ball.y) > 0) ? wy.abs() : 0.0;
        cands.add(_Cand(p, wx, wy, 10 - dist2 * 0.04 - toOwn * 55, dist2, false, cands.length));
      }
    }
  }
  if (cands.isEmpty) {
    Body? best;
    double bd = double.infinity;
    for (final Body p in mine) {
      final double dd = hyp(p.x - ball.x, p.y - ball.y);
      if (dd < bd) {
        bd = dd;
        best = p;
      }
    }
    if (best == null) return null;
    final double vx2 = ball.x - best.x;
    final double vy2 = ball.y - best.y;
    double d2 = math.sqrt(vx2 * vx2 + vy2 * vy2);
    if (d2 == 0) d2 = 1.0;
    cands.add(_Cand(best, vx2 / d2, vy2 / d2, 0.0, d2, false, 0));
  }
  cands.sort((_Cand a, _Cand b) {
    if (a.sc != b.sc) return a.sc > b.sc ? -1 : 1;
    return a.i.compareTo(b.i);
  });
  final int poolN = math.min(const <int>[4, 2, 1][lvl], cands.length);
  final _Cand c = cands[(e.rng.randf() * poolN).floor()];
  final double gauss = (e.rng.randf() + e.rng.randf() + e.rng.randf() - 1.5) * 1.15;
  final double ang = math.atan2(c.dy, c.dx) + gauss * sg;
  double pw = lvl == 2 ? _min(1, 0.66 + c.dist / 1000) : _min(1, 0.5 + c.dist / 1100);
  if (lvl == 0) pw *= 0.7 + e.rng.randf() * 0.3;
  if (c.atk && lvl > 0) pw = _max(pw, 0.78);
  return AiPlan(c.p, math.cos(ang), math.sin(ang), _max(0.3, pw) * LMAX);
}
