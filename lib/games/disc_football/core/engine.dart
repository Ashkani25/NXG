// NEXORA Disc Football physics engine — 1:1 Dart port of the Godot build's src/game/engine.gd
// (NxEngine, default model "nx8", updated 2026-11-14) + src/game/body.gd.
//
// nx8 = POOL (billiards) physics: shots go exactly along the aim with speed linear in drag length
// (SHOT_MAX), straight-line motion, constant cloth friction, discs 3x the ball's mass (PM 6 / BM 2),
// disc-disc E_BODY .95 / disc-ball E_DISC_BALL .70 with soft light contacts, resolved at the time of
// impact, cushions E_CUSHION .85 (angle in = out), adaptive substeps, fixed 240 Hz step,
// render interpolation prev -> current via [Engine.alpha].
// The old "v4" reference model of engine.gd (TS port, never selected by the Godot app) is not ported.
//
// Pure Dart (no Flutter imports), deterministic for a given [MatchCfg.seed] (all randomness goes
// through [NxRng]). Also used by the online host (it simulates and broadcasts snapshots).
import 'dart:math' as math;

import 'data.dart';
import 'ai.dart';
import 'model.dart';

export 'model.dart';

const double K = 1.27;
const double PR = 49.0; // piece radius
const double BR = 27.0; // ball radius
const double POST_R8 = 5.0;
const double RC = 70.0;
const double LMAX = 210.0; // drag length for full power
const double STEP = 1 / 240;
const double POST_R = POST_R8;
const double PM = 6.0; // disc mass
const double BM = 2.0; // ball mass
const double SHOT_MAX = 1900.0;
const double DISC_VMAX = 2000.0;
const double V_SAFE = 3300.0;
const double FRICTION = 360.0;
const double V_STOP = 6.0;
const double V_SETTLE = 80.0;
const double SETTLE_K = 2.0;
const double E_SOFT = 0.55;
const double V_SOFT = 240.0;
const double E_BODY = 0.95;
const double E_DISC_BALL = 0.70;
const double E_CUSHION = 0.85;
const double SUB_PX = 4.0;
const int SUB_MAX = 16;
const double ROLL_K = 0.6;
const double CORNER_NUDGE = 70.0;

const List<int> kGoalCols = <int>[0xFFFFD23A, 0xFFFFFFFF, 0xFF3BD0FF, 0xFFFF4A7A, 0xFF7BFF5A];
const List<int> kHitCols = <int>[0xFFFFFFFF, 0xFF9FE8FF, 0xFF5CB6FF];

/// Euclidean length (Godot sqrt(x*x+y*y)).
double hyp(double a, double b) => math.sqrt(a * a + b * b);

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

class Engine {
  Engine(this.cfg) : rng = NxRng(cfg.seed) {
    final int fi = cfg.field;
    f = (fi >= 0 && fi < kFields.length) ? kFields[fi] : kFields[0];
    fl = f.l + 4;
    fr = f.r - 4;
    ft = f.t + 4;
    fb = f.b - 4;
    cx = (fl + fr) / 2;
    cy = (ft + fb) / 2;
    ky = f.cs;
    final List<double> gi = kGS[f.gs] ?? kGS['white']!;
    final double gw = 2.0 * f.g / (gi[3] - gi[2]);
    gg = GoalGeom(gw, gw * gi[1] / gi[0] * 1.28, cx - f.g - gi[2] * gw);
    depth = _max(120.0, jsRound(gg.h * 0.98));
    goals = <Goal>[
      Goal(team: 0, y: ft, x1: cx - f.g, x2: cx + f.g, d: -1),
      Goal(team: 1, y: fb, x1: cx - f.g, x2: cx + f.g, d: 1),
    ];
    forms = List<int>.of(cfg.forms);
    mleft = cfg.matchTime;
    tleft = cfg.turnTime;
    reset(cfg.first);
  }

  final MatchCfg cfg;
  final NxRng rng;
  late final Field f;
  late final double fl, fr, ft, fb, cx, cy, ky;
  late final List<Goal> goals;
  late final GoalGeom gg;
  late final double depth;

  /// Formations per side (mutable: a loadout change applies at the next kickoff).
  late List<int> forms;

  List<Body> bodies = <Body>[];
  late Body ball;
  List<Particle> parts = <Particle>[];
  List<TrailPt> trail = <TrailPt>[];
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

  /// Sides played by the AI in addition to cfg.ai (team 1). Online clients / bot tests set it.
  List<bool> aiTeams = <bool>[false, false];

  static double powerMul(double p) => 0.75 + (_min(10, _max(1, p)) - 1) / 9.0 * 0.5;
  static double aimDevDeg(double a) => (10 - _min(10, _max(1, a))) / 9.0 * 4.0;
  static double aimPreview(double a) => 0.45 + (_min(10, _max(1, a)) - 1) / 9.0 * 0.75;

  void reset(int kickTeam) {
    final double w = fr - fl;
    final double h = fb - ft;
    bodies = <Body>[];
    trail = <TrailPt>[];
    parts = <Particle>[];
    slow = 0;
    cam = 0;
    for (int cm = 0; cm < 2; cm++) {
      final List<List<double>> sl = slots(forms[cm]);
      for (int i = 0; i < sl.length; i++) {
        final double nx = sl[i][0];
        final double ny = sl[i][1];
        const double ins = PR + 6.0;
        final double x = fl + ins + nx * (w - 2 * ins);
        final double y = cm == 1 ? (ft + ny * h) : (fb - ny * h);
        bodies.add(Body(cm * 20 + i, cm, x, y, PR, PM));
      }
    }
    ball = Body(99, 2, cx, ky, BR, BM);
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

  /// Match restart (pause menu): score 0:0, clock reset, kickoff by team 0.
  void restartMatch() {
    score = <int>[0, 0];
    mleft = cfg.matchTime;
    sudden = false;
    events.clear();
    reset(0);
  }

  bool isAiTurn() => (cfg.ai && turn == 1) || aiTeams[turn];
  bool canControl() => phase == Phase.aim && !isAiTurn();

  // ---------- input ----------
  bool pick(double x, double y) {
    if (!canControl()) return false;
    Body? fb0;
    double bd = 1e9;
    for (final Body b in bodies) {
      if (b.team == turn && b != ball) {
        final double d = hyp(x - b.x, y - b.y);
        if (d < b.r + 30 && d < bd) {
          fb0 = b;
          bd = d;
        }
      }
    }
    if (fb0 == null) return false;
    drag = Drag(b: fb0, sx: fb0.x, sy: fb0.y, cx: x, cy: y, ai: false);
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
    final double dx = d.sx - d.cx;
    final double dy = d.sy - d.cy;
    final double l = hyp(dx, dy);
    if (l > 18 && phase == Phase.aim) fire(d.b, dx, dy, l, human: true);
  }

  void cancel() {
    if (drag != null && !drag!.ai) drag = null;
  }

  AimInfo? aimInfo() {
    final Drag? d = drag;
    if (d == null) return null;
    final double dx = d.sx - d.cx;
    final double dy = d.sy - d.cy;
    final double l = hyp(dx, dy);
    if (l < 18) return AimInfo(d.b, 0, 0, 0);
    return AimInfo(d.b, _min(l, LMAX) / LMAX, dx / l, dy / l);
  }

  DiscStats statsOf(int team) {
    final List<DiscStats?>? s = cfg.stats;
    if (s != null && s.length > team && s[team] != null) return s[team]!;
    return const DiscStats(power: 5, accuracy: 5);
  }

  void fire(Body b, double dx, double dy, double l, {bool human = false}) {
    final double p = _min(l, LMAX) / LMAX;
    final int team = b.team;
    lastPower = p;
    double v = SHOT_MAX * p;
    if (cfg.stats != null) {
      v *= powerMul(statsOf(team).power);
    } else if (team < 2 && cfg.vip.length > team && cfg.vip[team]) {
      v *= 1.16;
    }
    v = _min(v, DISC_VMAX);
    final double ux = dx / l;
    final double uy = dy / l;
    b.vx = ux * v;
    b.vy = uy * v;
    b.ramp = 0;
    b.boost = 0;
    b.tvx = 0;
    b.tvy = 0;
    b.spin = 0;
    if (b.team != turn) turn = b.team;
    phase = Phase.move;
    idle = 0;
    shots += 1;
    drag = null;
    lastWho = b.team;
    events.add(EngineEvent.shot(b.team));
  }

  // ---------- walls ----------
  void _cornerNudge(Body b) {
    final double r = b.r;
    const double gap = 1.5;
    final bool atL = b.x - r <= fl + gap;
    final bool atR = b.x + r >= fr - gap;
    if (!(atL || atR)) return;
    final bool atT = b.y - r <= ft + gap && (b.x < goals[0].x1 || b.x > goals[0].x2);
    final bool atB = b.y + r >= fb - gap && (b.x < goals[1].x1 || b.x > goals[1].x2);
    if (!(atT || atB)) return;
    if (b.vx * b.vx + b.vy * b.vy > 90.0 * 90.0) return;
    final double nx = atL ? 1.0 : -1.0;
    final double ny = atT ? 1.0 : -1.0;
    b.vx = nx * CORNER_NUDGE;
    b.vy = ny * CORNER_NUDGE;
  }

  void _cap(Body b) {
    final double s2 = b.vx * b.vx + b.vy * b.vy;
    if (s2 > V_SAFE * V_SAFE) {
      final double k = V_SAFE / math.sqrt(s2);
      b.vx *= k;
      b.vy *= k;
    }
  }

  void _post8(Body b, double px, double py) {
    final double dx = b.x - px;
    final double dy = b.y - py;
    final double d = math.sqrt(dx * dx + dy * dy);
    final double m = b.r + POST_R8;
    if (d >= m || d == 0) return;
    final double nx = dx / d;
    final double ny = dy / d;
    final double vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      b.vx = E_CUSHION * (b.vx - 2.0 * vn * nx);
      b.vy = E_CUSHION * (b.vy - 2.0 * vn * ny);
      if (b == ball) events.add(EngineEvent.post(-vn / 1800));
    }
  }

  void _cushionX(Body b, double wall, double side) {
    final double over = (wall - b.x) * side;
    if (over <= 0.0) return;
    if (b.vx * side < 0.0) {
      final double vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (b == ball && vs > 200) events.add(EngineEvent.wall(vs / 1800));
      b.vx = -b.vx * E_CUSHION;
      b.vy *= E_CUSHION;
      b.x = wall + side * over * E_CUSHION;
    } else {
      b.x = wall;
    }
  }

  void _cushionY(Body b, double wall, double side) {
    final double over = (wall - b.y) * side;
    if (over <= 0.0) return;
    if (b.vy * side < 0.0) {
      final double vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (b == ball && vs > 200) events.add(EngineEvent.wall(vs / 1800));
      b.vy = -b.vy * E_CUSHION;
      b.vx *= E_CUSHION;
      b.y = wall + side * over * E_CUSHION;
    } else {
      b.y = wall;
    }
  }

  void _walls8(Body b) {
    if (b != ball && b.gout != null) {
      final Goal g0 = b.gout!;
      final double dq = g0.d * (b.y - g0.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g0.d * 270 * K;
        b.vx *= 0.6;
      } else {
        b.vy = 0;
        b.vx *= 0.2;
        b.gout = null;
      }
    }
    final bool bl = b == ball;
    final double r = b.r;
    _cushionX(b, fl + r, 1.0);
    _cushionX(b, fr - r, -1.0);
    final double vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    for (final Goal g in goals) {
      final double dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final double lo = g.x1 + (bl ? 0.0 : r);
      final double hi = g.x2 - (bl ? 0.0 : r);
      final bool inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final bool gl = phase == Phase.goal && bl;
        final double back = g.y + g.d * depth;
        if (!bl && dp > r * 0.3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > depth) {
          b.y = back - g.d * r;
          if (g.d * b.vy > 0) {
            b.vy = -b.vy * (gl ? 0.2 : E_CUSHION);
            b.vx *= (gl ? 0.6 : E_CUSHION);
          }
        }
        if (dp > (bl ? r * 0.6 : 0.0)) {
          final double ee = gl ? 0.3 : E_CUSHION;
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) {
              b.vx = -b.vx * ee;
              b.vy *= (gl ? 1.0 : ee);
            }
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) {
              b.vx = -b.vx * ee;
              b.vy *= (gl ? 1.0 : ee);
            }
          }
        }
      } else {
        _cushionY(b, g.y - g.d * r, -g.d.toDouble());
      }
    }
    _cornerNudge(b);
  }

  // ---------- contacts ----------
  void _hit8(Body a, Body b, double h) {
    double dx = b.x - a.x;
    double dy = b.y - a.y;
    double dd = dx * dx + dy * dy;
    final double m = a.r + b.r;
    if (dd >= m * m) return;
    final double rvx = b.vx - a.vx;
    final double rvy = b.vy - a.vy;
    final double dv = dx * rvx + dy * rvy;
    final double sm = a.im + b.im;
    final bool isB = a == ball || b == ball;
    double vn = 0.0;
    if (dv < 0.0) {
      final double vv = rvx * rvx + rvy * rvy;
      double s = 0.0;
      if (vv > 1e-9) {
        s = (dv + math.sqrt(_max(0.0, dv * dv - vv * (dd - m * m)))) / vv;
        s = _clamp(s, 0.0, h);
      }
      a.x -= a.vx * s;
      a.y -= a.vy * s;
      b.x -= b.vx * s;
      b.y -= b.vy * s;
      dx = b.x - a.x;
      dy = b.y - a.y;
      double d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-4) {
        dx = 0.0;
        dy = -1.0;
        d = 1.0;
      }
      final double nx = dx / d;
      final double ny = dy / d;
      vn = rvx * nx + rvy * ny;
      if (vn < 0.0) {
        final double eFull = isB ? E_DISC_BALL : E_BODY;
        final double ee = -vn >= V_SOFT ? eFull : _lerp(_min(E_SOFT, eFull), eFull, -vn / V_SOFT);
        final double j = -(1.0 + ee) * vn / sm;
        a.vx -= j * nx * a.im;
        a.vy -= j * ny * a.im;
        b.vx += j * nx * b.im;
        b.vy += j * ny * b.im;
        _cap(a);
        _cap(b);
      }
      a.x += a.vx * s;
      a.y += a.vy * s;
      b.x += b.vx * s;
      b.y += b.vy * s;
    }
    dx = b.x - a.x;
    dy = b.y - a.y;
    dd = dx * dx + dy * dy;
    if (dd < m * m) {
      final double d2 = math.sqrt(dd);
      double ux = 0.0;
      double uy = -1.0;
      if (d2 > 1e-4) {
        ux = dx / d2;
        uy = dy / d2;
      }
      final double pen = m - d2;
      a.x -= ux * pen * a.im / sm;
      a.y -= uy * pen * a.im / sm;
      b.x += ux * pen * b.im / sm;
      b.y += uy * pen * b.im / sm;
    }
    if (vn < -150) {
      events.add(EngineEvent.hit(ball: isB, power: -vn / 1900));
      if (!isB && vn < -520) {
        final double q = _min(1, -vn / 1900.0);
        a.sq = _max(a.sq, q * 0.5);
        b.sq = _max(b.sq, q * 0.5);
      }
      if (isB) {
        final double pw = _min(1, -vn / 2100.0);
        if (pw > 0.2) {
          final Body o = ball == b ? a : b;
          ball.sq = _max(ball.sq, pw * 0.6);
          o.sq = _max(o.sq, pw * 0.25);
          if (pw > 0.45) {
            burst((a.x + b.x) / 2, (a.y + b.y) / 2, jsRound(4 + pw * 8).toInt(), 200 + pw * 260, kHitCols, 0.3, 2);
          }
        }
      }
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _rotate(Body b, double wx, double wy, double wz, double dt) {
    final double w = math.sqrt(wx * wx + wy * wy + wz * wz);
    final double th = w * dt;
    if (th < 1e-7) return;
    final double ax = wx / w;
    final double ay = wy / w;
    final double az = wz / w;
    final double c = math.cos(th);
    final double s = math.sin(th);
    final double t = 1 - c;
    final double m0 = t * ax * ax + c;
    final double m1 = t * ax * ay - s * az;
    final double m2 = t * ax * az + s * ay;
    final double m3 = t * ax * ay + s * az;
    final double m4 = t * ay * ay + c;
    final double m5 = t * ay * az - s * ax;
    final double m6 = t * ax * az - s * ay;
    final double m7 = t * ay * az + s * ax;
    final double m8 = t * az * az + c;
    final List<double> R = b.R;
    final double r0 = R[0], r1 = R[1], r2 = R[2], r3 = R[3], r4 = R[4], r5 = R[5], r6 = R[6], r7 = R[7], r8 = R[8];
    final double n0 = m0 * r0 + m1 * r3 + m2 * r6;
    final double n1 = m0 * r1 + m1 * r4 + m2 * r7;
    final double n2 = m0 * r2 + m1 * r5 + m2 * r8;
    R[3] = m3 * r0 + m4 * r3 + m5 * r6;
    R[4] = m3 * r1 + m4 * r4 + m5 * r7;
    R[5] = m3 * r2 + m4 * r5 + m5 * r8;
    R[6] = m6 * r0 + m7 * r3 + m8 * r6;
    R[7] = m6 * r1 + m7 * r4 + m8 * r7;
    R[8] = m6 * r2 + m7 * r5 + m8 * r8;
    final double l0 = math.sqrt(n0 * n0 + n1 * n1 + n2 * n2);
    R[0] = n0 / l0;
    R[1] = n1 / l0;
    R[2] = n2 / l0;
  }

  // ---------- simulation ----------
  void _sim8(double dt) {
    double e2 = 0.0;
    double mmin = 1e9;
    for (final Body b in bodies) {
      final double mb = 1.0 / _max(b.im, 1e-6);
      e2 += mb * (b.vx * b.vx + b.vy * b.vy);
      mmin = _min(mmin, mb);
    }
    final int n = math.max(1, math.min(SUB_MAX, (math.sqrt(e2 / mmin) * dt / SUB_PX).ceil()));
    final double h = dt / n;
    for (int i = 0; i < n; i++) {
      _sub8(h);
      if (phase == Phase.move) {
        for (final Goal g in goals) {
          if (ball.x > g.x1 && ball.x < g.x2 && (g.d < 0 ? (ball.y < g.y - ball.r * 0.8) : (ball.y > g.y + ball.r * 0.8))) {
            _scored(g.team);
            break;
          }
        }
      }
    }
  }

  void _sub8(double h) {
    for (final Body b in bodies) {
      if (b.vox != 0 || b.voy != 0) {
        final double q = 1 - _min(1, h * 15);
        b.vox *= q;
        b.voy *= q;
        if (b.vox.abs() < 0.04) b.vox = 0;
        if (b.voy.abs() < 0.04) b.voy = 0;
      }
      b.x += b.vx * h;
      b.y += b.vy * h;
      final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sp > 0) {
        final double ns = sp - FRICTION * (sp < V_SETTLE ? SETTLE_K : 1.0) * h;
        if (ns < V_STOP) {
          b.vx = 0;
          b.vy = 0;
        } else {
          final double k2 = _min(ns, V_SAFE) / sp;
          b.vx *= k2;
          b.vy *= k2;
        }
      }
      b.spin = 0;
      if (b == ball) {
        b.sq *= 1 - 9 * h;
        if (b.vx != 0.0 || b.vy != 0.0) {
          final double roll = ROLL_K / b.r;
          _rotate(b, -b.vy * roll, b.vx * roll, 0.0, h);
        }
      }
      _walls8(b);
    }
    final int n = bodies.length;
    for (int it = 0; it < 2; it++) {
      for (int a = 0; a < n; a++) {
        final Body ba = bodies[a];
        for (int c = a + 1; c < n; c++) {
          final Body bc = bodies[c];
          final double mm = ba.r + bc.r;
          final double ddx = bc.x - ba.x;
          if (ddx >= mm || ddx <= -mm) continue;
          final double ddy = bc.y - ba.y;
          if (ddy >= mm || ddy <= -mm) continue;
          _hit8(ba, bc, it == 0 ? h : 0.0);
        }
      }
    }
    for (final Goal g in goals) {
      _post8(ball, g.x1, g.y);
      _post8(ball, g.x2, g.y);
    }
    for (final Body b in bodies) {
      _walls8(b);
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
    ripple[t] = 1.0;
    rippleX[t] = ball.x;
    score[t] += 1;
    pause = 1.8;
    flash = 1.0;
    shake[t] = 0.6;
    phase = Phase.goal;
    kick = 1 - t;
    slow = 1.1;
    cam = 1.4;
    final Goal g = goals[t];
    burst(ball.x, g.y, 80, 760, kGoalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, kGoalCols, 1.8, 3);
  }

  void burst(double x, double y, int n, double sp, List<int> cols, double life, [int k = 0]) {
    if (parts.length > 420) return;
    for (int i = 0; i < n; i++) {
      final double a = rng.randf() * math.pi * 2;
      final double v = sp * (0.3 + rng.randf());
      final double l = life * (0.6 + rng.randf() * 0.6);
      final double r = 2 + rng.randf() * 3.5;
      parts.add(Particle(x, y, math.cos(a) * v, math.sin(a) * v, l, life, r, cols[i % cols.length], k, k == 3 ? 600.0 : 0.0));
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

  bool timeUp() => cfg.matchTime > 0 && !sudden && mleft <= 0;

  // ---------- main step (call once per frame) ----------
  void update(double rdt) {
    final double dt = _min(rdt, 0.05);
    time += dt;
    if (phase == Phase.over) {
      tickFx(dt);
      return;
    }
    if (cfg.matchTime > 0 && !sudden && mleft > 0) mleft = _max(0, mleft - dt);
    double ts = 1.0;
    if (slow > 0) {
      slow -= dt;
      final double u = 1 - _max(0, slow) / 1.1;
      ts = 0.32 + 0.68 * u * u;
    }
    acc += dt * ts;
    int n = 0;
    const int cap = 14;
    while (acc >= STEP) {
      if (n >= cap) {
        n += 1;
        break;
      }
      n += 1;
      for (final Body b in bodies) {
        b.px = b.x;
        b.py = b.y;
      }
      _sim8(STEP);
      acc -= STEP;
    }
    if (n > cap) acc = 0;
    if (phase == Phase.move) {
      bool moving = false;
      for (final Body b in bodies) {
        if (b.vx != 0 || b.vy != 0) {
          moving = true;
          break;
        }
      }
      idle = moving ? 0.0 : idle + dt;
      if (idle > 0.25) _finishTurn();
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
          tickFx(dt);
          return;
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

  /// Online clients: visual-only goal feedback (the host owns the score).
  void fxGoal(int t) {
    ripple[t] = 1.0;
    rippleX[t] = ball.x;
    flash = 1.0;
    shake[t] = 0.6;
    cam = 1.4;
    final Goal g = goals[t];
    burst(ball.x, g.y, 80, 760, kGoalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, kGoalCols, 1.8, 3);
  }

  void tickFx(double dt) {
    flash = _max(0, flash - dt * 2);
    cam = _max(0, cam - dt * 3.2);
    shake[0] = _max(0, shake[0] - dt);
    ripple[0] = _max(0, ripple[0] - dt * 0.8);
    ripple[1] = _max(0, ripple[1] - dt * 0.8);
    shake[1] = _max(0, shake[1] - dt);
    final double sp = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
    if (sp > 60) trail.add(TrailPt(ball.x, ball.y, _min(1, sp / 900)));
    int k = 0;
    for (int i = 0; i < trail.length; i++) {
      final TrailPt p = trail[i];
      p.a -= dt * 3.0;
      if (p.a > 0) {
        trail[k] = p;
        k++;
      }
    }
    trail.length = k;
    const int tmax = 54;
    if (trail.length > tmax) trail.removeRange(0, trail.length - tmax);
    for (final Body b in bodies) {
      if (b != ball) {
        if (b.sq != 0) b.sq = b.sq > 0.02 ? b.sq - dt * 5 : 0.0;
        final double s = math.sqrt(b.vx * b.vx + b.vy * b.vy);
        if (s > 140 * K) {
          b.tr.add(Pt(b.x, b.y));
        } else if (b.tr.isNotEmpty) {
          b.tr.removeAt(0);
        }
        if (b.tr.length > 12) b.tr.removeAt(0);
      }
    }
    k = 0;
    for (int i = 0; i < parts.length; i++) {
      final Particle p = parts[i];
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.965;
      p.vy = p.vy * 0.965 + p.g * dt;
      p.l -= dt;
      if (p.l > 0) {
        parts[k] = p;
        k++;
      }
    }
    parts.length = k;
  }

  /// Interpolation factor for rendering between physics steps.
  double alpha() => _clamp(acc / STEP, 0, 1);

  // ---------- AI ----------
  void _aiTick(double dt) {
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < 0.7 + rng.randf() * 0.7) return;
      final AiPlan? p = aiDecide();
      if (p == null) return;
      p.t = 0;
      aiPlan = p;
      drag = Drag(b: p.b, sx: p.b.x, sy: p.b.y, cx: p.b.x, cy: p.b.y, ai: true);
      return;
    }
    final AiPlan pl = aiPlan!;
    pl.t += dt;
    final double k = _min(1, pl.t / 0.75);
    final double e = k * k * (3 - 2 * k);
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

  /// Decide the AI shot for the side on turn (dx, dy unit; l = drag length). Public for tests.
  AiPlan? aiDecide() => decideAiShot(this);
}
