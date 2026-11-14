import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/backgammon/core/backgammon_rules.dart';
import 'package:nexora/games/backgammon/online/backgammon_online.dart';
import 'package:nexora/games/core/online/gm_backend.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/ludo/core/ludo_rules.dart';
import 'package:nexora/games/ludo/online/ludo_online.dart';
import 'package:nexora/games/quiz/online/quiz_online.dart';
import 'package:nexora/games/snakes_ladders/online/snl_online.dart';
import 'package:nexora/games/uno/core/uno_engine.dart';
import 'package:nexora/games/uno/core/uno_models.dart';
import 'package:nexora/games/uno/online/uno_online.dart';

class _Watch implements GmWatch {
  bool closed = false;
  @override
  Future<void> close() async => closed = true;
}

/// In-memory backend: holds one view, counts calls, can fail moves.
class FakeBackend implements GmBackend {
  FakeBackend(this.current);
  Map<String, dynamic> current;
  int views = 0;
  int ticks = 0;
  final List<Map<String, dynamic>> moves = <Map<String, dynamic>>[];
  final List<int?> versions = <int?>[];
  String? failWith;
  void Function()? onChange;
  _Watch? watcher;

  @override
  Future<Map<String, dynamic>> view(String matchId) async {
    views++;
    return current;
  }

  @override
  Future<Map<String, dynamic>> move(String matchId, Map<String, dynamic> move, {int? version}) async {
    if (failWith != null) throw Exception(failWith);
    moves.add(move);
    versions.add(version);
    current = <String, dynamic>{...current, 'version': (current['version'] as int) + 1};
    return current;
  }

  @override
  Future<Map<String, dynamic>> tick(String matchId) async {
    ticks++;
    return current;
  }

  @override
  Future<Map<String, dynamic>> resign(String matchId) async {
    current = <String, dynamic>{
      ...current,
      'status': 'finished',
      'version': (current['version'] as int) + 1,
      'result': <String, dynamic>{'winners': <int>[1], 'reason': 'resign', 'rating_delta': <int>[-16, 16]},
    };
    return current;
  }

  @override
  Future<Map<String, dynamic>> shot(String matchId, int version, Map<String, dynamic> state, int nextTurn,
          {Map<String, dynamic>? finish}) async =>
      current;

  @override
  GmWatch watch(String matchId, String uid, void Function() onChange, void Function(bool connected) onStatus) {
    this.onChange = onChange;
    onStatus(true);
    return watcher = _Watch();
  }

  @override
  Future<Map<String, dynamic>> createRoom(String game, int seats, {String? name, bool private = false, Map<String, dynamic>? settings}) async =>
      <String, dynamic>{};
  @override
  Future<Map<String, dynamic>> joinRoom({String? code, String? roomId, bool spectate = false}) async => <String, dynamic>{};
  @override
  Future<Map<String, dynamic>> quick(String game, int seats) async => <String, dynamic>{};
  @override
  Future<void> takeSeat(String roomId, int seat) async {}
  @override
  Future<Map<String, dynamic>> updateRoom(String roomId, {int? seats, Map<String, dynamic>? settings}) async => <String, dynamic>{};
  @override
  Future<void> setReady(String roomId, bool ready) async {}
  @override
  Future<String> start(String roomId) async => 'm1';
  @override
  Future<void> leave(String roomId) async {}
  @override
  Future<String?> roomMatch(String roomId) async => 'm1';
  @override
  Future<List<Map<String, dynamic>>> rooms(String game) async => <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> leaderboard(String game, {int limit = 20}) async => <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>?> myRating(String game, String uid) async => null;
}

Map<String, dynamic> viewJson({
  String game = 'backgammon',
  int version = 1,
  int turn = 0,
  String status = 'live',
  int? mySeat = 0,
  DateTime? now,
  DateTime? deadline,
  Map<String, dynamic>? state,
}) =>
    <String, dynamic>{
      'match_id': 'm1',
      'room_id': 'r1',
      'game': game,
      'seats': <String>['u0', 'u1'],
      'names': <String>['Ana', 'Bob'],
      'status': status,
      'phase': 'roll',
      'turn': turn,
      'version': version,
      'state': state ?? <String, dynamic>{'out': <bool>[false, false], 'strikes': <int>[0, 2], 'scores': <int>[0, 0]},
      'deadline': deadline?.toUtc().toIso8601String(),
      'now': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'result': null,
      'authority': 'server',
      'ranked': true,
      'my_seat': mySeat,
      'private': <String, dynamic>{},
    };

void main() {
  group('GmView', () {
    test('parses the gm_view wire format', () {
      final GmView v = GmView(viewJson(turn: 0));
      expect(v.matchId, 'm1');
      expect(v.seatCount, 2);
      expect(v.nameOf(1), 'Bob');
      expect(v.myTurn, isTrue);
      expect(v.live, isTrue);
      expect(v.strikesOf(1), 2);
      expect(v.isOut(0), isFalse);
      expect(v.myOutcome, isNull);
    });

    test('outcome, winners and rating delta', () {
      final Map<String, dynamic> j = viewJson(status: 'finished', mySeat: 1);
      j['result'] = <String, dynamic>{'winners': <int>[1], 'scores': <int>[0, 2], 'reason': 'gammon', 'rating_delta': <int>[-15, 15]};
      final GmView v = GmView(j);
      expect(v.finished, isTrue);
      expect(v.myOutcome, 1);
      expect(v.myRatingDelta, 15);
      expect(v.reason, 'gammon');
      final Map<String, dynamic> d = viewJson(status: 'finished');
      d['result'] = <String, dynamic>{'winners': <int>[0, 1]};
      expect(GmView(d).myOutcome, 0);
    });

    test('spectator never has a turn', () {
      expect(GmView(viewJson(mySeat: null)).myTurn, isFalse);
    });

    test('remaining time uses the server clock offset', () {
      final DateTime local = DateTime.utc(2026, 1, 1, 12);
      final DateTime deadline = DateTime.utc(2026, 1, 1, 12, 0, 30);
      // server is 10 s ahead of this device
      expect(gmRemaining(deadline, local, const Duration(seconds: 10)), const Duration(seconds: 20));
      expect(gmRemaining(deadline, local.add(const Duration(minutes: 1)), Duration.zero), Duration.zero);
    });

    test('turn games send versions, simultaneous games do not', () {
      expect(GmMove.versioned('backgammon'), isTrue);
      expect(GmMove.versioned('quiz'), isFalse);
      expect(GmMove.versioned('mafia'), isFalse);
      expect(const GmMove('play', <String, dynamic>{'card': 3}).toJson(), <String, dynamic>{'a': 'play', 'card': 3});
    });

    test('error text is bilingual', () {
      expect(gmErrorText('PostgrestException(message: not your turn, code: P0001)', true), 'نوبت تو نیست');
      expect(gmErrorText('stale version', false), contains('try again'));
    });

    test('specs match the server seat bounds', () {
      expect(gmSpec('mafia')!.minSeats, 6);
      expect(gmSpec('mafia')!.maxSeats, 12);
      expect(gmSpec('uno')!.maxSeats, 6);
      expect(gmSpec('ludo')!.seatChoices, <int>[2, 3, 4]);
      expect(gmPlayableGames, containsAll(<String>['backgammon', 'ludo', 'snakes_ladders', 'uno', 'quiz', 'mafia']));
      expect(gmSpec('billiards')!.playable, isFalse);
    });
  });

  group('GmMatchController', () {
    test('loads, sends versioned moves and ignores stale views', () async {
      final FakeBackend b = FakeBackend(viewJson(version: 3));
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', pollEvery: const Duration(hours: 1));
      await c.refresh();
      expect(c.view!.version, 3);
      expect(c.connected, isTrue);
      final bool ok = await c.move(const GmMove('roll'));
      expect(ok, isTrue);
      expect(b.moves.single['a'], 'roll');
      expect(b.versions.single, 3);
      expect(c.view!.version, 4);
      // an older view (late realtime echo) never replaces a newer one
      expect(c.accept(viewJson(version: 2)), isFalse);
      expect(c.view!.version, 4);
      c.dispose();
      expect(b.watcher!.closed, isTrue);
    });

    test('a rejected move surfaces an error and refetches', () async {
      final FakeBackend b = FakeBackend(viewJson());
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', isFa: false, pollEvery: const Duration(hours: 1));
      await c.refresh();
      final int before = b.views;
      b.failWith = 'illegal move';
      expect(await c.move(const GmMove('play')), isFalse);
      expect(c.error, 'That move is not allowed');
      expect(c.busy, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(b.views, greaterThan(before));
      c.clearError();
      expect(c.error, isNull);
      c.dispose();
    });

    test('realtime pings refetch the view', () async {
      final FakeBackend b = FakeBackend(viewJson());
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', pollEvery: const Duration(hours: 1));
      await c.refresh();
      b.current = viewJson(version: 9, turn: 1);
      b.onChange!();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.view!.version, 9);
      expect(c.view!.myTurn, isFalse);
      c.dispose();
    });

    test('an overdue deadline pokes gm_tick once per 3 s', () async {
      final DateTime now = DateTime.now();
      final FakeBackend b = FakeBackend(viewJson(now: now, deadline: now.subtract(const Duration(seconds: 5))));
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', pollEvery: const Duration(hours: 1));
      await c.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(b.ticks, 1);
      c.dispose();
    });

    test('resign finishes the match', () async {
      final FakeBackend b = FakeBackend(viewJson());
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', pollEvery: const Duration(hours: 1));
      await c.refresh();
      final List<GmView> seen = <GmView>[];
      final StreamSubscription<GmView> sub = c.views.listen(seen.add);
      expect(await c.resign(), isTrue);
      expect(c.view!.finished, isTrue);
      expect(c.view!.myOutcome, -1);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.finished, isTrue);
      await sub.cancel();
      c.dispose();
    });
  });

  group('wire adapters', () {
    test('backgammon board array round-trips into BgState', () {
      final List<int> b = List<int>.filled(28, 0);
      b[23] = 2;
      b[12] = 5;
      b[7] = 3;
      b[5] = 5;
      b[0] = -2;
      b[11] = -5;
      b[16] = -3;
      b[18] = -5;
      final BgState s = bgStateFromWire(b, 0);
      expect(s.key, BgState.initial().key);
      final BgTurnTracker t = BgTurnTracker(s, 0, <int>[3, 1]);
      final BgMove? m1 = t.play(const BgMove(7, 4, 3));
      final BgMove? m2 = t.play(const BgMove(5, 4, 1));
      expect(m1, isNotNull);
      expect(m2, isNotNull);
      expect(t.complete, isTrue);
      expect(bgPlayToWire(t.played), <List<int>>[<int>[7, 4, 3], <int>[5, 4, 1]]);
    });

    test('server card ids are buildUnoDeck ids', () {
      // same formulas as _gm_uno_kind / _gm_uno_color / _gm_uno_num in the migration
      String kind(int id) {
        if (id >= 104) return 'w4';
        if (id >= 100) return 'w';
        final int o = id % 25;
        if (o <= 18) return 'n';
        return <String>['skip', 'rev', 'd2'][(o - 19) % 3];
      }

      int num(int id) {
        final int o = id % 25;
        if (id >= 100 || o > 18) return -1;
        return o == 0 ? 0 : (o - 1) ~/ 2 + 1;
      }

      const Map<UnoKind, String> k = <UnoKind, String>{
        UnoKind.number: 'n',
        UnoKind.skip: 'skip',
        UnoKind.reverse: 'rev',
        UnoKind.drawTwo: 'd2',
        UnoKind.wild: 'w',
        UnoKind.wildDrawFour: 'w4',
      };
      for (final UnoCard c in buildUnoDeck()) {
        expect(kind(c.id), k[c.kind], reason: 'card ${c.id}');
        expect(num(c.id), c.number, reason: 'card ${c.id}');
        expect(c.id < 100 ? c.id ~/ 25 : -1, c.color?.index ?? -1, reason: 'card ${c.id}');
      }
    });

    test('uno legality matches the offline engine', () {
      final List<UnoCard> deck = buildUnoDeck();
      // hand: violet 5, turquoise skip, wild, wild draw four; top: turquoise 5
      final List<int> hand = <int>[25 + 9, 19, 100, 104];
      final UnoGame g = UnoGame.fromState(
        hands: <List<UnoCard>>[<UnoCard>[for (final int id in hand) deck[id]], <UnoCard>[deck[1]]],
        drawPile: <UnoCard>[deck[2], deck[3]],
        discard: <UnoCard>[deck[9]],
        activeColor: UnoColor.turquoise,
      );
      for (final int id in hand) {
        expect(unoOnlineLegal(hand, id, 9, UnoColor.turquoise.index), g.isLegal(0, deck[id]), reason: 'card $id');
      }
      // wild draw four is illegal while holding the active colour
      expect(unoOnlineLegal(hand, 104, 9, 0), isFalse);
      expect(unoOnlineLegal(<int>[104, 30], 104, 9, 0), isTrue);
    });

    test('ludo wire state', () {
      final LudoState s = ludoStateFromWire(<String, dynamic>{
        'corners': <int>[3, 0, 1],
        'tk': <List<int>>[<int>[-1, 0, 56, 10], <int>[-1, -1, -1, -1], <int>[51, 2, 3, 4]],
        'six': 1,
      }, 2);
      expect(s.playerCount, 3);
      expect(s.homeCount(0), 1);
      expect(s.turn, 2);
      expect(s.sixStreak, 1);
      expect(LudoRules.legalMoves(s, 0, 6).length, 3);
    });

    test('snakes path includes the snake / ladder end', () {
      expect(snlPathOf(<String, dynamic>{'from': 0, 'steps': <int>[1], 'final': 38}), <int>[0, 1, 38]);
      expect(snlPathOf(<String, dynamic>{'from': 97, 'steps': <int>[98, 99, 100, 99], 'final': 99}), <int>[97, 98, 99, 100, 99]);
    });

    test('every quiz id resolves to a local question', () {
      expect(quizQuestionById('space_001'), isNotNull);
      expect(quizQuestionById('nope'), isNull);
    });
  });
}
