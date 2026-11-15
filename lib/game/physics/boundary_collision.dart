// Static boundary geometry of the pitch: rails (one-sided segments), rounded corners (concave arcs), goal posts
// (circles) and goal nets (segments). Every normal points into the region a body may occupy, so a body's response
// is always computed from the true contact normal (no forced directions).
//
//   corner = end rail segment + side rail segment joined by a concave arc of radius cornerR (tangent to both):
//   a body entering the corner rolls round the arc and leaves along the other rail; the outgoing direction follows
//   from where it touched the arc (contact normal), a straight-diagonal hit comes straight back.
import 'dart:math' as math;

import 'body.dart';
import 'physics_config.dart';

enum EdgeKind { rail, net, post, corner }

class Seg {
  final double ax, ay, ux, uy, len, nx, ny;
  final EdgeKind kind;
  const Seg(this.ax, this.ay, this.ux, this.uy, this.len, this.nx, this.ny, this.kind);
  factory Seg.of(double x0, double y0, double x1, double y1, double nx, double ny, EdgeKind k) {
    final dx = x1 - x0, dy = y1 - y0, l = math.sqrt(dx * dx + dy * dy);
    return Seg(x0, y0, dx / l, dy / l, l, nx, ny, k);
  }
}

/// concave quarter arc: the body stays INSIDE the circle (cx, cy, rad) while in the quadrant (sx, sy) of its centre
class Arc {
  final double cx, cy, rad, sx, sy;
  const Arc(this.cx, this.cy, this.rad, this.sx, this.sy);
}

class Post {
  final double x, y, rad;
  const Post(this.x, this.y, this.rad);
}

class Boundary {
  final double l, r, t, b; // play rectangle (rail lines)
  final List<Goal> goals;
  final double depth;
  final List<Seg> segs = [];
  final List<Arc> arcs = [];
  final List<Post> posts = [];

  Boundary(this.l, this.r, this.t, this.b, this.goals, this.depth, PhysicsConfig c) {
    final rc = c.cornerR;
    segs
      ..add(Seg.of(l, t + rc, l, b - rc, 1, 0, EdgeKind.rail))
      ..add(Seg.of(r, t + rc, r, b - rc, -1, 0, EdgeKind.rail));
    for (final g in goals) {
      final y = g.y, ny = -g.d.toDouble(); // rail normal points back into the pitch
      segs
        ..add(Seg.of(l + rc, y, g.x1, y, 0, ny, EdgeKind.rail))
        ..add(Seg.of(g.x2, y, r - rc, y, 0, ny, EdgeKind.rail));
      final yb = y + g.d * depth;
      segs
        ..add(Seg.of(g.x1, y, g.x1, yb, 1, 0, EdgeKind.net))
        ..add(Seg.of(g.x2, y, g.x2, yb, -1, 0, EdgeKind.net))
        ..add(Seg.of(g.x1, yb, g.x2, yb, 0, ny, EdgeKind.net));
      posts
        ..add(Post(g.x1, y, c.postR))
        ..add(Post(g.x2, y, c.postR));
    }
    arcs
      ..add(Arc(l + rc, t + rc, rc, -1, -1))
      ..add(Arc(r - rc, t + rc, rc, 1, -1))
      ..add(Arc(l + rc, b - rc, rc, -1, 1))
      ..add(Arc(r - rc, b - rc, rc, 1, 1));
  }

  /// goal whose mouth the point (x, y) is behind (inside the net), or null
  Goal? goalAt(double x, double y) {
    for (final g in goals) {
      if (g.d * (y - g.y) > 0 && x > g.x1 && x < g.x2) return g;
    }
    return null;
  }

  /// last-resort containment (never expected to act; guarantees no body ever leaves the pitch + goals)
  void contain(Body o) {
    final rr = o.r;
    final g = goalAt(o.x, o.y);
    if (g != null) {
      final lo = g.x1 + rr, hi = g.x2 - rr;
      if (lo <= hi) o.x = o.x < lo ? lo : (o.x > hi ? hi : o.x);
      final back = g.y + g.d * (depth - rr);
      if (g.d * (o.y - back) > 0) o.y = back;
      return;
    }
    if (o.x < l + rr) o.x = l + rr;
    if (o.x > r - rr) o.x = r - rr;
    final inMouthX = o.x > goals[0].x1 && o.x < goals[0].x2;
    if (!inMouthX) {
      if (o.y < t + rr) o.y = t + rr;
      if (o.y > b - rr) o.y = b - rr;
    } else {
      final yt = t - depth + rr, yb = b + depth - rr;
      if (o.y < yt) o.y = yt;
      if (o.y > yb) o.y = yb;
    }
  }
}
