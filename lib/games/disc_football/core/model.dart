// Disc Football engine model types (port of body.gd + the dictionaries used by engine.gd).
// Pure Dart (no Flutter imports). Re-exported by engine.dart.
/// Seedable deterministic RNG (mulberry32). randf() in [0, 1).
class NxRng {
  NxRng([int? seed]) : _s = (seed ?? DateTime.now().microsecondsSinceEpoch) & 0xFFFFFFFF;
  int _s;

  int nextU32() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _s;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) => ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF;

  double randf() => nextU32() / 4294967296.0;
}

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

  /// Team that scores in this goal.
  final int team;
  final double y;
  final double x1;
  final double x2;

  /// -1 = top goal (team 0 scores here), +1 = bottom goal.
  final int d;
}

/// One physics body (disc team 0/1, ball team 2) — same fields as NxBody in body.gd.
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

  /// 3x3 rotation matrix of the rolling ball, row-major (r0..r8 in body.gd).
  final List<double> R = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  double sq = 0;
  double tvx = 0;
  double tvy = 0;
  double ramp = 0;
  double boost = 0;
  double vox = 0;
  double voy = 0;
  Goal? gout;

  /// Disc motion trail.
  final List<Pt> tr = <Pt>[];

  void resetRot() {
    for (int i = 0; i < 9; i++) {
      R[i] = (i == 0 || i == 4 || i == 8) ? 1 : 0;
    }
  }
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

/// Engine event (union of the event dictionaries, discriminated by [t]).
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

/// Match configuration (the Godot cfg dictionary).
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
    this.teams = const <String>['club0', 'club1'],
    this.seed,
  });
  final int field;
  final int ball;
  final List<int> forms;
  final bool ai;

  /// 0 easy, 1 normal, 2 hard.
  final int aiLvl;
  final int limit;
  final double matchTime;
  final double turnTime;
  final List<bool> vip;
  final int first;

  /// Disc stats per team (power scales the launch speed; accuracy the aim preview).
  final List<DiscStats?>? stats;

  /// Disc (team) ids per side, for skins.
  final List<String> teams;
  final int? seed;
}

class Drag {
  Drag({required this.b, required this.sx, required this.sy, required this.cx, required this.cy, required this.ai});
  final Body b;
  final double sx;
  final double sy;
  double cx;
  double cy;
  final bool ai;
}

class AimInfo {
  const AimInfo(this.b, this.p, this.ux, this.uy);
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

class GoalGeom {
  const GoalGeom(this.w, this.h, this.x);
  final double w;
  final double h;
  final double x;
}

