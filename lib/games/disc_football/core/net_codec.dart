// Online wire format for Disc Football — compatible with the Godot build's src/online/online_match.gd
// (enc_ev/dec_ev, _send_snap, cfg_from_room) and the older Expo OnlineMatch.tsx (same keys).
// Broadcast event 'g' payloads (RoomLink.sendGame adds `from`):
//   {k:'s', s:Snap}                         host → all   snapshot
//   {k:'shot', b, dx, dy, n}                ctrl → host  shot input (dx,dy = drag vector, 0.1 precision; n = turn seq)
//   {k:'aim', b, dx, dy} / {k:'aim', b:-1}  ctrl → all   live aim preview (integers)
//   {k:'res', winner, rd, score, ok}        host → all   reported result
//   {k:'abort'}                             host → all   match cancelled
// Snap = {q, ts, hz, ph, tu, sc:[a,b], ml, tl, su:0|1, c:uid|null, n, p:[x*10,y*10,ang*100]*bodies, R:[9 × 1000], ev:[[...]]}
// Pure Dart (no Flutter imports).
import 'dart:math' as math;

import 'data.dart';
import 'engine.dart';

const double kTau = math.pi * 2;

/// GDScript round(): half away from zero (same as Dart's round()).
int _ri(double v) => v.round();
/// GDScript _num(v, d): numbers and numeric strings, else the default.
double _d(Object? v, [double def = 0]) => v is num ? v.toDouble() : (v is String ? (double.tryParse(v) ?? def) : def);
int _i(Object? v, [int def = 0]) => v is num ? v.toInt() : (v is String ? (int.tryParse(v) ?? def) : def);

/// Event → compact int array (encEv).
List<int> encEv(EngineEvent e) {
  switch (e.t) {
    case 'hit':
      return <int>[0, e.ball ? 1 : 0, _ri(e.power * 100)];
    case 'wall':
      return <int>[1, _ri(e.power * 100)];
    case 'post':
      return <int>[2, _ri(e.power * 100)];
    case 'goal':
      return <int>[3, e.team, e.nogoal ? 1 : 0];
    case 'turn':
      return <int>[4, e.team];
    case 'shot':
      return <int>[5, e.team];
    case 'end':
      return <int>[6, e.score![0], e.score![1]];
    default:
      return <int>[7];
  }
}

/// Compact int array → event (decEv).
EngineEvent decEv(List<dynamic> a) {
  final int k = a.isEmpty ? 7 : _i(a[0]);
  int at(int i) => i < a.length ? _i(a[i]) : 0;
  switch (k) {
    case 0:
      return EngineEvent.hit(ball: at(1) != 0, power: at(2) / 100);
    case 1:
      return EngineEvent.wall(at(1) / 100);
    case 2:
      return EngineEvent.post(at(1) / 100);
    case 3:
      return EngineEvent.goal(at(1), at(2) != 0);
    case 4:
      return EngineEvent.turn(at(1));
    case 5:
      return EngineEvent.shot(at(1));
    case 6:
      return EngineEvent.end(<int>[at(1), at(2)]);
    default:
      return const EngineEvent.clock();
  }
}

/// A host snapshot (type Snap in OnlineMatch.tsx).
class Snap {
  Snap({
    required this.q,
    required this.ts,
    required this.hz,
    required this.ph,
    required this.tu,
    required this.sc,
    required this.ml,
    required this.tl,
    required this.su,
    required this.c,
    required this.n,
    required this.p,
    required this.R,
    required this.ev,
  });
  final int q;
  final int ts;
  final int hz;
  final Phase ph;
  final int tu;
  final List<int> sc;
  final double ml;
  final double tl;
  final int su;
  final String? c;
  final int n;
  final List<int> p;
  final List<int> R;
  final List<List<dynamic>> ev;

  /// Capture the engine exactly like OnlineMatch.sendSnap.
  static Snap capture(Engine eng, {required int q, required int ts, required int hz, required String? ctrl, required int seq, required List<List<int>> evs}) {
    final List<int> p = <int>[];
    for (final Body b in eng.bodies) {
      p
        ..add(_ri(b.x * 10))
        ..add(_ri(b.y * 10))
        ..add(_ri((((b.ang % kTau) + kTau) % kTau) * 100));
    }
    final List<int> r = <int>[for (final double v in eng.ball.R) _ri(v * 1000)];
    return Snap(
      q: q,
      ts: ts,
      hz: hz,
      ph: eng.phase,
      tu: eng.turn,
      sc: <int>[eng.score[0], eng.score[1]],
      ml: (eng.mleft * 10).round() / 10,
      tl: (eng.tleft * 10).round() / 10,
      su: eng.sudden ? 1 : 0,
      c: ctrl,
      n: seq,
      p: p,
      R: r,
      ev: List<List<dynamic>>.of(evs),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'q': q,
        'ts': ts,
        'hz': hz,
        'ph': ph.name,
        'tu': tu,
        'sc': <int>[sc[0], sc[1]],
        'ml': ml,
        'tl': tl,
        'su': su,
        'c': c,
        'n': n,
        'p': p,
        'R': R,
        'ev': ev,
      };

  static Snap? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? pp = raw['p'];
    if (pp is! List) return null;
    final Object? scr = raw['sc'];
    final List<dynamic> sc = scr is List ? scr : const <dynamic>[0, 0];
    final Object? rr = raw['R'];
    final Object? ee = raw['ev'];
    return Snap(
      q: _i(raw['q'], -1),
      ts: _i(raw['ts']),
      hz: _i(raw['hz'], 12),
      ph: phaseFromName('${raw['ph']}'),
      tu: _i(raw['tu']) == 1 ? 1 : 0,
      sc: <int>[sc.isNotEmpty ? _i(sc[0]) : 0, sc.length > 1 ? _i(sc[1]) : 0],
      ml: _d(raw['ml']),
      tl: _d(raw['tl']),
      su: _i(raw['su']),
      c: raw['c'] == null ? null : '${raw['c']}',
      n: _i(raw['n']),
      p: pp.map((dynamic v) => _i(v)).toList(),
      R: rr is List ? rr.map((dynamic v) => _i(v)).toList() : <int>[],
      ev: ee is List ? ee.whereType<List<dynamic>>().toList() : <List<dynamic>>[],
    );
  }
}

/// MatchCfg for an online room (online_match.gd cfg_from_room). [settings] = rooms.settings JSON.
/// Stats / teams are filled by the online layer from the players' discs.
MatchCfg cfgFromRoomSettings(Map<String, dynamic>? settings, {List<DiscStats?>? stats, List<String>? teams}) {
  final Map<String, dynamic> s = settings ?? const <String, dynamic>{};
  final double time = math.max(0.0, _d(s['time'], 0));
  final int goals = math.max(1, _d(s['goals'], 3).truncate());
  final Object? turnV = s['turn'];
  final double turnT = (turnV != null && _d(turnV, -1) == 0) ? 0.0 : math.max(5.0, _d(turnV, 15));
  final int nf = kFields.length;
  return MatchCfg(
    field: math.max(0, math.min(nf - 1, _d(s['field'], 0).truncate())),
    ball: math.max(0, math.min(35, _d(s['ball'], 0).truncate())),
    forms: <int>[0, 0],
    ai: false,
    aiLvl: 1,
    limit: time > 0 ? 99 : goals,
    matchTime: time,
    turnTime: turnT,
    vip: <bool>[false, false],
    first: 0,
    stats: stats,
    teams: teams ?? const <String>['club0', 'club1'],
  );
}

/// Host-side validation + application of a remote shot (same checks as OnlineMatch.tsx).
/// Returns true when the shot was fired.
bool applyShotInput(Engine eng, {required int bodyId, required double dx, required double dy}) {
  if (eng.phase != Phase.aim) return false;
  Body? b;
  for (final Body x in eng.bodies) {
    if (x.id == bodyId && x.team == eng.turn) b = x;
  }
  if (b == null) return false;
  final double l = hyp(dx, dy);
  if (l > 18 && l < 5000) {
    eng.fire(b, dx, dy, l, human: true);
    return true;
  }
  return false;
}

/// Full engine state with velocities (for tests / resync). Not part of the Expo wire format.
Map<String, dynamic> engineState(Engine e) => <String, dynamic>{
      'b': <List<double>>[
        for (final Body b in e.bodies) <double>[b.x, b.y, b.vx, b.vy, b.ang, b.spin],
      ],
      'R': List<double>.of(e.ball.R),
      'sc': <int>[e.score[0], e.score[1]],
      'tu': e.turn,
      'ph': e.phase.name,
      'ml': e.mleft,
      'tl': e.tleft,
      'su': e.sudden,
      'sh': e.shots,
    };

void applyEngineState(Engine e, Map<String, dynamic> s) {
  final Object? bl = s['b'];
  if (bl is List && bl.length == e.bodies.length) {
    for (int i = 0; i < bl.length; i++) {
      final Object? r = bl[i];
      if (r is! List || r.length < 6) continue;
      final Body b = e.bodies[i];
      b.x = b.px = _d(r[0]);
      b.y = b.py = _d(r[1]);
      b.vx = _d(r[2]);
      b.vy = _d(r[3]);
      b.ang = _d(r[4]);
      b.spin = _d(r[5]);
    }
  }
  final Object? rr = s['R'];
  if (rr is List && rr.length == 9) {
    for (int j = 0; j < 9; j++) {
      e.ball.R[j] = _d(rr[j]);
    }
  }
  final Object? sc = s['sc'];
  if (sc is List && sc.length == 2) e.score = <int>[_i(sc[0]), _i(sc[1])];
  e.turn = _i(s['tu']) == 1 ? 1 : 0;
  e.phase = phaseFromName('${s['ph']}');
  e.mleft = _d(s['ml']);
  e.tleft = _d(s['tl']);
  e.sudden = s['su'] == true;
  e.shots = _i(s['sh']);
  e.acc = 0;
}
