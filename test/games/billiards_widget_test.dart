import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/billiards/billiards_entry.dart';
import 'package:nexora/games/disc_football/disc_football_entry.dart';
import 'package:nexora/games/game_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameLaunch _launch(String id, List<GameResult> results, {GameMode mode = GameMode.vsBot, bool isFa = true}) => GameLaunch(
      gameId: id,
      mode: mode,
      difficulty: BotDifficulty.normal,
      playerName: 'Tester',
      isFa: isFa,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: 1, // odd seed: in billiards the bot breaks, so the bot loop runs
      onFinish: results.add,
    );

Future<void> _pumpFor(WidgetTester tester, Widget child, Duration total) async {
  final FlutterExceptionHandler? old = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    // Surface the full diagnostic in CI logs (prefixed so the log filter keeps it).
    for (final String line in d.toString().split('\n').take(40)) {
      // ignore: avoid_print
      print('Error: $line');
    }
    old?.call(d);
  };
  try {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: child))));
    const Duration frame = Duration(milliseconds: 16);
    int n = total.inMilliseconds ~/ frame.inMilliseconds;
    while (n-- > 0) {
      await tester.pump(frame);
    }
  } finally {
    FlutterError.onError = old;
  }
}

void main() {
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

  testWidgets('billiards vs bot runs a few seconds on 360x640 without errors', (WidgetTester tester) async {
    phone(tester);
    final List<GameResult> results = <GameResult>[];
    await _pumpFor(tester, buildBilliardsGame(_launch('billiards', results)), const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
    expect(results.length, lessThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('billiards local (English) builds without overflow', (WidgetTester tester) async {
    phone(tester);
    final List<GameResult> results = <GameResult>[];
    await _pumpFor(tester, buildBilliardsGame(_launch('billiards', results, mode: GameMode.local, isFa: false)),
        const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('registry wires finger_soccer to the Disc Football entry', () {
    final GameInfo? g = gameById('finger_soccer');
    expect(g, isNotNull);
    expect(g!.builder, same(buildDiscFootballGame));
  });

  testWidgets('finger soccer (disc football) setup screen runs a few seconds on 360x640 without errors',
      (WidgetTester tester) async {
    phone(tester);
    final List<GameResult> results = <GameResult>[];
    final FlutterExceptionHandler? old = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      for (final String line in d.toString().split('\n').take(60)) {
        // ignore: avoid_print
        print('Error: $line');
      }
      old?.call(d);
    };
    addTearDown(() => FlutterError.onError = old);
    await _pumpFor(tester, gameById('finger_soccer')!.builder(_launch('finger_soccer', results)), const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(results.length, lessThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
