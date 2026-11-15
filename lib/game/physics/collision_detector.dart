// Continuous (swept) collision detection: time of first impact within [0, tMax] for straight-line motion over one
// substep. Circle-circle, circle vs one-sided segment, circle vs post (static circle) and circle inside a concave
// corner arc. A contact already touching / slightly overlapping and still approaching returns 0.
// Every function returns -1 when there is no impact in the window.
import 'dart:math' as math;

import 'body.dart';
import 'boundary_collision.dart';

/// smallest t in [0, tMax] at which |q + v t| == rr, q = relative position, v = relative velocity (approaching)
double _sweptCircle(double qx, double qy, double vx, double vy, double rr, double tMax) {
  final qv = qx * vx + qy * vy;
  if (qv >= -1e-6) return -1; // separating or tangent (tolerance: no zero-progress re-contacts)
  final qq = qx * qx + qy * qy, r2 = rr * rr;
  if (qq <= r2) return 0; // touching / overlapping and approaching
  final vv = vx * vx + vy * vy;
  if (vv < 1e-12) return -1;
  final disc = qv * qv - vv * (qq - r2);
  if (disc < 0) return -1;
  final t = (-qv - math.sqrt(disc)) / vv;
  return t <= tMax ? (t < 0 ? 0 : t) : -1;
}

/// two moving bodies
double toiPair(Body a, Body b, double tMax) =>
    _sweptCircle(b.x - a.x, b.y - a.y, b.vx - a.vx, b.vy - a.vy, a.r + b.r, tMax);

/// body vs a goal post (static circle)
double toiPost(Body o, Post p, double tMax) => _sweptCircle(o.x - p.x, o.y - p.y, o.vx, o.vy, o.r + p.rad, tMax);

/// body vs a one-sided segment (the body is on the normal side)
double toiSeg(Body o, Seg s, double tMax) {
  final vn = o.vx * s.nx + o.vy * s.ny;
  if (vn >= -1e-6) return -1;
  final dc = (o.x - s.ax) * s.nx + (o.y - s.ay) * s.ny; // centre distance from the rail line
  if (dc < 0) return -1; // centre behind the rail: not this rail's business
  final gap = dc - o.r;
  final t = gap <= 0 ? 0.0 : gap / -vn;
  if (t > tMax) return -1;
  final q = (o.x + o.vx * t - s.ax) * s.ux + (o.y + o.vy * t - s.ay) * s.uy;
  return (q >= 0 && q <= s.len) ? t : -1;
}

/// body inside a concave corner arc: first t at which it reaches the arc (moving outwards) inside the quadrant
double toiArc(Body o, Arc a, double tMax) {
  final rr = a.rad - o.r;
  if (rr <= 0) return -1;
  final qx = o.x - a.cx, qy = o.y - a.cy;
  final qv = qx * o.vx + qy * o.vy;
  if (qv <= 1e-6) return -1; // moving inwards
  final qq = qx * qx + qy * qy;
  double t;
  if (qq >= rr * rr) {
    t = 0;
  } else {
    final vv = o.vx * o.vx + o.vy * o.vy;
    final disc = qv * qv - vv * (qq - rr * rr);
    t = (-qv + math.sqrt(disc)) / vv;
    if (t > tMax) return -1;
  }
  final cx = qx + o.vx * t, cy = qy + o.vy * t;
  return (cx * a.sx >= 0 && cy * a.sy >= 0) ? t : -1;
}
