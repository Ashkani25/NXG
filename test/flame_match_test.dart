// v0.7.0: the match runs inside a FlameGame (GameWidget). The component tree drives the deterministic engine from
// Flame's update and only reads/interpolates for display, so a Flame-driven match is bit-identical to the same
// frame times fed to a headless engine (online lockstep relies on this).
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/game/flame/match_components.dart';
import 'package:nexora/game/game.dart';

MatchCfg _cfg() => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: [const DiscStats(7, 10), const DiscStats(7, 10)]);

Engine _eng() => Engine(_cfg(), rand: math.Random(11).nextDouble);

void _shoot(Engine e) {
  final d = e.bodies.firstWhere((b) => !identical(b, e.ball) && b.team == e.turn);
  e.fire(d, 0, -LMAX * .8, LMAX * .8, true);
}

void main() {
  test('fixed physics step is 240 Hz', () => expect(STEP, 1 / 240));

  testWidgets('match is a FlameGame with the layered component tree', (tester) async {
    final e = _eng();
    final g = MatchGame(e: e, onTick: e.update);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: g)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(g, isA<FlameGame>());
    final kids = g.children.toList();
    expect(kids.whereType<FixedStepDriver>().length, 1);
    expect(kids.whereType<FrameClock>().length, 1);
    expect(kids.whereType<SoftCamera>().length, 1);
    expect(kids.whereType<BackgroundComponent>().length, 1);
    expect(kids.whereType<FlashComponent>().length, 1);
    final space = kids.whereType<PitchSpace>().single;
    final layers = space.children.toList();
    for (final t in [GoalNetsComponent, DropShadowsComponent, DiscsComponent, BallTrailComponent, BallComponent, GoalFramesComponent, AimComponent, ParticlesComponent]) {
      expect(layers.where((c) => c.runtimeType == t).length, 1, reason: '$t');
    }
    // paint order: shadows under discs under ball under goal frames under aim
    int pr(Type t) => layers.firstWhere((c) => c.runtimeType == t).priority;
    expect(pr(DropShadowsComponent) < pr(DiscsComponent), isTrue);
    expect(pr(DiscsComponent) < pr(BallComponent), isTrue);
    expect(pr(BallComponent) < pr(GoalFramesComponent), isTrue);
    expect(pr(GoalFramesComponent) < pr(AimComponent), isTrue);
    // the driver runs before every match component in the update order (Flame's own World/Camera hold nothing)
    final mine = kids.where((c) => c is! World && c is! CameraComponent).toList();
    expect(mine.first, isA<FixedStepDriver>());
    expect(kids.indexOf(mine.first) < kids.indexOf(space), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Flame-driven match == headless engine fed the same frame times (bit-exact)', (tester) async {
    final a = _eng(), b = _eng();
    final dts = <double>[];
    final g = MatchGame(e: a, onTick: (dt) {
      dts.add(dt);
      a.update(dt);
    });
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: g)));
    await tester.pump(const Duration(milliseconds: 16));
    _shoot(a);
    _shoot(b);
    final ms = [16, 17, 15, 33, 16, 8, 16, 16, 50, 16];
    for (var i = 0; i < 240; i++) {
      await tester.pump(Duration(milliseconds: ms[i % ms.length]));
    }
    expect(dts.length, greaterThan(200));
    for (final dt in dts) {
      b.update(dt);
    }
    for (var i = 0; i < a.bodies.length; i++) {
      expect(a.bodies[i].x, b.bodies[i].x, reason: 'x $i');
      expect(a.bodies[i].y, b.bodies[i].y, reason: 'y $i');
      expect(a.bodies[i].vx, b.bodies[i].vx);
      expect(a.bodies[i].vy, b.bodies[i].vy);
    }
    expect(a.score, b.score);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('soft camera: bounded drift, still while aiming', (tester) async {
    final e = _eng();
    final g = MatchGame(e: e, onTick: e.update);
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: g)));
    await tester.pump(const Duration(milliseconds: 16));
    _shoot(e);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(g.softCam.x.abs(), lessThanOrEqualTo(SoftCamera.maxPx + 1e-6));
      expect(g.softCam.y.abs(), lessThanOrEqualTo(SoftCamera.maxPx + 1e-6));
    }
    await tester.pumpWidget(const SizedBox());
  });
}
