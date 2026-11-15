// v0.7.0 tournaments: every format (single, best-of / first-to, aggregate, real two-leg with away goals + deciders),
// rankings points, the app-wide auto-move rule, deep-link entries, the 30 s lineup timer and the ready flow, and
// the server migration's contract (the RPCs the app calls exist there, additive only, RLS tightened).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/game/data.dart' show kForms;
import 'package:nexora/online/cup_alerts.dart';
import 'package:nexora/online/cup_lineup.dart';
import 'package:nexora/online/cup_logic.dart';
import 'package:nexora/online/cup_reminders.dart';
import 'package:nexora/online/online_match.dart';
import 'package:nexora/net/supabase.dart' show Rec;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('formats (mirror of _cup_series_winner_v3)', () {
    test('single game: its winner', () {
      expect(playSeriesV3('single', 1, 1, [(3, 1)]), (1, 1));
      expect(playSeriesV3('single', 1, 1, [(0, 3)]), (2, 1));
    });
    test('single game drawn (forfeit 0:0) -> golden-goal decider', () {
      expect(playSeriesV3('single', 1, 1, [(0, 0)]), (0, 1));
      expect(playSeriesV3('single', 1, 1, [(0, 0), (0, 1)]), (2, 2));
    });
    test('best-of-N / first-to-N wins', () {
      expect(playSeriesV3('first_to', 3, 2, [(3, 0), (3, 1)]), (1, 2));
      expect(playSeriesV3('first_to', 3, 2, [(3, 0), (0, 3), (1, 3)]), (2, 3));
      expect(playSeriesV3('first_to', 5, 3, [(3, 0), (0, 3), (3, 2), (1, 3), (3, 1)]), (1, 5));
      expect(playSeriesV3('first_to', 7, 4, [(3, 0), (3, 0), (3, 0), (3, 0)]), (1, 4));
    });
    test('aggregate goals over N games', () {
      expect(playSeriesV3('aggregate', 2, 1, [(3, 0), (2, 4)]), (1, 2)); // 5:4
      expect(playSeriesV3('aggregate', 3, 1, [(1, 3), (3, 0), (0, 2)]), (2, 3)); // 4:5
      expect(playSeriesV3('aggregate', 2, 1, [(3, 0), (0, 3)]), (0, 2)); // level -> decider
      expect(playSeriesV3('aggregate', 2, 1, [(3, 0), (0, 3), (1, 0)]), (1, 3));
    });
    test('two-leg: aggregate decides, away goals OFF by default -> decider', () {
      // leg 1 at p1 (2:1), leg 2 at p2 (p1 scores 1, p2 scores 2): 3:3 aggregate
      expect(playSeriesV3('two_leg', 2, 1, [(2, 1), (1, 2)]), (0, 2));
      expect(playSeriesV3('two_leg', 2, 1, [(2, 1), (1, 2), (0, 1)]), (2, 3)); // golden-goal decider
      expect(playSeriesV3('two_leg', 2, 1, [(3, 1), (1, 2)]), (1, 2)); // 4:3
    });
    test('two-leg with the away-goals rule', () {
      // 3:3 aggregate; p1's away goals (leg 2) = 1, p2's away goals (leg 1) = 1 -> still level -> decider
      expect(playSeriesV3('two_leg', 2, 1, [(2, 1), (1, 2)], awayGoals: true), (0, 2));
      // 2:2 aggregate; p1 away goals 2 (leg 2), p2 away goals 0 -> p1
      expect(playSeriesV3('two_leg', 2, 1, [(0, 0), (2, 2)], awayGoals: true), (1, 2));
      // same scores without the rule -> decider
      expect(playSeriesV3('two_leg', 2, 1, [(0, 0), (2, 2)]), (0, 2));
    });
    test('two-leg home sides and decider goals', () {
      expect(cupHomeSide('two_leg', 1), 1);
      expect(cupHomeSide('two_leg', 2), 2);
      expect(cupHomeSide('two_leg', 3), 1); // decider at the higher seed
      expect(cupIsDecider('two_leg', 2, 3), isTrue);
      expect(cupIsDecider('two_leg', 2, 2), isFalse);
      expect(cupGoalsFor('two_leg', 2, 3, 3, 'golden_goal'), 1);
      expect(cupGoalsFor('two_leg', 2, 3, 3, 'game'), 3);
      expect(cupGoalsFor('aggregate', 3, 5, 2, 'golden_goal'), 5);
    });
    test('after 3 drawn deciders the higher seed advances (no endless tie)', () {
      expect(playSeriesV3('aggregate', 2, 1, [(1, 1), (1, 1), (0, 0), (0, 0), (0, 0)]), (1, 5));
    });
    test('create params are normalised per format', () {
      final s = DateTime.utc(2026, 12, 1, 16, 30);
      final two = cupCreateParams(name: 'x', max: 64, mode: 'two_leg', games: 7, targetWins: 3, goals: 3, startsUtc: s, awayGoals: true);
      expect(two['p_games'], 2);
      expect(two['p_target_wins'], 1);
      expect(two['p_away_goals'], isTrue);
      final ft = cupCreateParams(name: 'x', max: 64, mode: 'first_to', games: 1, targetWins: 4, goals: 3, startsUtc: s, awayGoals: true);
      expect(ft['p_games'], 7);
      expect(ft['p_away_goals'], isFalse);
      expect(ft['p_starts'], '2026-12-01T16:30:00.000Z');
      expect(kCupMaxPlayers, 64);
    });
    test('labels', () {
      expect(cupSeriesLabel('two_leg', 2, 1), 'رفت و برگشت · مجموع گل');
      expect(cupGameLabelFa('two_leg', 2, 3, 2, 'golden_goal', meIsP1: false), contains('میزبان تویی'));
      expect(cupGameLabelFa('two_leg', 2, 3, 3, 'golden_goal'), contains('گل طلایی'));
    });
  });

  group('rankings (mirror of _cup_rank_points)', () {
    test('points', () {
      expect(cupRankPoints(titles: 1, cups: 1, seriesWins: 4), 25 + 2 + 12);
      expect(cupRankPoints(runnerUp: 1, cups: 1, seriesWins: 3), 15 + 2 + 9);
      expect(cupRankPoints(third: 1, fourth: 0, cups: 2, seriesWins: 1), 10 + 4 + 3);
      expect(cupRankPoints(fourth: 1), 6);
    });
    test('a title always outranks a runner-up in the same cup', () {
      expect(cupRankPoints(titles: 1, cups: 1, seriesWins: 1) > cupRankPoints(runnerUp: 1, cups: 1, seriesWins: 1), isTrue);
    });
  });

  group('auto-move + deep links', () {
    test('both paired players are moved when the pairing becomes ready', () {
      final row = {'id': 'm1', 'cup_id': 'c1', 'p1': 'a', 'p2': 'b', 'status': 'ready'};
      expect(cupShouldAutoEnter(row: row, uid: 'a', entered: {}, inCupRoom: false), isTrue);
      expect(cupShouldAutoEnter(row: row, uid: 'b', entered: {}, inCupRoom: false), isTrue);
      expect(cupShouldAutoEnter(row: row, uid: 'z', entered: {}, inCupRoom: false), isFalse);
      expect(cupShouldAutoEnter(row: row, uid: 'a', entered: {'m1'}, inCupRoom: false), isFalse); // once
      expect(cupShouldAutoEnter(row: row, uid: 'a', entered: {}, inCupRoom: true), isFalse);
      expect(cupShouldAutoEnter(row: {...row, 'status': 'pending'}, uid: 'a', entered: {}, inCupRoom: false), isFalse);
    });
    test('notification payloads deep-link', () {
      expect(cupMatchEntry('cupmatch:c1:m1'), ('c1', 'm1'));
      expect(cupMatchEntry('cup:c1'), isNull);
      expect(cupEntryOf('c1'), 'cup:c1'); // old payload (bare id)
      expect(cupEntryOf('cupmatch:c1:m1'), 'cupmatch:c1:m1');
    });
    test('room formations from the server lineup reach both peers', () {
      expect(roomForms(Rec({'forms': [2, 5]})), [2, 5]);
      expect(roomForms(Rec({})), [0, 0]);
      expect(roomForms(Rec({'forms': [99, -1]})), [kForms.length - 1, 0]);
    });
  });

  group('30 s lineup timer', () {
    final t0 = DateTime.utc(2026, 11, 20, 18);
    test('never more than 30 s after the Play press', () {
      expect(kCupLineupSeconds, 30);
      expect(lineupSecondsLeft(now: t0, pressedAt: t0), 30);
      expect(lineupSecondsLeft(now: t0.add(const Duration(seconds: 12)), pressedAt: t0), 18);
      expect(lineupSecondsLeft(now: t0.add(const Duration(seconds: 31)), pressedAt: t0), 0);
      // a later server deadline does not extend it
      expect(lineupSecondsLeft(now: t0, pressedAt: t0, serverUntil: t0.add(const Duration(seconds: 50))), 30);
    });
    test('an earlier server deadline shortens it', () {
      expect(lineupSecondsLeft(now: t0, pressedAt: t0, serverUntil: t0.add(const Duration(seconds: 9))), 9);
      expect(lineupSecondsLeft(now: t0, pressedAt: t0, serverUntil: t0.subtract(const Duration(seconds: 1))), 0);
    });
    test('defaults when nothing was picked', () {
      final d = lineupFinal(equippedTeam: 'club3', roomField: 4, roomBall: 7);
      expect(d.team, 'club3');
      expect(d.formation, 0);
      expect((d.field, d.ball), (4, 7));
      final p = lineupFinal(pickedTeam: 'club9', pickedFormation: 3, pickedField: 1, pickedBall: 2, equippedTeam: 'club3', roomField: 4, roomBall: 7);
      expect((p.team, p.formation, p.field, p.ball), ('club9', 3, 1, 2));
    });
  });

  group('ready flow (CupLineupScreen + cup_ready)', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.i.load();
    });

    testWidgets('Play opens the window, picks are saved, timer end sends the final lineup and closes', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      var now = DateTime.utc(2026, 11, 20, 18);
      final sent = <Map<String, Object?>>[];
      bool? done;
      await t.pumpWidget(MaterialApp(
        home: CupLineupScreen(
          matchId: 'm1',
          isHost: true,
          roomField: 4,
          roomBall: 7,
          clock: () => now,
          send: (p) async {
            sent.add(Map.of(p));
            return {'lineup_until': now.add(const Duration(seconds: 30)).toIso8601String(), 'status': 'ready'};
          },
          onDone: (s) => done = s,
        ),
      ));
      await t.pump(const Duration(milliseconds: 50));
      expect(sent.length, 1, reason: 'pressing Play sends cup_ready at once (opens the server window)');
      expect(sent.first['p_match'], 'm1');
      expect(sent.first['p_field'], 4);
      expect(sent.first['p_ball'], 7);
      expect(find.text('۳۰'), findsOneWidget);
      // pick formation 2 -> saved (debounced)
      await t.tap(find.byKey(const ValueKey('lineupForm2')));
      await t.pump(const Duration(milliseconds: 400));
      expect(sent.last['p_formation'], 2);
      // pick ball 3 (host)
      await t.ensureVisible(find.byKey(const ValueKey('lineupBall3')));
      await t.tap(find.byKey(const ValueKey('lineupBall3')));
      await t.pump(const Duration(milliseconds: 400));
      expect(sent.last['p_ball'], 3);
      final before = sent.length;
      // time passes: 29.5 s after the press -> final send + close, without anyone pressing Ready
      now = now.add(const Duration(milliseconds: 29500));
      await t.pump(const Duration(milliseconds: 250));
      await t.pump(const Duration(milliseconds: 50));
      expect(sent.length, before + 1);
      expect(sent.last['p_formation'], 2);
      expect(sent.last['p_ball'], 3);
      expect(done, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Ready sends immediately; a non-host never sends pitch/ball', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      final now = DateTime.utc(2026, 11, 20, 18);
      final sent = <Map<String, Object?>>[];
      bool? done;
      await t.pumpWidget(MaterialApp(
        home: CupLineupScreen(
          matchId: 'm2',
          isHost: false,
          roomField: 4,
          roomBall: 7,
          clock: () => now,
          send: (p) async {
            sent.add(Map.of(p));
            return {'status': sent.length >= 2 ? 'live' : 'ready'};
          },
          onDone: (s) => done = s,
        ),
      ));
      await t.pump(const Duration(milliseconds: 50));
      await t.ensureVisible(find.byKey(const ValueKey('lineupReady')));
      await t.tap(find.byKey(const ValueKey('lineupReady')));
      await t.pump(const Duration(milliseconds: 100));
      expect(sent.length, 2);
      expect(sent.every((p) => p['p_field'] == null && p['p_ball'] == null), isTrue);
      expect(done, isTrue, reason: 'both ready -> server started the game');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('server migration contract', () {
    final sql = File('supabase/migrations/20261117_cups_v070.sql').readAsStringSync();
    final plus = File('supabase/migrations/20261116_cups_plus.sql').readAsStringSync();
    final lib = [for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) f.readAsStringSync()].join('\n');
    test('every cup RPC the app calls is defined by cups.sql or a migration', () {
      final all = sql + plus + File('supabase/cups.sql').readAsStringSync();
      final called = RegExp(r"rpc\(\s*'(cup_[a-z0-9_]+)'").allMatches(lib).map((m) => m.group(1)!).toSet();
      expect(called, containsAll(['cup_create_v3', 'cup_ready', 'cup_ranking', 'cup_enter', 'cup_join', 'cup_checkin', 'cup_approve']));
      for (final f in called) {
        expect(all.contains('function public.$f('), isTrue, reason: f);
      }
    });
    test('additive only: no table/column drops, old cup_create revoked, ledger not world-readable', () {
      expect(RegExp(r'drop\s+table', caseSensitive: false).hasMatch(sql), isFalse);
      expect(RegExp(r'drop\s+column', caseSensitive: false).hasMatch(sql), isFalse);
      expect(sql, contains('revoke execute on function public.cup_create(text, int, int, int, timestamptz, int, int[], boolean) from public, anon, authenticated'));
      expect(sql, contains('create policy "cup_ledger own"'));
      expect(sql, contains("'two_leg'"));
      expect(sql, contains("cron.schedule('nexora-cups', '10 seconds'"));
      expect(sql, contains("raise exception 'request rejected'"));
      expect(sql, contains('_cup_expire_pending'));
    });
  });
}

