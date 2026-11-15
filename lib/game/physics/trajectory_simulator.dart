// Aim preview: runs the SAME PhysicsWorld step on an isolated copy of the bodies (the live match state is never
// touched, no events, no randomness) and records the shooter's path up to its first contact with another body or
// its first rail / post bounce, plus where that contact sends the shooter and the struck body.
import 'dart:typed_data';

import 'body.dart';
import 'boundary_collision.dart';
import 'physics_config.dart';
import 'physics_world.dart';

class AimPrediction {
  /// shooter path points (x, y pairs), from the launch point to the first contact (inclusive)
  final Float64List path;
  final int n;

  /// first contact: 0 none (stopped / time out), 1 another body, 2 rail / post / net
  final int hit;
  final double hx, hy; // shooter centre at the first contact
  final double sx, sy; // shooter velocity right after the contact (direction of the bounce / deflection)
  final double tx, ty; // struck body velocity right after the contact (hit == 1), else 0
  final Body? target; // the struck body of the LIVE world (hit == 1)
  const AimPrediction(this.path, this.n, this.hit, this.hx, this.hy, this.sx, this.sy, this.tx, this.ty, this.target);
}

class _Rec implements PhysicsListener {
  final Body shooter;
  int hit = 0;
  Body? other;
  double hx = 0, hy = 0, sx = 0, sy = 0, tx = 0, ty = 0;
  _Rec(this.shooter);
  void _snap() {
    hx = shooter.x;
    hy = shooter.y;
    sx = shooter.vx;
    sy = shooter.vy;
    tx = other?.vx ?? 0;
    ty = other?.vy ?? 0;
  }

  @override
  void onPair(Body a, Body b, double vn) {
    if (hit != 0) return;
    if (identical(a, shooter)) {
      hit = 1;
      other = b;
      _snap();
    } else if (identical(b, shooter)) {
      hit = 1;
      other = a;
      _snap();
    }
  }

  @override
  void onStatic(Body o, EdgeKind kind, double vn) {
    if (hit == 0 && identical(o, shooter)) {
      hit = 2;
      _snap();
    }
  }

  @override
  void afterSubstep() {}
}

class TrajectorySimulator {
  final PhysicsConfig c;
  final Boundary bd;
  final Float64List _pts = Float64List(2 * 400);
  TrajectorySimulator(this.c, this.bd);

  /// predict the shot of [shooter] (a body of [live]) leaving at (vx, vy); at most [maxT] seconds simulated
  AimPrediction predict(List<Body> live, Body shooter, double vx, double vy, {double maxT = 2.5}) {
    final copy = <Body>[];
    Body? me;
    for (final b in live) {
      final k = b.clonePhys();
      if (identical(b, shooter)) {
        k.vx = vx;
        k.vy = vy;
        me = k;
      }
      copy.add(k);
    }
    final s = me!;
    final rec = _Rec(s);
    final w = PhysicsWorld(c, bd, copy, listener: rec)..eject = false;
    var n = 0;
    _pts[n++] = s.x;
    _pts[n++] = s.y;
    final steps = (maxT / c.step).ceil();
    for (var i = 0; i < steps && rec.hit == 0 && !s.asleep; i++) {
      w.step(c.step);
      if (i % 3 == 2 && n < _pts.length - 2) {
        _pts[n++] = s.x;
        _pts[n++] = s.y;
      }
    }
    if (rec.hit == 0) {
      rec.hx = s.x;
      rec.hy = s.y;
    }
    if (n < _pts.length - 1) {
      // the path ends exactly at the contact point
      if (rec.hit != 0 && n >= 4) n -= 2;
      _pts[n++] = rec.hx;
      _pts[n++] = rec.hy;
    }
    Body? target;
    if (rec.hit == 1) {
      for (final b in live) {
        if (b.id == rec.other!.id) target = b;
      }
    }
    return AimPrediction(Float64List.fromList(_pts.sublist(0, n)), n ~/ 2, rec.hit, rec.hx, rec.hy, rec.sx, rec.sy, rec.tx, rec.ty, target);
  }
}
