import 'dart:math' as math;

import 'config.dart';
import 'fs_match.dart';

enum FsBotLevel { easy, normal, hard }

/// Search bot: generates candidate shots and evaluates each by running the real,
/// deterministic simulation on a cloned match. Works offline and costs only CPU.
/// The bot is NOT part of the determinism contract (only the chosen shot is).
class FsBot {
  FsBot({required this.team, this.level = FsBotLevel.normal, int seed = 7}) : _rng = math.Random(seed);

  final int team;
  final FsBotLevel level;
  final math.Random _rng;

  int get candidateCount => switch (level) {
        FsBotLevel.easy => 8,
        FsBotLevel.normal => 22,
        FsBotLevel.hard => 48,
      };

  double get _noise => switch (level) {
        FsBotLevel.easy => 0.20,
        FsBotLevel.normal => 0.07,
        FsBotLevel.hard => 0.02,
      };

  /// Deterministic (per rng state) list of candidate shots for the current position.
  List<FsShot> candidates(FsMatch m) {
    final ball = m.ball;
    final own = m.bodies.where((b) => b.team == team).toList();
    final out = <FsShot>[];
    if (own.isEmpty) return out;
    final goalY = team == 0 ? 0.0 : FsConfig.fieldH; // enemy goal line
    const goalX = FsConfig.fieldW / 2;
    for (var c = 0; c < candidateCount; c++) {
      final d = own[c % own.length];
      // aim at ball (first third), at a point behind the ball toward goal (rest), plus jitter
      var tx = ball.x;
      var ty = ball.y;
      if (c % 3 != 0) {
        final gx = goalX - ball.x, gy = goalY - ball.y;
        final gl = math.sqrt(gx * gx + gy * gy);
        if (gl > 1e-6) {
          tx = ball.x - gx / gl * (FsConfig.discR + FsConfig.ballR) * 0.8;
          ty = ball.y - gy / gl * (FsConfig.discR + FsConfig.ballR) * 0.8;
        }
      }
      final dx0 = tx - d.x, dy0 = ty - d.y;
      final ang = math.atan2(dy0, dx0) + (_rng.nextDouble() * 2 - 1) * (_noise + (c ~/ own.length) * 0.03);
      final power = 0.55 + _rng.nextDouble() * 0.45;
      out.add(FsShot(bodyId: d.id, dirX: math.cos(ang), dirY: math.sin(ang), power: power));
    }
    return out;
  }

  /// Simulates [shot] on a clone of [m] and returns its score (null when illegal).
  double? evaluate(FsMatch m, FsShot shot) {
    final sim = m.clone();
    if (sim.validate(shot) != null) return null;
    final out = sim.playShot(shot);
    return score(sim, out);
  }

  FsShot fallback(FsMatch m) {
    final own = m.bodies.where((b) => b.team == team).toList();
    return FsShot(bodyId: own.first.id, dirX: 0, dirY: team == 0 ? -1 : 1, power: 0.6);
  }

  /// Synchronous search (tests / server). The UI uses [FsBotSearch] to spread the work.
  FsShot choose(FsMatch m) {
    FsShot? best;
    var bestScore = -1e18;
    for (final shot in candidates(m)) {
      final s = evaluate(m, shot);
      if (s != null && s > bestScore) {
        bestScore = s;
        best = shot;
      }
    }
    return best ?? fallback(m);
  }

  double score(FsMatch after, FsTurnOutcome out) {
    if (out.scorer == team) return 1e6;
    if (out.scorer == 1 - team) return -1e6;
    final b = after.ball;
    final enemyGoalY = team == 0 ? 0.0 : FsConfig.fieldH;
    final ownGoalY = team == 0 ? FsConfig.fieldH : 0.0;
    final dxg = b.x - FsConfig.fieldW / 2;
    final dEnemy = math.sqrt(dxg * dxg + (b.y - enemyGoalY) * (b.y - enemyGoalY));
    final dOwn = math.sqrt(dxg * dxg + (b.y - ownGoalY) * (b.y - ownGoalY));
    return -dEnemy + 0.35 * dOwn;
  }
}

/// Incremental bot search: evaluates a few candidates per frame so the UI never hitches.
class FsBotSearch {
  FsBotSearch(this.bot, FsMatch match)
      : _base = match.clone(),
        _cands = bot.candidates(match);

  final FsBot bot;
  final FsMatch _base;
  final List<FsShot> _cands;
  int _i = 0;
  FsShot? _best;
  double _bestScore = -1e18;

  bool get done => _i >= _cands.length;

  /// Evaluates up to [budget] candidates. Returns true when the search is complete.
  bool step(int budget) {
    var n = 0;
    while (_i < _cands.length && n < budget) {
      final shot = _cands[_i];
      _i++;
      n++;
      final s = bot.evaluate(_base, shot);
      if (s != null && s > _bestScore) {
        _bestScore = s;
        _best = shot;
      }
    }
    return done;
  }

  FsShot get best => _best ?? bot.fallback(_base);
}
