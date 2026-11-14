import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/disc_football/core/data.dart';
import 'package:nexora/games/disc_football/core/engine.dart';
import 'package:nexora/games/disc_football/core/net_codec.dart';
import 'package:nexora/games/disc_football/disc_football_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchCfg _cfg({int field = 0, int lvl = 1, int seed = 7, double matchTime = 0, int first = 0, List<int> forms = const <int>[0, 3]}) =>
    MatchCfg(
      field: field,
      ball: 0,
      forms: forms,
      ai: true,
      aiLvl: lvl,
      limit: 3,
      matchTime: matchTime,
      turnTime: 15,
      vip: <bool>[false, false],
      first: first,
      stats: const <DiscStats?>[DiscStats(power: 5, accuracy: 5), DiscStats(power: 8, accuracy: 8)],
      teams: const <String>['club0', 'nat2'],
      seed: seed,
    );

String _state(Engine e) {
  final StringBuffer b = StringBuffer('${e.score[0]}:${e.score[1]} t${e.turn} ${e.phase.name} s${e.shots}|');
  for (final Body x in e.bodies) {
    b.write('${x.x.toStringAsFixed(6)},${x.y.toStringAsFixed(6)},${x.vx.toStringAsFixed(6)},${x.vy.toStringAsFixed(6)};');
  }
  return b.toString();
}

/// Runs a bot-vs-bot match; returns [ended, simSeconds, goals, outOfBounds].
List<num> _botMatch(Engine e, {double maxT = 1500}) {
  e.aiTeams = <bool>[true, true];
  double t = 0;
  bool ended = false;
  int goals = 0;
  int bad = 0;
  while (t < maxT && !ended) {
    e.update(0.05);
    t += 0.05;
    for (final EngineEvent ev in e.events) {
      if (ev.t == 'end') ended = true;
      if (ev.t == 'goal' && !ev.nogoal) goals++;
    }
    e.events.clear();
    for (final Body b in e.bodies) {
      if (b.x.isNaN || b.y.isNaN || b.x < e.fl - 200 || b.x > e.fr + 200 || b.y < e.ft - e.depth - 200 || b.y > e.fb + e.depth + 200) {
        bad++;
      }
    }
  }
  return <num>[ended ? 1 : 0, t, goals, bad];
}

void main() {
  group('data (Godot data.gd)', () {
    test('tables', () {
      expect(kFields.length, 30);
      expect(kForms.length, 9);
      expect(kForms.every((Formation f) => f.pts.length == 5), isTrue);
      expect(kTrails.length, 36);
      expect(teamById('club0').name, 'Persepolis');
      expect(teamById('elite3').id, 'club0'); // removed discs fall back
      expect(teamKey(teamById('nat7')), 'nat07');
      expect(discStatsFor('vip1').power, 8);
      expect(discStatsFor('club4').power, 5);
      expect(discStatsFor('lux2').power, 6);
    });
  });

  group('engine', () {
    test('kickoff layout: 5 discs per side inside the pitch, ball on the spot', () {
      for (int fi = 0; fi < kFields.length; fi++) {
        for (int fm = 0; fm < kForms.length; fm++) {
          final Engine e = Engine(_cfg(field: fi, forms: <int>[fm, fm]));
          expect(e.bodies.length, 11);
          expect(e.ball.x, closeTo(e.cx, 1e-9));
          expect(e.ball.y, e.f.cs);
          for (final Body b in e.bodies) {
            expect(b.x - b.r >= e.fl - 1e-6 && b.x + b.r <= e.fr + 1e-6, isTrue, reason: 'field $fi form $fm x');
            expect(b.y - b.r >= e.ft - 1e-6 && b.y + b.r <= e.fb + 1e-6, isTrue, reason: 'field $fi form $fm y');
          }
          expect(e.bodies.where((Body b) => b.team == 0).first.y > e.cy, isTrue); // team 0 defends the bottom
        }
      }
    });

    test('deterministic for a seed (bot vs bot, 120 s of play)', () {
      final Engine a = Engine(_cfg(seed: 42))..aiTeams = <bool>[true, true];
      final Engine b = Engine(_cfg(seed: 42))..aiTeams = <bool>[true, true];
      for (int i = 0; i < 2400; i++) {
        a.update(1 / 60 + (i % 3) * 0.004);
        b.update(1 / 60 + (i % 3) * 0.004);
        a.events.clear();
        b.events.clear();
      }
      expect(_state(a), _state(b));
      expect(a.shots + a.score[0] + a.score[1] > 0, isTrue);
      final Engine c = Engine(_cfg(seed: 43))..aiTeams = <bool>[true, true];
      for (int i = 0; i < 2400; i++) {
        c.update(1 / 60 + (i % 3) * 0.004);
      }
      expect(_state(c) == _state(a), isFalse);
    });

    test('shot speed is linear in drag length and capped (nx8)', () {
      final Engine e = Engine(_cfg());
      final Body d = e.bodies.firstWhere((Body b) => b.team == 0);
      e.fire(d, 0, -105, 105);
      final double v1 = hyp(d.vx, d.vy);
      expect(v1, closeTo(SHOT_MAX * 0.5 * Engine.powerMul(5), 1e-6));
      expect(d.vx, closeTo(0, 1e-9)); // exactly along the aim
      final Engine e2 = Engine(_cfg());
      final Body d2 = e2.bodies.firstWhere((Body b) => b.team == 1);
      e2.turn = 1;
      e2.fire(d2, 0, 900, 900);
      expect(hyp(d2.vx, d2.vy), closeTo(DISC_VMAX, 1e-6)); // power 8 -> above SHOT_MAX, capped
    });

    test('goal detection: ball rolled into the top goal scores for team 0', () {
      final Engine e = Engine(_cfg());
      e.events.clear();
      // second shot of the half (kick-off shots cannot score)
      final Body d = e.bodies.firstWhere((Body b) => b.team == 0);
      e.shots = 1;
      e.fire(d, 0.0001, 0.0001, 0.00015); // a negligible tap: phase move, shots = 2
      d.vx = 0;
      d.vy = 0;
      for (final Body b in e.bodies) {
        if (b != e.ball && b.x > e.goals[0].x1 - 120 && b.x < e.goals[0].x2 + 120 && b.y < e.ky) b.x = e.fl + b.r + 1;
      }
      e.ball.x = e.cx;
      e.ball.y = e.ft + 160;
      e.ball.vx = 0;
      e.ball.vy = -900;
      bool scored = false;
      for (int i = 0; i < 120 && !scored; i++) {
        e.update(1 / 60);
        for (final EngineEvent ev in e.events) {
          if (ev.t == 'goal') {
            expect(ev.team, 0);
            expect(ev.nogoal, isFalse);
            scored = true;
          }
        }
        e.events.clear();
      }
      expect(scored, isTrue);
      expect(e.score, <int>[1, 0]);
      expect(e.phase, Phase.goal);
      // after the celebration the side that conceded kicks off
      for (int i = 0; i < 300 && e.phase == Phase.goal; i++) {
        e.update(1 / 60);
      }
      expect(e.phase, Phase.aim);
      expect(e.turn, 1);
    });

    test('kick-off shot cannot score (no goal)', () {
      final Engine e = Engine(_cfg());
      final Body d = e.bodies.firstWhere((Body b) => b.team == 0);
      e.fire(d, 0.0001, 0.0001, 0.00015);
      d.vx = 0;
      d.vy = 0;
      for (final Body b in e.bodies) {
        if (b != e.ball && b.x > e.goals[0].x1 - 120 && b.x < e.goals[0].x2 + 120 && b.y < e.ky) b.x = e.fl + b.r + 1;
      }
      e.ball.y = e.ft + 160;
      e.ball.vy = -900;
      bool nogoal = false;
      for (int i = 0; i < 120; i++) {
        e.update(1 / 60);
        if (e.events.any((EngineEvent ev) => ev.t == 'goal' && ev.nogoal)) nogoal = true;
        e.events.clear();
      }
      expect(nogoal, isTrue);
      expect(e.score, <int>[0, 0]);
    });

    test('human input: pick / drag / release fires along the pull', () {
      final MatchCfg c = MatchCfg(
          field: 0, ball: 0, forms: <int>[0, 0], ai: false, aiLvl: 1, limit: 3, matchTime: 0, turnTime: 15, vip: <bool>[false, false], first: 0);
      final Engine e = Engine(c);
      final Body d = e.bodies.firstWhere((Body b) => b.team == 0);
      expect(e.pick(d.x + 5, d.y + 5), isTrue);
      e.move(d.x, d.y + 150); // pull down -> shoot up
      final AimInfo? a = e.aimInfo();
      expect(a, isNotNull);
      expect(a!.p, closeTo(150 / LMAX, 1e-9));
      e.release();
      expect(e.phase, Phase.move);
      expect(d.vy < 0 && d.vx.abs() < 1e-9, isTrue);
      expect(e.pick(d.x, d.y), isFalse); // not while moving
    });

    test('AI makes legal shots at every level', () {
      for (int lvl = 0; lvl < 3; lvl++) {
        for (int seed = 1; seed <= 12; seed++) {
          final Engine e = Engine(_cfg(lvl: lvl, seed: seed, first: seed % 2, field: seed % kFields.length));
          final AiPlan? p = e.aiDecide();
          expect(p, isNotNull);
          expect(p!.b.team, e.turn);
          expect(p.b, isNot(same(e.ball)));
          expect(hyp(p.dx, p.dy), closeTo(1, 1e-9));
          expect(p.l >= 0.3 * LMAX - 1e-9 && p.l <= LMAX + 1e-9, isTrue);
        }
      }
    });

    test('AI turn fires by itself in the aim phase', () {
      final Engine e = Engine(_cfg(first: 1));
      bool shot = false;
      for (int i = 0; i < 400 && !shot; i++) {
        e.update(1 / 60);
        shot = e.events.any((EngineEvent ev) => ev.t == 'shot' && ev.team == 1);
        e.events.clear();
      }
      expect(shot, isTrue);
    });

    test('bot-vs-bot matches finish (goals and timed), no tunnelling / NaN', () {
      for (int m = 0; m < 6; m++) {
        final Engine e = Engine(_cfg(field: (m * 5) % kFields.length, lvl: m % 3, seed: 100 + m, matchTime: m == 3 ? 180 : 0,
            forms: <int>[m % 9, (m * 7 + 3) % 9]));
        final List<num> r = _botMatch(e);
        expect(r[0], 1, reason: 'match $m did not end (${e.score})');
        expect(r[3], 0, reason: 'match $m bodies out of bounds');
        expect(e.phase, Phase.over);
        if (m != 3) expect(math.max(e.score[0], e.score[1]), 3);
      }
    });
  });

  group('net codec (online_match.gd wire)', () {
    test('events round trip', () {
      final List<EngineEvent> evs = <EngineEvent>[
        const EngineEvent.hit(ball: true, power: 0.43),
        const EngineEvent.wall(0.2),
        const EngineEvent.post(1.1),
        const EngineEvent.goal(1, true),
        const EngineEvent.turn(1),
        const EngineEvent.shot(0),
        const EngineEvent.end(<int>[3, 2]),
        const EngineEvent.clock(),
      ];
      for (final EngineEvent ev in evs) {
        final EngineEvent d = decEv(encEv(ev));
        expect(d.t, ev.t);
        expect(d.team, ev.team);
        expect(d.nogoal, ev.nogoal);
        expect(d.ball, ev.ball);
        expect(d.power, closeTo(ev.power, 0.006));
      }
      expect(encEv(const EngineEvent.hit(ball: true, power: 0.43)), <int>[0, 1, 43]);
    });

    test('snapshot round trip + room cfg', () {
      final Engine e = Engine(_cfg());
      final Snap s = Snap.capture(e, q: 5, ts: 1000, hz: 30, ctrl: 'u1', seq: 2, evs: <List<int>>[<int>[4, 0]]);
      final Snap? s2 = Snap.fromJson(s.toJson());
      expect(s2, isNotNull);
      expect(s2!.p, s.p);
      expect(s2.p.length, e.bodies.length * 3);
      expect(s2.R, <int>[1000, 0, 0, 0, 1000, 0, 0, 0, 1000]);
      expect(s2.ph, Phase.aim);
      expect(s2.c, 'u1');
      final MatchCfg c = cfgFromRoomSettings(<String, dynamic>{'time': 0, 'goals': 5, 'turn': 0, 'field': 99, 'ball': 3});
      expect(c.limit, 5);
      expect(c.turnTime, 0);
      expect(c.field, kFields.length - 1);
      final MatchCfg c2 = cfgFromRoomSettings(<String, dynamic>{'time': 120});
      expect(c2.limit, 99);
      expect(c2.turnTime, 15);
    });
  });

  group('widget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.init();
    });

    testWidgets('setup -> start -> vs bot plays a few seconds without errors', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final List<GameResult> results = <GameResult>[];
      final GameLaunch launch = GameLaunch(
        gameId: 'finger_soccer',
        mode: GameMode.vsBot,
        difficulty: BotDifficulty.hard,
        playerName: 'Tester',
        isFa: true,
        fancyEffects: true,
        reducedMotion: false,
        soundOn: false,
        seed: 3,
        onFinish: results.add,
      );
      final FlutterExceptionHandler? oldHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails d) {
        for (final String line in d.toString().split('\n').take(30)) {
          // ignore: avoid_print
          print('Error: $line');
        }
        oldHandler?.call(d);
      };
      addTearDown(() => FlutterError.onError = oldHandler);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: buildDiscFootballGame(launch))))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('شروع بازی'), findsOneWidget);
      await tester.tap(find.text('شروع بازی'));
      for (int i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(results.length <= 1, isTrue);
    });
  });
}
