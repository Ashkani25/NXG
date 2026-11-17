// ignore_for_file: invalid_use_of_visible_for_testing_member
// Renders both finger-soccer goal models on the pitch: the real match screen, plus a geometry
// check (BmPainter output with red rings on the physics collision posts and a cyan goal line).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:nexora/games/finger_soccer/core/bm_goal_art.dart';
import 'package:nexora/games/finger_soccer/ui/bm_painter.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

class _H implements BmHooks {
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
  void emit(String event, Map<String, dynamic> data) {}
}

Future<ui.Image> _load(String a) async {
  final ByteData d = await rootBundle.load(a);
  final ui.Codec c = await ui.instantiateImageCodec(d.buffer.asUint8List());
  return (await c.getNextFrame()).image;
}

void main() {
  for (int gs = 0; gs < kBmGoalArts.length; gs++) {
    final BmGoalArt art = kBmGoalArts[gs];
    testWidgets('goal ${art.id} geometry', (WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final int field in <int>[0, 6]) {
          final BmEngine e = BmEngine(_H(), rng: math.Random(3));
          e.startMatch(BmConfig(
              mode: 'local', teams: const <String>['club0', 'club1'], form: const <int>[0, 0],
              names: const <String>['A', 'B'], field: field, ball: 0));
          final BmImages im = BmImages()
            ..field = await _load('assets/games/bermuda/fields/${kBmFields[field].id}.webp')
            ..goal = await _load(art.asset)
            ..goalArt = art
            ..ball = await _load('assets/games/bermuda/balls/b0.webp');
          final BmView v = BmView();
          const Size sz = Size(390, 844);
          final ui.PictureRecorder rec = ui.PictureRecorder();
          final Canvas c = Canvas(rec);
          c.scale(2);
          BmPainter(e, im, v, () => 0, 2, false, repaint: ValueNotifier<int>(0)).paint(c, sz);
          final Paint red = Paint()
            ..color = const Color(0xFFFF2020)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          final Paint cyan = Paint()
            ..color = const Color(0xFF00E5FF)
            ..strokeWidth = 1;
          Offset sc(double x, double y) => Offset(x * v.s + v.ox, y * v.s + v.oy);
          for (final BmGoal g in e.GOALS) {
            c.drawLine(sc(g.x1 - 60, g.y), sc(g.x2 + 60, g.y), cyan);
            c.drawCircle(sc(g.x1, g.y), 4, red);
            c.drawCircle(sc(g.x2, g.y), 4, red);
          }
          final ui.Image img = await rec.endRecording().toImage(780, 1688);
          final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
          final File f = File('$kShots/goals/geom_${art.id}_f$field.png')..parent.createSync(recursive: true);
          f.writeAsBytesSync(bd!.buffer.asUint8List());
        }
      });
    });

    testWidgets('goal ${art.id} in the match', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{'bm.goal': gs});
      await LocalStore.init();
      await loadFonts();
      phone(tester);
      await tester.pumpWidget(shotApp(BermudaView(
          launch: GameLaunch(
              gameId: 'finger_soccer', mode: GameMode.local, difficulty: BotDifficulty.normal,
              playerName: 'Ashkan', isFa: false, fancyEffects: true, reducedMotion: false,
              soundOn: false, seed: 2, onFinish: (_) {}),
          autoStart: true)));
      await settle(tester, frames: 40);
      await shoot(tester, 'goals/match_${art.id}.png');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final bool fa in <bool>[false, true]) {
    testWidgets('setup screen with disc stats and goal picker (fa=$fa)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.init();
      await loadFonts();
      phone(tester, h: 1400);
      await tester.pumpWidget(shotApp(BermudaView(
          launch: GameLaunch(
              gameId: 'finger_soccer', mode: GameMode.vsBot, difficulty: BotDifficulty.normal,
              playerName: 'Ashkan', isFa: fa, fancyEffects: true, reducedMotion: false,
              soundOn: false, seed: 2, onFinish: (_) {}))));
      await settle(tester, frames: 30);
      await shoot(tester, 'goals/setup_${fa ? 'fa' : 'en'}.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
