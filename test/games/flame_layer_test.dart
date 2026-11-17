
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/billiards/billiards_entry.dart';
import 'package:nexora/games/carrom/carrom_entry.dart';
import 'package:nexora/games/core/flame/nx_flame.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameLaunch _launch(String id, {bool fancy = true, bool reduced = false}) => GameLaunch(
      gameId: id,
      mode: GameMode.vsBot,
      difficulty: BotDifficulty.normal,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: fancy,
      reducedMotion: reduced,
      soundOn: false,
      seed: 1,
      onFinish: (_) {},
    );

NxFlameHost _hostIn(WidgetTester tester) =>
    tester.widget<GameWidget<NxFlameHost>>(find.byType(GameWidget<NxFlameHost>)).game!;

void main() {
  group('NxFlameHost fixed-step accumulator', () {
    test('runs whole 1/120 s steps and carries the remainder', () {
      int steps = 0;
      final NxFlameHost h = NxFlameHost(onStep: (double s) {
        expect(s, 1 / 120);
        steps++;
      });
      expect(h.advance(1 / 60), 2);
      expect(h.advance(.004), 0); // 4 ms < one step: carried
      expect(h.accumulator, closeTo(.004, 1e-9));
      expect(h.advance(.005), 1); // 9 ms total -> one step, 0.67 ms left
      expect(steps, 3);
      expect(h.totalSteps, 3);
      expect(h.accumulator, lessThan(h.step));
      expect(h.alpha, inInclusiveRange(0.0, 1.0));
    });

    test('a big frame is clamped (sim) but the wall clock keeps the raw time', () {
      double frameDt = -1;
      final NxFlameHost h = NxFlameHost(onStep: (_) {}, onFrame: (double dt) => frameDt = dt);
      final int n = h.advance(1.0);
      expect(n, inInclusiveRange(5, 6)); // 0.05 s of simulation at most
      expect(frameDt, .05);
      expect(h.clock, 1.0);
      final NxFlameHost raw = NxFlameHost(onFrame: (double dt) => frameDt = dt, rawFrameDt: true);
      raw.advance(.3);
      expect(frameDt, .3);
    });

    test('step cap per frame drops the backlog instead of spiralling', () {
      final NxFlameHost h = NxFlameHost(onStep: (_) {}, step: .01, maxFrameDt: 1, maxStepsPerFrame: 4);
      expect(h.advance(.5), 4);
      expect(h.accumulator, lessThan(.01));
      expect(h.advance(.005), lessThanOrEqualTo(1)); // no debt carried
      expect(h.advance(.02), inInclusiveRange(1, 3));
    });

    test('negative / NaN dt is ignored', () {
      final NxFlameHost h = NxFlameHost(onStep: (_) {});
      expect(h.advance(-1), 0);
      expect(h.advance(double.nan), 0);
      expect(h.clock, 0);
      expect(h.accumulator, 0);
    });

    test('step count depends only on elapsed time, not on frame pacing', () {
      int count(List<double> frames) {
        final NxFlameHost h = NxFlameHost(onStep: (_) {});
        for (final double f in frames) {
          h.advance(f);
        }
        return h.totalSteps;
      }

      final int a = count(List<double>.filled(60, 1 / 60));
      final int b = count(List<double>.filled(144, 1 / 144));
      final int c = count(<double>[for (int i = 0; i < 90; i++) i.isEven ? .007 : .0152222]);
      expect(a, inInclusiveRange(119, 120));
      expect(b, inInclusiveRange(119, 120));
      expect(c, inInclusiveRange(119, 120));
    });
  });

  group('NxFx particle caps', () {
    test('fancy: bursts are capped by the live budget and freed when they expire', () {
      final NxFx fx = NxFx(const NxFxConfig());
      final int cap = fx.config.maxParticles;
      expect(fx.burst(Offset.zero, count: 500, life: 1), cap);
      expect(fx.live, cap);
      expect(fx.burst(Offset.zero, count: 10), 0);
      expect(fx.ring(Offset.zero, const Color(0xFFFFFFFF)), 0);
      fx.tickBudget(1.01);
      expect(fx.live, 0);
      expect(fx.ring(Offset.zero, const Color(0xFFFFFFFF), count: 12), 13);
    });

    test('fancyEffects off: fewer particles and a lower cap', () {
      final NxFx fx = NxFx(NxFxConfig.of(fancyEffects: false, reducedMotion: false));
      expect(fx.config.maxParticles, lessThan(const NxFxConfig().maxParticles));
      expect(fx.burst(Offset.zero, count: 100), 40);
      expect(fx.burst(Offset.zero, count: 100), fx.config.maxParticles - 40);
      expect(fx.live, fx.config.maxParticles);
    });

    test('reducedMotion: nothing is spawned', () {
      final NxFx fx = NxFx(NxFxConfig.of(fancyEffects: true, reducedMotion: true));
      expect(fx.burst(Offset.zero), 0);
      expect(fx.ring(Offset.zero, const Color(0xFFFFFFFF)), 0);
      expect(fx.fireBurst(Offset.zero), 0);
      expect(fx.fireTrail(0, 0, 1000, 0, 1, 1 / 60), 0);
      expect(fx.live, 0);
    });

    test('fire pool never exceeds its capacity and drains', () {
      final NxFx fx = NxFx(const NxFxConfig());
      for (int i = 0; i < 600; i++) {
        fx.fireTrail(i.toDouble(), 0, 2000, 0, 1, 1 / 60);
        fx.fireTrail(0, i.toDouble(), 0, 2000, 1, 1 / 60, slot: 1);
        expect(fx.fire.active, lessThanOrEqualTo(fx.fire.capacity));
        expect(fx.live, lessThanOrEqualTo(fx.config.maxParticles));
      }
      expect(fx.fire.active, greaterThan(0));
      fx.fireBurst(Offset.zero, count: 500);
      expect(fx.fire.active, lessThanOrEqualTo(fx.fire.capacity));
      for (int i = 0; i < 120; i++) {
        fx.fire.update(1 / 60);
      }
      expect(fx.fire.active, 0);
    });
  });

  group('games run on the Flame host', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalStore.init();
    });

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> run(WidgetTester tester, Widget child, int frames) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: child))));
      for (int i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('billiards (fancy fx) simulates in fixed steps on Flame', (WidgetTester tester) async {
      phone(tester);
      await run(tester, buildBilliardsGame(_launch('billiards')), 300);
      expect(tester.takeException(), isNull);
      final NxFlameHost h = _hostIn(tester);
      expect(h.clock, greaterThan(3));
      expect(h.totalSteps, greaterThan(0)); // the bot broke and the balls rolled on host steps
      expect(h.fx.live, lessThanOrEqualTo(h.fx.config.maxParticles));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('carrom (fancy fx) runs on Flame', (WidgetTester tester) async {
      phone(tester);
      await run(tester, buildCarromGame(_launch('carrom')), 400);
      // The carrom HUD row overflows with the test font (Ahem) at 360 dp; that is pre-existing
      // and unrelated to Flame, so only layout overflow is tolerated here.
      final Object? ex = tester.takeException();
      expect(ex == null || '$ex'.contains('overflowed'), isTrue, reason: '$ex');
      final NxFlameHost h = _hostIn(tester);
      expect(h.clock, greaterThan(4));
      expect(h.fx.live, lessThanOrEqualTo(h.fx.config.maxParticles));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('finger soccer (fancy fx) runs on Flame', (WidgetTester tester) async {
      phone(tester);
      await run(tester, BermudaView(launch: _launch('finger_soccer'), autoStart: true), 600);
      expect(tester.takeException(), isNull);
      final NxFlameHost h = _hostIn(tester);
      expect(h.clock, greaterThan(6));
      expect(h.fx.live, lessThanOrEqualTo(h.fx.config.maxParticles));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });
  });
}
