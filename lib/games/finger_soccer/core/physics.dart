import 'dart:math' as math;

import 'body.dart';
import 'config.dart';

/// Reference: test/games/tools/fs_physics_ref.ts (= supabase/functions/submit_shot/physics.ts).
/// Keep operation order identical. The optional [FsImpact] sink only RECORDS contacts for
/// visual juice; it never changes a number, so the determinism contract is unaffected.

/// A contact that happened during one fixed step (render-only information).
class FsImpact {
  const FsImpact({required this.x, required this.y, required this.strength, required this.wall});
  final double x;
  final double y;

  /// Closing speed (units/s) along the contact normal.
  final double strength;
  final bool wall;
}

List<FsBody> fsKickoffBodies() {
  const w = FsConfig.fieldW, h = FsConfig.fieldH;
  const base = <List<double>>[
    [0.30, 170],
    [0.70, 170],
    [0.50, 300],
    [0.22, 430],
    [0.78, 430],
  ];
  final bs = <FsBody>[];
  for (var i = 0; i < 5; i++) {
    bs.add(FsBody(id: i, kind: FsKind.disc, team: 0, r: FsConfig.discR, m: FsConfig.discMass, x: w * base[i][0], y: h - base[i][1]));
  }
  for (var i = 0; i < 5; i++) {
    bs.add(FsBody(id: 5 + i, kind: FsKind.disc, team: 1, r: FsConfig.discR, m: FsConfig.discMass, x: w * base[i][0], y: base[i][1]));
  }
  bs.add(FsBody(id: 10, kind: FsKind.ball, team: -1, r: FsConfig.ballR, m: FsConfig.ballMass, x: w / 2, y: h / 2));
  return bs;
}

const List<List<double>> fsPosts = [
  [FsConfig.mouthL, 0],
  [FsConfig.mouthR, 0],
  [FsConfig.mouthL, FsConfig.fieldH],
  [FsConfig.mouthR, FsConfig.fieldH],
];

void _collideStatic(FsBody b, double px, double py, double pr, List<FsImpact>? sink) {
  final dx = b.x - px, dy = b.y - py;
  final minD = b.r + pr;
  final d2 = dx * dx + dy * dy;
  if (d2 >= minD * minD) return;
  double nx = 1, ny = 0, d = 0;
  if (d2 > 0) {
    d = math.sqrt(d2);
    nx = dx / d;
    ny = dy / d;
  }
  b.x = px + nx * minD;
  b.y = py + ny * minD;
  final vn = b.vx * nx + b.vy * ny;
  if (vn < 0) {
    b.vx -= (1 + FsConfig.eWall) * vn * nx;
    b.vy -= (1 + FsConfig.eWall) * vn * ny;
    if (sink != null) sink.add(FsImpact(x: px, y: py, strength: -vn, wall: true));
  }
}

void _collidePair(FsBody a, FsBody b, List<FsImpact>? sink) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final minD = a.r + b.r;
  final d2 = dx * dx + dy * dy;
  if (d2 >= minD * minD) return;
  double nx = 1, ny = 0, d = 0;
  if (d2 > 0) {
    d = math.sqrt(d2);
    nx = dx / d;
    ny = dy / d;
  }
  final overlap = minD - d;
  final ia = 1 / a.m, ib = 1 / b.m, isum = ia + ib;
  a.x -= nx * overlap * (ia / isum);
  a.y -= ny * overlap * (ia / isum);
  b.x += nx * overlap * (ib / isum);
  b.y += ny * overlap * (ib / isum);
  final rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rv < 0) {
    final e = (a.isBall || b.isBall) ? FsConfig.eBall : FsConfig.eDisc;
    final j = -(1 + e) * rv / isum;
    a.vx -= j * ia * nx;
    a.vy -= j * ia * ny;
    b.vx += j * ib * nx;
    b.vy += j * ib * ny;
    if (sink != null) {
      sink.add(FsImpact(x: a.x + nx * a.r, y: a.y + ny * a.r, strength: -rv, wall: false));
    }
  }
}

void _walls(FsBody b, List<FsImpact>? sink) {
  const w = FsConfig.fieldW, h = FsConfig.fieldH, e = FsConfig.eWall;
  const mL = FsConfig.mouthL, mR = FsConfig.mouthR;
  if (b.x - b.r < 0) {
    b.x = b.r;
    if (b.vx < 0) {
      if (sink != null) sink.add(FsImpact(x: 0, y: b.y, strength: -b.vx, wall: true));
      b.vx = -b.vx * e;
    }
  }
  if (b.x + b.r > w) {
    b.x = w - b.r;
    if (b.vx > 0) {
      if (sink != null) sink.add(FsImpact(x: w, y: b.y, strength: b.vx, wall: true));
      b.vx = -b.vx * e;
    }
  }
  final inMouth = b.isBall && b.x > mL && b.x < mR;
  if (!inMouth) {
    if (b.y - b.r < 0) {
      b.y = b.r;
      if (b.vy < 0) {
        if (sink != null) sink.add(FsImpact(x: b.x, y: 0, strength: -b.vy, wall: true));
        b.vy = -b.vy * e;
      }
    }
    if (b.y + b.r > h) {
      b.y = h - b.r;
      if (b.vy > 0) {
        if (sink != null) sink.add(FsImpact(x: b.x, y: h, strength: b.vy, wall: true));
        b.vy = -b.vy * e;
      }
    }
  } else {
    if (b.y < 0) {
      if (b.x - b.r < mL) {
        b.x = mL + b.r;
        if (b.vx < 0) b.vx = -b.vx * e;
      }
      if (b.x + b.r > mR) {
        b.x = mR - b.r;
        if (b.vx > 0) b.vx = -b.vx * e;
      }
      if (b.y - b.r < -FsConfig.goalDepth) {
        b.y = -FsConfig.goalDepth + b.r;
        if (b.vy < 0) b.vy = -b.vy * e;
      }
    } else if (b.y > h) {
      if (b.x - b.r < mL) {
        b.x = mL + b.r;
        if (b.vx < 0) b.vx = -b.vx * e;
      }
      if (b.x + b.r > mR) {
        b.x = mR - b.r;
        if (b.vx > 0) b.vx = -b.vx * e;
      }
      if (b.y + b.r > h + FsConfig.goalDepth) {
        b.y = h + FsConfig.goalDepth - b.r;
        if (b.vy > 0) b.vy = -b.vy * e;
      }
    }
  }
}

/// One fixed step. Returns the scoring team (0 = bottom team scores in the top goal,
/// 1 = top team scores in the bottom goal) or -1.
int fsStep(List<FsBody> bs, [List<FsImpact>? sink]) {
  const dt = FsConfig.dt;
  final k = math.max(0.0, 1 - FsConfig.drag * dt);
  const s2 = FsConfig.stopSpeed * FsConfig.stopSpeed;
  for (var i = 0; i < bs.length; i++) {
    final b = bs[i];
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.vx *= k;
    b.vy *= k;
    if (b.vx * b.vx + b.vy * b.vy < s2) {
      b.vx = 0;
      b.vy = 0;
    }
  }
  for (var i = 0; i < bs.length; i++) {
    for (var p = 0; p < fsPosts.length; p++) {
      _collideStatic(bs[i], fsPosts[p][0], fsPosts[p][1], FsConfig.postR, sink);
    }
  }
  for (var i = 0; i < bs.length; i++) {
    for (var j = i + 1; j < bs.length; j++) {
      _collidePair(bs[i], bs[j], sink);
    }
  }
  for (var i = 0; i < bs.length; i++) {
    _walls(bs[i], sink);
  }
  final ball = bs[bs.length - 1];
  if (ball.y < -FsConfig.ballR) return 0;
  if (ball.y > FsConfig.fieldH + FsConfig.ballR) return 1;
  return -1;
}

bool fsIsSettled(List<FsBody> bs) {
  for (var i = 0; i < bs.length; i++) {
    if (bs[i].vx != 0 || bs[i].vy != 0) return false;
  }
  return true;
}

/// Incremental simulator: used headless (loop until done) and live (one tick per fixed dt).
class FsSimulator {
  FsSimulator(this.bodies, {this.impactSink});
  final List<FsBody> bodies;

  /// Optional render-only contact recorder (never affects the simulation).
  final List<FsImpact>? impactSink;
  int steps = 0;
  int scorer = -1;
  bool done = false;

  /// Returns true when the shot simulation has finished.
  bool tick() {
    if (done) return true;
    final sc = fsStep(bodies, impactSink);
    steps++;
    if (sc >= 0) {
      scorer = sc;
      done = true;
      return true;
    }
    if (fsIsSettled(bodies)) {
      done = true;
      return true;
    }
    if (steps >= FsConfig.maxSteps) {
      done = true;
      return true;
    }
    return false;
  }

  void runToEnd() {
    while (!tick()) {}
  }
}

void fsSnap(List<FsBody> bs) {
  for (var i = 0; i < bs.length; i++) {
    final b = bs[i];
    b.x = (b.x * 1000 + 0.5).floor() / 1000;
    b.y = (b.y * 1000 + 0.5).floor() / 1000;
    b.vx = 0;
    b.vy = 0;
  }
}

int fsStateHash(List<FsBody> bs) {
  var h = 2166136261;
  void mix(int v) {
    h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF;
    h = (h * 16777619) & 0xFFFFFFFF;
  }

  for (var i = 0; i < bs.length; i++) {
    mix((bs[i].x * 1000 + 0.5).floor());
    mix((bs[i].y * 1000 + 0.5).floor());
  }
  return h & 0xFFFFFFFF;
}
