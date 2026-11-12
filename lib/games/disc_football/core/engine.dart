// NEXORA Disc Football physics engine — 1:1 Dart port of nexora-universe/src/game/engine.ts.
// Fixed 240 Hz sub-stepping, impulse-based circle collisions with positional correction,
// rolling 3D ball rotation, render interpolation (prev -> current).
// Pure Dart (no Flutter imports). Every constant and every operation mirrors the TS source;
// Math.hypot is reproduced bit-for-bit (V8's Kahan-compensated algorithm) so the golden test
// against engine.ts stays tight. Randomness is injectable for determinism.
import 'dart:math' as math;

import 'data.dart';

const double K = 1.27;
const double PR = 49; // piece radius (world units)
const double BR = 25.5; // ball radius
const double RC = 70; // rounded corner radius
const double LMAX = 210; // max drag length for full power
const double STEP = 1 / 240;
const double POST_R = 8; // goal-post radius
const double _HV = 8, _EPP = .62, _PCAP = 190;
const double _BK = 1.9, _BF = 175, _BFV = 140, _BVMAX = 1750, _BSTOP = 26;
const double _PK = 1.55, _PFL = 300, _PFV = 230, _PSTOP = 20;
const double _WALL_VOUT = 820, _POST_VOUT = 900;

/// V8 Math.hypot for two values (max-scaled, Kahan-compensated sum).
double hyp(double a, double b) {
  a = a.abs();
  b = b.abs();
  if (a.isInfinite || b.isInfinite) return double.infinity;
  if (a.isNaN || b.isNaN) return double.nan;
  final double m = a > b ? a : b;
  if (m == 0) return 0;
  double sum = 0, comp = 0;
  double n = a / m;
  double summand = n * n - comp;
  double prelim = sum + summand;
  comp = (prelim - sum) - summand;
  sum = prelim;
  n = b / m;
  summand = n * n - comp;
  prelim = sum + summand;
  comp = (prelim - sum) - summand;
  sum = prelim;
  return math.sqrt(sum) * m;
}

/// V8 Math.hypot for three values.
double hyp3(double a, double b, double c) {
  a = a.abs();
  b = b.abs();
  c = c.abs();
  if (a.isInfinite || b.isInfinite || c.isInfinite) return double.infinity;
  if (a.isNaN || b.isNaN || c.isNaN) return double.nan;
  double m = a > b ? a : b;
  if (c > m) m = c;
  if (m == 0) return 0;
  double sum = 0, comp = 0;
  for (final double v in <double>[a, b, c]) {
    final double n = v / m;
    final double summand = n * n - comp;
    final double prelim = sum + summand;
    comp = (prelim - sum) - summand;
    sum = prelim;
  }
  return math.sqrt(sum) * m;
}

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

class TrailPt {
  TrailPt(this.x, this.y, this.a);
  double x;
  double y;
  double a;
}

class Pt {
  Pt(this.x, this.y);
  double x;
  double y;
}

class Goal {
  Goal({required this.team, required this.y, required this.x1, required this.x2, required this.d});
  final int team;
  final double y;
  final double x1;
  final double x2;

  /// -1 = top goal (team 0 scores here), +1 = bottom goal.
  final int d;
}

class Body {
  Body(this.id, this.team, this.x, this.y, this.r, double m)
      : px = x,
        py = y,
        im = 1 / m;
  final int id;

  /// 0 / 1 = discs, 2 = ball.
  final int team;
  double x;
  double y;
  double px;
  double py;
  double vx = 0;
  double vy = 0;
  final double r;
  final double im;
  double spin = 0;
  double ang = 0;
  final List<double> R = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  double sq = 0;
  double tvx = 0;
  double tvy = 0;
  double ramp = 0;
  double boost = 0;
  double vox = 0;
  double voy = 0;
  Goal? gout;
  final List<Pt> tr = <Pt>[];
}

class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.l, this.m, this.r, this.c, this.k, this.g);
  double x;
  double y;
  double vx;
  double vy;
  double l;
  final double m;
  final double r;
  final int c; // ARGB
  final int k;
  final double g;
}

enum Phase { aim, move, goal, over }

Phase phaseFromName(String s) {
  for (final Phase p in Phase.values) {
    if (p.name == s) return p;
  }
  return Phase.aim;
}

/// Engine event (union of the TS EngineEvent variants, discriminated by [t]).
class EngineEvent {
  const EngineEvent._(this.t, {this.ball = false, this.power = 0, this.team = 0, this.nogoal = false, this.score});
  const EngineEvent.hit({required bool ball, required double power}) : this._('hit', ball: ball, power: power);
  const EngineEvent.wall(double power) : this._('wall', power: power);
  const EngineEvent.post(double power) : this._('post', power: power);
  const EngineEvent.goal(int team, bool nogoal) : this._('goal', team: team, nogoal: nogoal);
  const EngineEvent.turn(int team) : this._('turn', team: team);
  const EngineEvent.shot(int team) : this._('shot', team: team);
  const EngineEvent.end(List<int> score) : this._('end', score: score);
  const EngineEvent.clock() : this._('clock');

  /// 'hit' | 'wall' | 'post' | 'goal' | 'turn' | 'shot' | 'end' | 'clock'
  final String t;
  final bool ball;
  final double power;
  final int team;
  final bool nogoal;
  final List<int>? score;
}

class DiscStats {
  const DiscStats({required this.power, required this.accuracy});
  final double power;
  final double accuracy;
}

class MatchCfg {
  MatchCfg({
    required this.field,
    required this.ball,
    required this.forms,
    required this.ai,
    required this.aiLvl,
    required this.limit,
    required this.matchTime,
    required this.turnTime,
    required this.vip,
    required this.first,
    this.stats,
  });
  final int field;
  final int ball;
  final List<int> forms;
  final bool ai;
  final int aiLvl; // 0..2
  final int limit;
  final double matchTime;
  final double turnTime;
  final List<bool> vip;
  final int first;

  /// disc stats per team (power scales impulse, accuracy controls aim deviation + preview length)
  List<DiscStats>? stats;
}

double powerMul(double p) => .75 + (_min(10, _max(1, p)) - 1) / 9 * .5;
double aimDevDeg(double a) => (10 - _min(10, _max(1, a))) / 9 * 4;
double aimPreview(double a) => .45 + (_min(10, _max(1, a)) - 1) / 9 * .75;

void _rotate(List<double> R, double wx, double wy, double wz, double dt) {
  final double w = hyp3(wx, wy, wz), th = w * dt;
  if (th < 1e-7) return;
  final double ax = wx / w, ay = wy / w, az = wz / w, c = math.cos(th), s = math.sin(th), t = 1 - c;
  final double m0 = t * ax * ax + c, m1 = t * ax * ay - s * az, m2 = t * ax * az + s * ay;
  final double m3 = t * ax * ay + s * az, m4 = t * ay * ay + c, m5 = t * ay * az - s * ax;
  final double m6 = t * ax * az - s * ay, m7 = t * ay * az + s * ax, m8 = t * az * az + c;
  final List<double> r = List<double>.of(R);
  R[0] = m0 * r[0] + m1 * r[3] + m2 * r[6];
  R[1] = m0 * r[1] + m1 * r[4] + m2 * r[7];
  R[2] = m0 * r[2] + m1 * r[5] + m2 * r[8];
  R[3] = m3 * r[0] + m4 * r[3] + m5 * r[6];
  R[4] = m3 * r[1] + m4 * r[4] + m5 * r[7];
  R[5] = m3 * r[2] + m4 * r[5] + m5 * r[8];
  R[6] = m6 * r[0] + m7 * r[3] + m8 * r[6];
  R[7] = m6 * r[1] + m7 * r[4] + m8 * r[7];
  R[8] = m6 * r[2] + m7 * r[5] + m8 * r[8];
  final double l0 = hyp3(R[0], R[1], R[2]);
  R[0] /= l0;
  R[1] /= l0;
  R[2] /= l0;
}

class Rect4 {
  Rect4(this.l, this.r, this.t, this.b);
  final double l;
  final double r;
  final double t;
  final double b;
}

class Drag {
  Drag({required this.b, required this.sx, required this.sy, required this.cx, required this.cy, this.ai = false});
  final Body b;
  final double sx;
  final double sy;
  double cx;
  double cy;
  final bool ai;
}

class AimInfo {
  AimInfo(this.b, this.p, this.ux, this.uy);
  final Body b;
  final double p;
  final double ux;
  final double uy;
}

class AiPlan {
  AiPlan(this.b, this.dx, this.dy, this.l);
  final Body b;
  final double dx;
  final double dy;
  final double l;
  double t = 0;
}

class _Cand {
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk);
  final Body p;
  final double dx;
  final double dy;
  final double sc;
  final double dist;
  final int atk;
}

/// Stable sort (JS Array.prototype.sort is stable; Dart's List.sort is not guaranteed to be).
void _stableSort<T>(List<T> a, int Function(T x, T y) cmp) {
  for (int i = 1; i < a.length; i++) {
    final T v = a[i];
    int j = i - 1;
    while (j >= 0 && cmp(a[j], v) > 0) {
      a[j + 1] = a[j];
      j--;
    }
    a[j + 1] = v;
  }
}

const List<int> _kHitCols = <int>[0xFFFFFFFF, 0xFF9FE8FF, 0xFF5CB6FF];
const List<int> _kGoalCols = <int>[0xFFFFD23A, 0xFFFFFFFF, 0xFF3BD0FF, 0xFFFF4A7A, 0xFF7BFF5A];

class Engine {
  Engine(this.cfg, {double Function()? random}) : rnd = random ?? math.Random().nextDouble {
    f = cfg.field >= 0 && cfg.field < kFields.length ? kFields[cfg.field] : kFields[0];
    F = Rect4(f.l + 4, f.r - 4, f.t + 4, f.b - 4);
    CX = (F.l + F.r) / 2;
    CY = (F.t + F.b) / 2;
    KY = f.cs;
    final List<double> gi = kGS[f.gs]!;
    final double gw = 2 * f.g / (gi[3] - gi[2]);
    GGw = gw;
    GGh = gw * gi[1] / gi[0] * 1.28;
    GGx = CX - f.g - gi[2] * gw;
    DEPTH = _max(120, jsRound(GGh * .98));
    goals = <Goal>[
      Goal(team: 0, y: F.t, x1: CX - f.g, x2: CX + f.g, d: -1),
      Goal(team: 1, y: F.b, x1: CX - f.g, x2: CX + f.g, d: 1),
    ];
    mleft = cfg.matchTime;
    tleft = cfg.turnTime;
    reset(cfg.first);
  }

  final MatchCfg cfg;
  final double Function() rnd;
  late final Field f;
  late final Rect4 F;
  late final double CX;
  late final double CY;
  late final double KY;
  late final List<Goal> goals;
  late final double GGw;
  late final double GGh;
  late final double GGx;
  double DEPTH = 120;
  List<Body> bodies = <Body>[];
  late Body ball;
  final List<Particle> parts = <Particle>[];
  final List<TrailPt> trail = <TrailPt>[];
  List<int> score = <int>[0, 0];
  int turn = 0;
  Phase phase = Phase.aim;
  int shots = 0;
  double idle = 0;
  double pause = 0;
  int kick = 0;
  double acc = 0;
  double slow = 0;
  double flash = 0;
  double cam = 0;
  final List<double> shake = <double>[0, 0];
  final List<double> ripple = <double>[0, 0];
  final List<double> rippleX = <double>[0, 0];
  double mleft = 0;
  double tleft = 0;
  bool sudden = false;
  double aiT = 0;
  AiPlan? aiPlan;
  Drag? drag;
  final List<EngineEvent> events = <EngineEvent>[];
  double time = 0;
  int lastWho = 0;
  double lastPower = 0;

  /// online: per-team AI takeover (a team with no connected human is played by the bot)
  List<bool> aiTeams = <bool>[false, false];

  Body _mk(double x, double y, int team, double r, double m, int id) => Body(id, team, x, y, r, m);

  void reset(int kickTeam) {
    final double fw = F.r - F.l, fh = F.b - F.t;
    bodies = <Body>[];
    trail.clear();
    parts.clear();
    slow = 0;
    cam = 0;
    for (int cm = 0; cm < 2; cm++) {
      final List<List<double>> sl = slots(cfg.forms[cm]);
      for (int i = 0; i < sl.length; i++) {
        final double nx = sl[i][0], ny = sl[i][1];
        final double x = F.l + PR + 10 + nx * (fw - 2 * (PR + 10)), y = cm == 1 ? F.t + ny * fh : F.b - ny * fh;
        bodies.add(_mk(x, y, cm, PR, 5, cm * 20 + i));
      }
    }
    ball = _mk(CX, KY, 2, BR, 1.5, 99);
    bodies.add(ball);
    turn = kickTeam;
    phase = Phase.aim;
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    events.add(EngineEvent.turn(turn));
  }

  bool isAiTurn() => (cfg.ai && turn == 1) || aiTeams[turn];
  bool canControl() => phase == Phase.aim && !isAiTurn();

  // ---------- input ----------
  bool pick(double x, double y) {
    if (!canControl()) return false;
    Body? f0;
    double bd = 1e9;
    for (final Body b in bodies) {
      if (b.team == turn && b != ball) {
        final double d = hyp(x - b.x, y - b.y);
        if (d < b.r + 34 && d < bd) {
          f0 = b;
          bd = d;
        }
      }
    }
    if (f0 == null) return false;
    drag = Drag(b: f0, sx: f0.x, sy: f0.y, cx: x, cy: y);
    return true;
  }

  void move(double x, double y) {
    final Drag? d = drag;
    if (d != null && !d.ai) {
      d.cx = x;
      d.cy = y;
    }
  }

  void release() {
    final Drag? d = drag;
    if (d == null || d.ai) return;
    drag = null;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && phase == Phase.aim) fire(d.b, dx, dy, l, human: true);
  }

  void cancel() {
    if (drag != null && !drag!.ai) drag = null;
  }

  AimInfo? aimInfo() {
    final Drag? d = drag;
    if (d == null) return null;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l < 18) return AimInfo(d.b, 0, 0, 0);
    return AimInfo(d.b, _min(l, LMAX) / LMAX, dx / l, dy / l);
  }

  DiscStats statsOf(int team) {
    final List<DiscStats>? s = cfg.stats;
    return s != null ? s[team] : const DiscStats(power: 5, accuracy: 5);
  }

  /// human = a player's flick: disc accuracy adds a small random deviation
  void fire(Body b, double dx, double dy, double l, {bool human = false}) {
    final double p = _min(l, LMAX) / LMAX;
    final int team = b.team;
    lastPower = p;
    double v = (260 + 1085 * math.pow(p, .8).toDouble()) * K * 1.32;
    if (cfg.stats != null) {
      v *= powerMul(statsOf(team).power);
    } else if (cfg.vip[team]) {
      v *= 1.16;
    }
    double ux = dx / l, uy = dy / l;
    if (human && cfg.stats != null) {
      final double dev = aimDevDeg(statsOf(team).accuracy) * math.pi / 180;
      if (dev > 0) {
        final double a = math.atan2(uy, ux) + (rnd() + rnd() - 1) * dev;
        ux = math.cos(a);
        uy = math.sin(a);
      }
    }
    final double vx = ux * v, vy = uy * v;
    b.tvx = vx * 1.02;
    b.tvy = vy * 1.02;
    b.ramp = .06;
    b.vx = vx * .5;
    b.vy = vy * .5;
    b.boost = .22;
    phase = Phase.move;
    idle = 0;
    shots++;
    drag = null;
    cam = _max(cam, .18);
    lastWho = b.team;
    events.add(EngineEvent.shot(b.team));
  }

  // ---------- simulation ----------
  void _walls(Body b) {
    final Rect4 f0 = F;
    if (b != ball && b.gout != null) {
      final Goal g = b.gout!;
      final double dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final bool bl = b == ball;
    final double r = b.r, vs = hyp(b.vx, b.vy);
    double eN(double vn) => bl
        ? _min(.64 - .24 * _clamp((vn - 270 * K) / (730 * K), 0, 1), _WALL_VOUT * K / _max(1, vn))
        : _min(.72, _WALL_VOUT * 1.4 * K / _max(1, vn));
    if (b.x - r < f0.l) {
      b.x = f0.l + r;
      if (b.vx < 0) {
        if (bl && vs > 200) events.add(EngineEvent.wall(vs / 1800));
        b.vx *= -eN(-b.vx);
        b.spin += b.vy / r * .05;
      }
    }
    if (b.x + r > f0.r) {
      b.x = f0.r - r;
      if (b.vx > 0) {
        if (bl && vs > 200) events.add(EngineEvent.wall(vs / 1800));
        b.vx *= -eN(b.vx);
        b.spin -= b.vy / r * .05;
      }
    }
    for (final Goal g in goals) {
      final double dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final double lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final bool inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final bool gl = phase == Phase.goal && bl;
        final double eb = gl ? .2 : eN(b.vy.abs()), back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          b.vy = -g.d * b.vy.abs() * eb;
          if (gl) b.vx *= .6;
        }
        if (dp > (bl ? r * .6 : 0)) {
          final double ee = gl ? .3 : eN(b.vx.abs());
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) b.vx *= -ee;
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) b.vx *= -ee;
          }
        }
      } else {
        if (bl && vs > 200 && g.d * b.vy > 0) events.add(EngineEvent.wall(vs / 1800));
        b.y = g.y - g.d * r;
        if (g.d * b.vy > 0) b.vy = -g.d * b.vy.abs() * eN(b.vy.abs());
        b.spin += g.d * b.vx / r * .05;
      }
    }
    final List<List<double>> corners = <List<double>>[
      <double>[f0.l + RC, f0.t + RC, 1, 1],
      <double>[f0.r - RC, f0.t + RC, -1, 1],
      <double>[f0.l + RC, f0.b - RC, 1, -1],
      <double>[f0.r - RC, f0.b - RC, -1, -1],
    ];
    for (final List<double> c in corners) {
      final double cx = c[0], cy = c[1], sx = c[2], sy = c[3];
      if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
        final double dx = b.x - cx, dy = b.y - cy, d = hyp(dx, dy), lim = RC - r;
        if (d > lim && d > 0) {
          final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
          b.x = cx + nx * lim;
          b.y = cy + ny * lim;
          if (vn > 0) {
            final double ec = eN(vn);
            b.vx -= (1 + ec) * vn * nx;
            b.vy -= (1 + ec) * vn * ny;
          }
        }
      }
    }
  }

  void _post(Body b, double px, double py) {
    final double dx = b.x - px, dy = b.y - py, d = hyp(dx, dy), m = b.r + POST_R;
    if (d >= m || d == 0) return;
    final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      final double kp = 1 + _min(.62 - .14 * _min(1, -vn / (2000 * K)), _POST_VOUT * K / _max(1, -vn));
      b.vx -= kp * vn * nx;
      b.vy -= kp * vn * ny;
      if (b == ball) events.add(EngineEvent.post(-vn / 1800));
      if (b == ball && -vn > 900 * K) cam = _max(cam, .25);
    }
  }

  void _hit(Body a, Body b) {
    double dx = b.x - a.x, dy = b.y - a.y, d = hyp(dx, dy);
    final double m = a.r + b.r;
    if (d >= m) return;
    if (d < 1e-4) {
      dx = 1;
      dy = 0;
      d = 1;
    }
    final Body bl = ball;
    final double nx = dx / d, ny = dy / d, sm = a.im + b.im;
    final bool isB = a == bl || b == bl;
    double ka = isB && a != bl ? 1 / _HV : 1, kb = isB && b != bl ? 1 / _HV : 1;
    if (!isB) {
      final double sa = hyp(a.vx, a.vy), sb = hyp(b.vx, b.vy);
      if (sa > sb) {
        kb = .85;
      } else {
        ka = .85;
      }
    }
    double wa = a.im / sm * ka, wb = b.im / sm * kb;
    if (isB) {
      if (a == bl) {
        wa = 1 - wb;
      } else {
        wb = 1 - wa;
      }
    }
    final double pen = _max(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa;
    a.y -= ny * pen * wa;
    b.x += nx * pen * wb;
    b.y += ny * pen * wb;
    a.vox = _clamp(a.vox + nx * pen * wa, -9, 9);
    a.voy = _clamp(a.voy + ny * pen * wa, -9, 9);
    b.vox = _clamp(b.vox - nx * pen * wb, -9, 9);
    b.voy = _clamp(b.voy - ny * pen * wb, -9, 9);
    final double vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (vn >= 0) return;
    final double e = vn < -40 * K ? (isB ? .68 - .12 * _clamp((-vn - 500 * K) / (1200 * K), 0, 1) : _EPP) : 0;
    final double j = -(1 + e) * vn / sm;
    final Body? pa = isB ? (a == bl ? b : a) : null;
    final double pre = pa != null ? hyp(pa.vx, pa.vy) : 0;
    a.vx -= j * nx * a.im * ka;
    a.vy -= j * ny * a.im * ka;
    b.vx += j * nx * b.im * kb;
    b.vy += j * ny * b.im * kb;
    if (pa != null && pre < 260 * K) {
      final double ps = hyp(pa.vx, pa.vy), cp = _PCAP * K;
      if (ps > cp) {
        pa.vx *= cp / ps;
        pa.vy *= cp / ps;
      }
    }
    if (vn < -120 * K) {
      events.add(EngineEvent.hit(ball: isB, power: -vn / 1900));
      if (!isB && vn < -420 * K) {
        final double q = _min(1, -vn / (1500 * K));
        a.sq = _max(a.sq, q);
        b.sq = _max(b.sq, q);
      }
    }
    if (isB) {
      bl.spin += (bl == b ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / bl.r * .3;
      bl.spin = _clamp(bl.spin, -34, 34);
      final double pw = _min(1, -vn / (1700 * K));
      if (pw > .2) {
        final Body o = bl == b ? a : b;
        bl.sq = _max(bl.sq, pw);
        o.sq = _max(o.sq, pw * .7);
        cam = _max(cam, pw * .4);
        final double cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2;
        burst(cx, cy, jsRound(6 + pw * 10).toInt(), 260 + pw * 300, _kHitCols, .35, 2);
      }
    }
  }

  void _sim(double dt) {
    final Body bl = ball;
    for (final Body b in bodies) {
      if (b.ramp > 0) {
        final double k = _min(1, dt / b.ramp);
        b.vx += (b.tvx - b.vx) * k;
        b.vy += (b.tvy - b.vy) * k;
        b.ramp -= dt;
        if (b.ramp <= 0) b.ramp = 0;
      }
      if (b.vox != 0 || b.voy != 0) {
        final double q = 1 - _min(1, dt * 15);
        b.vox *= q;
        b.voy *= q;
        if (b.vox.abs() < .04) b.vox = 0;
        if (b.voy.abs() < .04) b.voy = 0;
      }
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      final double sp = hyp(b.vx, b.vy);
      final bool isBall = b == bl;
      if (sp > 0) {
        if (isBall) {
          double ns = sp * math.exp(-_BK * dt) - _BF * K * _min(1, sp / (_BFV * K)) * dt;
          if (ns < _BSTOP * K) {
            b.vx = 0;
            b.vy = 0;
            b.vox = 0;
            b.voy = 0;
          } else {
            ns = _min(ns, _BVMAX * K);
            final double k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        } else {
          final double fb = b.boost > 0 ? .35 : 1.0;
          if (b.boost > 0) b.boost -= dt;
          double ns = sp * math.exp(-_PK * fb * dt) - _PFL * K * _min(1, sp / (_PFV * K)) * fb * dt;
          if (ns < _PSTOP * K && b.ramp <= 0) {
            b.vx = 0;
            b.vy = 0;
          } else {
            ns = _max(0, _min(ns, 2800 * K));
            final double k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
      }
      if (isBall) {
        final double sp2 = hyp(b.vx, b.vy);
        b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt;
        if (b.spin.abs() < .02) b.spin = 0;
        final double roll = .95 / b.r;
        if (sp2 > 0 || b.spin != 0) _rotate(b.R, -b.vy * roll, b.vx * roll, b.spin * .55, dt);
        b.ang += b.spin * dt;
      } else {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      b.sq *= 1 - 9 * dt;
      _walls(b);
    }
    final List<Body> B = bodies;
    for (int it = 0; it < 2; it++) {
      for (int a = 0; a < B.length; a++) {
        for (int c = a + 1; c < B.length; c++) {
          _hit(B[a], B[c]);
        }
      }
    }
    for (final Goal g in goals) {
      for (final Body b in B) {
        _post(b, g.x1, g.y);
        _post(b, g.x2, g.y);
      }
    }
    for (final Body b in B) {
      _walls(b);
    }
    if (phase == Phase.move) {
      for (final Goal g in goals) {
        if (bl.x > g.x1 && bl.x < g.x2 && (g.d < 0 ? bl.y < g.y - bl.r * .8 : bl.y > g.y + bl.r * .8)) _scored(g.team);
      }
    }
  }

  void _scored(int t) {
    final bool nogoal = shots <= 1;
    events.add(EngineEvent.goal(t, nogoal));
    if (nogoal) {
      phase = Phase.goal;
      pause = 1.4;
      kick = turn;
      return;
    }
    ripple[t] = 1;
    rippleX[t] = ball.x;
    score[t]++;
    pause = 2.0;
    flash = 1;
    shake[t] = .6;
    phase = Phase.goal;
    kick = 1 - t;
    slow = 1.1;
    cam = 1.4;
    final Goal g = goals[t];
    burst(ball.x, g.y, 80, 760, _kGoalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _kGoalCols, 1.8, 3);
  }

  void burst(double x, double y, int n, double sp, List<int> cols, double life, [int k = 0]) {
    if (parts.length > 420) return;
    for (int i = 0; i < n; i++) {
      final double a = rnd() * math.pi * 2, v = sp * (.3 + rnd());
      parts.add(Particle(x, y, math.cos(a) * v, math.sin(a) * v, life * (.6 + rnd() * .6), life, 2 + rnd() * 3.5,
          cols[i % cols.length], k, k == 3 ? 600 : 0));
    }
  }

  void _finishTurn() {
    turn = 1 - turn;
    phase = Phase.aim;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    events.add(EngineEvent.turn(turn));
  }

  void _end() {
    phase = Phase.over;
    events.add(EngineEvent.end(<int>[score[0], score[1]]));
  }

  // ---------- main step (call once per frame) ----------
  void update(double rdt) {
    final double dt = _min(rdt, .05);
    time += dt;
    if (phase == Phase.over) {
      tickFx(dt);
      return;
    }
    if (cfg.matchTime > 0 && !sudden && mleft > 0) mleft = _max(0, mleft - dt);
    double ts = 1;
    if (slow > 0) {
      slow -= dt;
      ts = .3 + .7 * math.pow(1 - _max(0, slow) / 1.1, 2).toDouble();
    }
    acc += dt * ts;
    int n = 0;
    while (acc >= STEP) {
      final bool go = n < 16;
      n++;
      if (!go) break;
      for (final Body b in bodies) {
        b.px = b.x;
        b.py = b.y;
      }
      _sim(STEP);
      acc -= STEP;
    }
    if (n > 16) acc = 0;
    if (phase == Phase.move) {
      bool anyMoving = false;
      for (final Body b in bodies) {
        if (b.vx != 0 || b.vy != 0 || b.ramp > 0) {
          anyMoving = true;
          break;
        }
      }
      idle = anyMoving ? 0.0 : idle + dt;
      if (idle > .15) _finishTurn();
    } else if (phase == Phase.aim) {
      if (cfg.matchTime > 0 && !sudden && mleft <= 0) {
        if (score[0] != score[1]) {
          _end();
          return;
        }
        sudden = true;
        events.add(const EngineEvent.clock());
      }
      if (cfg.turnTime > 0) {
        tleft -= dt;
        if (tleft <= 0) {
          drag = null;
          aiPlan = null;
          _finishTurn();
        }
      }
      if (isAiTurn()) _aiTick(dt);
    } else if (phase == Phase.goal) {
      pause -= dt;
      if (pause <= 0) {
        if (cfg.matchTime > 0) {
          if (sudden || (mleft <= 0 && score[0] != score[1])) {
            _end();
          } else {
            if (mleft <= 0) sudden = true;
            reset(kick);
          }
        } else if (score[0] >= cfg.limit || score[1] >= cfg.limit) {
          _end();
        } else {
          reset(kick);
        }
      }
    }
    tickFx(dt);
  }

  /// online clients: visual-only goal feedback (the host owns the score)
  void fxGoal(int t) {
    ripple[t] = 1;
    rippleX[t] = ball.x;
    flash = 1;
    shake[t] = .6;
    cam = 1.4;
    final Goal g = goals[t];
    burst(ball.x, g.y, 80, 760, _kGoalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _kGoalCols, 1.8, 3);
  }

  void tickFx(double dt) {
    flash = _max(0, flash - dt * 2);
    cam = _max(0, cam - dt * 3.2);
    shake[0] = _max(0, shake[0] - dt);
    ripple[0] = _max(0, ripple[0] - dt * .8);
    ripple[1] = _max(0, ripple[1] - dt * .8);
    shake[1] = _max(0, shake[1] - dt);
    final Body bl = ball;
    final double sp = hyp(bl.vx, bl.vy);
    if (sp > 60) trail.add(TrailPt(bl.x, bl.y, _min(1, sp / 900)));
    for (final TrailPt p in trail) {
      p.a -= dt * 3.2;
    }
    trail.removeWhere((TrailPt p) => !(p.a > 0));
    if (trail.length > 40) trail.removeRange(0, trail.length - 40);
    for (final Body b in bodies) {
      if (b == bl) continue;
      final double s = hyp(b.vx, b.vy);
      if (s > 140 * K) {
        b.tr.add(Pt(b.x, b.y));
      } else if (b.tr.isNotEmpty) {
        b.tr.removeAt(0);
      }
      if (b.tr.length > 12) b.tr.removeAt(0);
    }
    for (final Particle p in parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= .965;
      p.vy = p.vy * .965 + p.g * dt;
      p.l -= dt;
    }
    parts.removeWhere((Particle p) => !(p.l > 0));
  }

  /// interpolation factor for rendering between physics steps
  double alpha() => _clamp(acc / STEP, 0, 1);

  // ---------- AI ----------
  void _aiTick(double dt) {
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + rnd() * .5) return;
      final AiPlan? p = _aiDecide();
      if (p == null) return;
      aiPlan = p;
      drag = Drag(b: p.b, sx: p.b.x, sy: p.b.y, cx: p.b.x, cy: p.b.y, ai: true);
      return;
    }
    final AiPlan pl = aiPlan!;
    pl.t += dt;
    final double k = _min(1, pl.t / .75), e = k * k * (3 - 2 * k);
    final Drag? d = drag;
    if (d != null) {
      d.cx = pl.b.x - pl.dx * pl.l * e;
      d.cy = pl.b.y - pl.dy * pl.l * e;
    }
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l);
    }
  }

  AiPlan? _aiDecide() {
    final int me = turn;
    final Body bl = ball;
    final List<Body> B = bodies;
    final List<Body> mine = B.where((Body b) => b.team == me && b != bl).toList();
    final Goal og = goals[1 - me];
    // team 1 attacks the bottom goal (goals[1]); team 0 attacks the top goal (goals[0])
    final Goal target = goals[me == 1 ? 1 : 0];
    final int lvl = cfg.aiLvl;
    final double sg = const <double>[.14, .06, .016][lvl], gw = (target.x2 - target.x1) / 2;
    double segDist(double px, double py, double ax, double ay, double bx, double by) {
      final double vx = bx - ax, vy = by - ay;
      double l2 = vx * vx + vy * vy;
      if (l2 == 0) l2 = 1;
      double t = ((px - ax) * vx + (py - ay) * vy) / l2;
      t = _clamp(t, 0, 1);
      return hyp(px - (ax + vx * t), py - (ay + vy * t));
    }

    bool clear(Body p, double x, double y) {
      for (final Body o in B) {
        if (o == p || o == bl) continue;
        if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
      }
      return true;
    }

    final List<_Cand> cands = <_Cand>[];
    for (final Body p in mine) {
      for (final double ox in const <double>[-.55, 0, .55]) {
        final double tx = CX + ox * gw, ty = target.y;
        double ux = tx - bl.x, uy = ty - bl.y;
        double ul = hyp(ux, uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final double cx = bl.x - ux * (p.r + bl.r + 1), cy = bl.y - uy * (p.r + bl.r + 1);
        double vx = cx - p.x, vy = cy - p.y;
        final double dist = hyp(vx, vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final double al = vx * ux + vy * uy;
        if (al < .2 || !clear(p, cx, cy)) continue;
        int blk = 0;
        for (final Body o in B) {
          if (o.team == me || o == bl) continue;
          if (segDist(o.x, o.y, bl.x, bl.y, tx, ty) < bl.r + o.r + 6) blk++;
        }
        cands.add(_Cand(p, vx, vy, 100 * al - dist * .03 - blk * 28 + ((bl.y - ty).abs() < 420 ? 25 : 0), dist, 1));
      }
      double vx = bl.x - p.x, vy = bl.y - p.y;
      final double dist = hyp(vx, vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (clear(p, bl.x, bl.y)) {
          final double toOwn = (vy * (og.y - bl.y) > 0) ? vy.abs() : 0;
          cands.add(_Cand(p, vx, vy, 10 - dist * .04 - toOwn * 55, dist, 0));
        }
      }
    }
    if (cands.isEmpty) {
      final List<Body> s = List<Body>.of(mine);
      _stableSort<Body>(s, (Body a, Body b) {
        final double d = hyp(a.x - bl.x, a.y - bl.y) - hyp(b.x - bl.x, b.y - bl.y);
        return d < 0 ? -1 : (d > 0 ? 1 : 0);
      });
      if (s.isEmpty) return null;
      final Body p = s[0];
      final double vx = bl.x - p.x, vy = bl.y - p.y;
      double d = hyp(vx, vy);
      if (d == 0) d = 1;
      cands.add(_Cand(p, vx / d, vy / d, 0, d, 0));
    }
    _stableSort<_Cand>(cands, (_Cand a, _Cand b) {
      final double d = b.sc - a.sc;
      return d < 0 ? -1 : (d > 0 ? 1 : 0);
    });
    final int poolN = const <int>[4, 2, 1][lvl];
    final List<_Cand> pool = cands.sublist(0, poolN < cands.length ? poolN : cands.length);
    final _Cand c = pool[(rnd() * pool.length).floor()];
    double gauss() => (rnd() + rnd() + rnd() - 1.5) * 1.15;
    final double ang = math.atan2(c.dy, c.dx) + gauss() * sg;
    double pw = lvl == 2 ? _min(1, .66 + c.dist / 1000) : _min(1, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + rnd() * .3;
    if (c.atk == 1 && lvl > 0) pw = _max(pw, .78);
    return AiPlan(c.p, math.cos(ang), math.sin(ang), _max(.3, pw) * LMAX);
  }
}
