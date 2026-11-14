/// Online 8-ball billiards: wire format + pure sync rules (no Flutter imports).
///
/// Host-authoritative like carrom (`gm_shot`): the shooter's device runs the deterministic
/// offline engine ([PoolMatch] / pool_physics) and submits the final table; the server checks
/// seat / turn order / version, runs the 45 s clock and ends the match on `p_finish`.
///
/// Wire state (`view.state`):
///   board  = [billiardsMatchToJson] after the shot (authoritative)
///   prev   = the table right before the shot (cue already placed for ball-in-hand)
///   shot   = [PoolShot.toJson] (dx, dy, p, s, e)
///   by     = shooter seat, hash = [poolStateHash] of `board`
///   seed   = kept from the server's init, scores = balls of own group potted per seat
///   shots  = server counter, foul = {seat, reason:'timeout'} after an idle timeout
library;

import 'package:nexora/games/billiards/core/pool_match.dart';
import 'package:nexora/games/billiards/core/pool_physics.dart';

import 'gm_models.dart';

double _d(Object? v, [double d = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? d;
  return d;
}

T _enumAt<T>(List<T> values, Object? i, T d) {
  final int k = gmInt(i, -1);
  return k >= 0 && k < values.length ? values[k] : d;
}

Map<String, dynamic> billiardsMatchToJson(PoolMatch m) => <String, dynamic>{
      'balls': <Map<String, dynamic>>[
        for (final PoolBall b in m.balls) <String, dynamic>{'id': b.id, 'x': b.x, 'y': b.y, 'k': b.pocketed, 'pk': b.pocket},
      ],
      'cur': m.current,
      'brk': m.breaker,
      'rail': m.requireRail,
      'g': <int>[for (final PoolGroup g in m.groups) g.index],
      'ph': m.phase == PoolPhase.over ? PoolPhase.over.index : PoolPhase.aiming.index,
      'isBreak': m.isBreak,
      'bih': m.ballInHand,
      'kit': m.kitchenOnly,
      'w': m.winner,
      'end': m.endReason.index,
      'n': m.shotCount,
    };

/// Null when missing or malformed.
PoolMatch? billiardsMatchFromJson(Object? raw) {
  if (raw is! Map) return null;
  try {
    final Map<String, dynamic> j = gmMap(raw);
    final List<Map<String, dynamic>> balls = gmMaps(j['balls']);
    if (balls.length != 16) return null;
    final PoolMatch m = PoolMatch.newRack(breaker: gmInt(j['brk']) == 1 ? 1 : 0, requireRail: j['rail'] != false);
    for (final Map<String, dynamic> b in balls) {
      final int id = gmInt(b['id'], -1);
      if (id < 0 || id > 15) return null;
      final PoolBall t = m.balls[id];
      t.x = _d(b['x'], t.x);
      t.y = _d(b['y'], t.y);
      t.vx = 0;
      t.vy = 0;
      t.pocketed = gmBool(b['k']);
      t.pocket = t.pocketed ? gmInt(b['pk'], -1) : -1;
    }
    m.current = gmInt(j['cur']) == 1 ? 1 : 0;
    final List<int> g = gmInts(j['g']);
    m.groups = <PoolGroup>[
      _enumAt<PoolGroup>(PoolGroup.values, g.isNotEmpty ? g[0] : 0, PoolGroup.none),
      _enumAt<PoolGroup>(PoolGroup.values, g.length > 1 ? g[1] : 0, PoolGroup.none),
    ];
    m.phase = gmInt(j['ph']) == PoolPhase.over.index ? PoolPhase.over : PoolPhase.aiming;
    m.isBreak = j['isBreak'] != false;
    m.ballInHand = gmBool(j['bih']);
    m.kitchenOnly = gmBool(j['kit']);
    m.winner = gmIntOrNull(j['w']);
    m.endReason = _enumAt<PoolEndReason>(PoolEndReason.values, j['end'], PoolEndReason.none);
    m.shotCount = gmInt(j['n']);
    m.world.resetEvents();
    return m;
  } catch (_) {
    return null;
  }
}

PoolShot? billiardsShotFromJson(Object? raw) {
  if (raw is! Map) return null;
  final Map<String, dynamic> j = gmMap(raw);
  if (j['dx'] == null || j['dy'] == null || j['p'] == null) return null;
  return PoolShot(
    dirX: _d(j['dx']),
    dirY: _d(j['dy']),
    power: _d(j['p']),
    spin: _d(j['s']),
    side: _d(j['e']),
  );
}

class BilliardsOnlineSync {
  BilliardsOnlineSync._();

  static int shotsOf(GmView v) => gmInt(v.state['shots']);
  static int? shooterOf(GmView v) => gmIntOrNull(v.state['by']);

  /// The table every client shows for [v]. No board yet = fresh rack, seat [GmView.turn] breaks.
  /// When the server passed the turn on an idle timeout, the incoming shooter gets ball in hand
  /// (a timeout counts as a foul), still behind the head string if it was the break.
  static PoolMatch derive(GmView v) {
    final int first = v.turn == 1 ? 1 : 0;
    final PoolMatch m = billiardsMatchFromJson(v.state['board']) ?? PoolMatch.newRack(breaker: first);
    if (v.live && !m.isOver && (v.turn == 0 || v.turn == 1) && m.current != v.turn) {
      m.current = v.turn;
      m.ballInHand = true;
      m.kitchenOnly = m.isBreak;
    }
    return m;
  }

  static List<int> scoresOf(PoolMatch m) => <int>[m.pottedCount(0), m.pottedCount(1)];

  static Map<String, dynamic> encode({
    required PoolMatch prev,
    required PoolShot shot,
    required PoolMatch after,
    required int shooter,
    Object? seed,
  }) =>
      <String, dynamic>{
        if (seed != null) 'seed': seed,
        'board': billiardsMatchToJson(after),
        'prev': billiardsMatchToJson(prev),
        'shot': <String, dynamic>{'dx': shot.dirX, 'dy': shot.dirY, 'p': shot.power, 's': shot.spin, 'e': shot.side},
        'by': shooter,
        'hash': after.stateHash,
        'scores': scoresOf(after),
      };

  static int nextTurn(PoolMatch after) => after.current;

  static Map<String, dynamic>? finishOf(PoolMatch m) {
    if (!m.isOver) return null;
    final int? w = m.winner;
    if (w == null || w < 0 || w > 1) return null;
    String reason;
    switch (m.endReason) {
      case PoolEndReason.eightPotted:
        reason = 'eight_potted';
        break;
      case PoolEndReason.eightEarly:
        reason = 'eight_early';
        break;
      case PoolEndReason.eightWithFoul:
        reason = 'eight_foul';
        break;
      case PoolEndReason.none:
        reason = 'win';
        break;
    }
    return <String, dynamic>{'winners': <int>[w], 'reason': reason};
  }

  static bool shouldReplay(GmView v, int appliedShots) {
    if (appliedShots < 0) return false;
    if (shotsOf(v) != appliedShots + 1) return false;
    final int? by = shooterOf(v);
    if (by == null || (v.mySeat != null && by == v.mySeat)) return false;
    return billiardsMatchFromJson(v.state['prev']) != null && billiardsShotFromJson(v.state['shot']) != null;
  }

  /// Headless replay of the newest shot (tests / fallback): prev + shot → resulting table.
  static PoolMatch? replay(GmView v) {
    final PoolMatch? prev = billiardsMatchFromJson(v.state['prev']);
    final PoolShot? shot = billiardsShotFromJson(v.state['shot']);
    if (prev == null || shot == null) return null;
    if (prev.playShot(shot) == null) return null;
    return prev;
  }
}
