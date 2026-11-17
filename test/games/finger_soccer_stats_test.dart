import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/core/bm_goal_art.dart';
import 'package:nexora/games/finger_soccer/core/bm_stats.dart';

class _Hooks implements BmHooks {
  final List<Map<String, dynamic>> shots = <Map<String, dynamic>>[];
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> pattern) {}
  @override
  void toast(String text, bool big) {}
  @override
  void goalFx() {}
  @override
  void emit(String event, Map<String, dynamic> data) {
    if (event == 'shot') shots.add(data);
  }
}

BmEngine _engine({int seed = 42, String mode = 'local', List<String> teams = const <String>['club0', 'club1']}) =>
    BmEngine(_Hooks(), rng: math.Random(1))
      ..startMatch(BmConfig(
          mode: mode,
          teams: teams,
          form: const <int>[0, 0],
          names: const <String>['A', 'B'],
          field: 6,
          ball: 0,
          ai: mode == 'bot',
          seed: seed));

/// Fires piece [b] straight up the pitch at full pull and returns (speed, angle deg from straight).
(double, double) _shoot(BmEngine e, BmBody b) {
  e.fire(b, 0, -LMAX, LMAX);
  final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
  final double ang = math.atan2(b.vx, -b.vy) * 180 / math.pi;
  return (sp, ang);
}

void main() {
  group('disc stats', () {
    test('every disc has stable Power/Accuracy 1..10 spanning the whole range', () {
      expect(kBmDiscStats.length, kBmTeams.length);
      for (final BmTeam t in kBmTeams) {
        final BmDiscStats s = bmDiscStats(t.id);
        expect(s.power, inInclusiveRange(1, 10));
        expect(s.accuracy, inInclusiveRange(1, 10));
      }
      final Set<int> p = kBmDiscStats.values.map((BmDiscStats s) => s.power).toSet();
      final Set<int> a = kBmDiscStats.values.map((BmDiscStats s) => s.accuracy).toSet();
      expect(p, <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
      expect(a, <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
      // hash-derived, not re-rolled: the same id always maps to the same value
      expect(bmHash32('club0', 1), bmHash32('club0', 1));
      expect(bmHash32('club0', 1), isNot(bmHash32('club1', 1)));
      // stats differ between discs (not all pairs equal)
      expect(kBmDiscStats.values.map((BmDiscStats s) => '${s.power}/${s.accuracy}').toSet().length, greaterThan(20));
    });

    test('pieces take the stats of their own disc, every match', () {
      final BmEngine e1 = _engine(teams: const <String>['nat3', 'car5']);
      final BmEngine e2 = _engine(teams: const <String>['nat3', 'car5'], seed: 9);
      for (final BmEngine e in <BmEngine>[e1, e2]) {
        for (final BmBody b in e.bodies) {
          if (identical(b, e.ball)) continue;
          final BmDiscStats s = bmDiscStats(e.sel[e.ct(b.team)]);
          expect(b.power, s.power);
          expect(b.accuracy, s.accuracy);
        }
      }
    });

    test('power-10 disc shoots measurably faster than power-1', () {
      final BmEngine e = _engine();
      final BmBody b = e.bodies.first;
      b.accuracy = 10;
      b.power = 1;
      final double slow = _shoot(e, b).$1;
      b.power = 10;
      final double fast = _shoot(e, b).$1;
      expect(fast / slow, closeTo(1.18 / .82, 1e-9));
      expect(bmPowerFactor(1), closeTo(.82, 1e-12));
      expect(bmPowerFactor(10), closeTo(1.18, 1e-12));
      expect(bmPowerFactor(5), closeTo(.82 + 4 * .04, 1e-12));
    });

    test('accuracy-1 deviates (up to 7 deg, scaled by strength); accuracy-10 never does', () {
      final BmEngine e = _engine();
      final BmBody b = e.bodies.first;
      b.power = 5;
      double maxDev = 0;
      int deviated = 0;
      for (int i = 0; i < 40; i++) {
        b.accuracy = 1;
        final double a1 = _shoot(e, b).$2;
        expect(a1.abs(), lessThanOrEqualTo(7 + 1e-9));
        expect(e.lastAimDevDeg, closeTo(a1, 1e-6));
        if (a1.abs() > .5) deviated++;
        maxDev = math.max(maxDev, a1.abs());
        b.accuracy = 10;
        expect(_shoot(e, b).$2.abs(), lessThan(1e-9));
      }
      expect(deviated, greaterThan(25));
      expect(maxDev, greaterThan(5));
      // a soft shot deviates less than a full one with the same noise
      expect(bmAimDeviationDeg(1, .25, 1).abs(), closeTo(7 * .25, 1e-12));
      expect(bmAimDeviationDeg(10, 1, 1), 0);
    });

    test('deviation is deterministic for the same match seed and shot sequence', () {
      List<double> run(int seed) {
        final BmEngine e = _engine(seed: seed);
        final BmBody b = e.bodies.first..accuracy = 1;
        return <double>[for (int i = 0; i < 6; i++) _shoot(e, b).$2];
      }

      expect(run(5), run(5));
      expect(run(5), isNot(run(6)));
    });

    test('bot shots go through the same stats and carry them in the payload', () {
      final _Hooks h = _Hooks();
      final BmEngine e = BmEngine(h, rng: math.Random(7))
        ..startMatch(const BmConfig(
            mode: 'bot',
            teams: <String>['club0', 'club1'],
            form: <int>[0, 0],
            names: <String>['A', 'B'],
            field: 6,
            ball: 0,
            matchTime: 300,
            ai: true,
            aiLvl: 2,
            seed: 3));
      for (int f = 0; f < 60 * 60 && h.shots.where((Map<String, dynamic> s) => s['team'] == 1).isEmpty; f++) {
        if (e.phase == 'aim' && e.turn == 0 && e.drag == null) {
          final BmAiPlan? p = e.aiDecide();
          if (p != null) e.fire(p.b, p.dx * p.l, p.dy * p.l, p.l);
        }
        e.frame(1 / 60);
      }
      final Map<String, dynamic> bot = h.shots.firstWhere((Map<String, dynamic> s) => s['team'] == 1);
      final BmDiscStats s = bmDiscStats('club1');
      expect(bot['power'], s.power);
      expect(bot['acc'], s.accuracy);
    });
  });

  test('goal art: post feet land exactly on the collision posts, only two models', () {
    expect(kBmGoalArts.map((BmGoalArt a) => a.id).toList(), <String>['green', 'hex']);
    expect(kBmGoalDefault, 0);
    for (final BmGoalArt a in kBmGoalArts) {
      final r = bmGoalArtRect(a, 822, 357, 500, 169, 200);
      expect(r.left + a.postL * r.width, closeTo(500 - 169, 1e-9));
      expect(r.left + a.postR * r.width, closeTo(500 + 169, 1e-9));
      expect(r.top + a.foot * r.height, closeTo(200, 1e-9));
    }
  });
}
