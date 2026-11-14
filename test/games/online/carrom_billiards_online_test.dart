import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/billiards/core/pool_match.dart';
import 'package:nexora/games/carrom/core/carrom_config.dart';
import 'package:nexora/games/carrom/core/carrom_match.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/core/online/billiards_online.dart';
import 'package:nexora/games/core/online/billiards_online_sync.dart';
import 'package:nexora/games/core/online/carrom_online.dart';
import 'package:nexora/games/core/online/carrom_online_sync.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';

import 'fake_gm_backend.dart';

/// Like the server: JSON round trip of the submitted state.
Map<String, dynamic> _wire(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

Map<String, dynamic> _hostView(String game,
    {int version = 3, int turn = 0, int? mySeat = 0, Map<String, dynamic>? state, String status = 'live'}) {
  final DateTime now = DateTime.now().toUtc();
  return <String, dynamic>{
    'match_id': 'm1',
    'room_id': 'r1',
    'game': game,
    'seats': <String>['u0', 'u1'],
    'names': <String>['Ana', 'Bob'],
    'status': status,
    'phase': 'shoot',
    'turn': turn,
    'version': version,
    'state': <String, dynamic>{
      'seed': 42,
      'shots': 0,
      'out': <bool>[false, false],
      'strikes': <int>[0, 0],
      'scores': <int>[0, 0],
      ...?state,
    },
    'deadline': now.add(const Duration(seconds: 45)).toIso8601String(),
    'now': now.toIso8601String(),
    'result': null,
    'authority': 'host',
    'ranked': false,
    'my_seat': mySeat,
    'private': <String, dynamic>{},
  };
}

/// Records gm_shot calls and behaves like the server (version+1, turn, shots+1, merged state).
class ShotBackend extends FakeBackend {
  ShotBackend(super.current);
  final List<Map<String, dynamic>> shots = <Map<String, dynamic>>[];
  final List<int> turns = <int>[];
  final List<Map<String, dynamic>?> finishes = <Map<String, dynamic>?>[];

  @override
  Future<Map<String, dynamic>> shot(String matchId, int version, Map<String, dynamic> state, int nextTurn,
      {Map<String, dynamic>? finish}) async {
    if (version != current['version']) throw Exception('stale version');
    shots.add(state);
    turns.add(nextTurn);
    finishes.add(finish);
    final Map<String, dynamic> old = Map<String, dynamic>.from(current['state'] as Map);
    current = <String, dynamic>{
      ...current,
      'version': (current['version'] as int) + 1,
      'turn': nextTurn,
      'state': <String, dynamic>{
        ..._wire(state),
        'out': old['out'],
        'strikes': old['strikes'],
        'scores': state['scores'] ?? old['scores'],
        'shots': ((old['shots'] as int?) ?? 0) + 1,
      },
      if (finish != null) 'status': 'finished',
      if (finish != null) 'result': <String, dynamic>{'winners': finish['winners'], 'reason': finish['reason']},
    };
    return current;
  }
}

GameLaunch _launch() => GameLaunch(
      gameId: 'carrom',
      mode: GameMode.local,
      difficulty: BotDifficulty.normal,
      playerName: '',
      isFa: false,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      onFinish: (GameResult _) {},
    );

Future<void> _flush() async {
  for (int i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('carrom online sync', () {
    test('a fresh match derives the break board with the server turn', () {
      final GmView v = GmView(_hostView('carrom', turn: 0));
      final CrMatch m = CarromOnlineSync.derive(v);
      expect(m.turn, 0);
      expect(m.phase, CrPhase.aiming);
      expect(m.stateHash(), CrMatch.newBoard().stateHash());
    });

    test('submitted state round-trips and the opponent replay is identical', () {
      final CrMatch m = CrMatch.newBoard();
      final CrMatch prev = m.clone();
      const CrShot shot = CrShot(placeX: 520, dirX: -0.05, dirY: -1, power: 0.92);
      m.playShot(shot);
      final Map<String, dynamic> st = CarromOnlineSync.encode(prev: prev, shot: shot, after: m, shooter: 0, seed: 42);
      expect(jsonEncode(st).length, lessThan(20000));
      final GmView opp = GmView(_hostView('carrom', turn: m.turn, mySeat: 1, state: <String, dynamic>{..._wire(st), 'shots': 1}));
      expect(CarromOnlineSync.derive(opp).stateHash(), m.stateHash());
      expect(CarromOnlineSync.shouldReplay(opp, 0), isTrue);
      expect(CarromOnlineSync.shouldReplay(opp, 1), isFalse);
      final CrMatch? again = CarromOnlineSync.boardFrom(opp.state['prev']);
      final CrShot? s2 = CarromOnlineSync.shotFrom(opp.state['shot']);
      again!.playShot(s2!);
      expect(again.stateHash(), gmInt(opp.state['hash']));
      // the shooter itself never replays its own echo
      final GmView mine = GmView(_hostView('carrom', turn: m.turn, mySeat: 0, state: <String, dynamic>{..._wire(st), 'shots': 1}));
      expect(CarromOnlineSync.shouldReplay(mine, 0), isFalse);
    });

    test('a server timeout passes the turn on the derived board', () {
      final CrMatch m = CrMatch.newBoard();
      final GmView v = GmView(_hostView('carrom', turn: 1, state: <String, dynamic>{
        'board': _wire(<String, dynamic>{'b': m.toJson()})['b'],
        'shots': 3,
        'foul': <String, dynamic>{'seat': 0, 'reason': 'timeout'},
      }));
      final CrMatch d = CarromOnlineSync.derive(v);
      expect(d.turn, 1);
      expect(d.turnNumber, 1);
    });

    test('finish payloads', () {
      final CrMatch m = CrMatch.newBoard();
      expect(CarromOnlineSync.finishOf(m), isNull);
      m.phase = CrPhase.finished;
      m.winner = 1;
      expect(CarromOnlineSync.finishOf(m)!['winners'], <int>[1]);
      m.winner = -1;
      m.turnNumber = CrConfig.maxTurns;
      final Map<String, dynamic> f = CarromOnlineSync.finishOf(m)!;
      expect(f['winners'], <int>[]);
      expect(f['reason'], 'draw');
    });

    test('shooter submits via gm_shot and the opponent replays to the same board', () async {
      final ShotBackend be = ShotBackend(_hostView('carrom', turn: 0, mySeat: 0));
      final GmMatchController gm = GmMatchController(matchId: 'm1', backend: be, uid: 'u0', autoStart: false, isFa: false);
      gm.accept(be.current);
      final CarromOnlineController cc = CarromOnlineController(_launch(), gm);
      gm.views.listen(cc.onView);
      cc.onView(gm.view!);
      expect(cc.canShoot, isTrue);
      cc.startShot(const CrShot(placeX: 512, dirX: 0.02, dirY: -1, power: 0.95));
      expect(cc.match.phase, CrPhase.simulating);
      for (int i = 0; i < 400 && cc.match.phase == CrPhase.simulating; i++) {
        cc.tick(0.05);
      }
      expect(cc.match.phase, isNot(CrPhase.simulating));
      await _flush();
      expect(be.shots.length, 1);
      expect(be.turns.single, cc.match.turn);
      expect(gm.view!.version, 4);
      final int hash = gmInt(be.shots.single['hash']);
      expect(cc.match.stateHash(), hash);

      // opponent device: sees the board before, then the new view → replays the shot
      final Map<String, dynamic> before = _hostView('carrom', turn: 0, mySeat: 1);
      final ShotBackend be2 = ShotBackend(before);
      final GmMatchController gm2 = GmMatchController(matchId: 'm1', backend: be2, uid: 'u1', autoStart: false, isFa: false);
      gm2.accept(before);
      final CarromOnlineController opp = CarromOnlineController(_launch(), gm2);
      opp.onView(gm2.view!);
      expect(opp.canShoot, isFalse);
      gm2.accept(<String, dynamic>{...be.current, 'my_seat': 1});
      opp.onView(gm2.view!);
      expect(opp.replaying, isTrue);
      for (int i = 0; i < 400 && opp.replaying; i++) {
        opp.tick(0.05);
      }
      expect(opp.replaying, isFalse);
      expect(opp.match.stateHash(), hash);
      expect(opp.appliedVersion, 4);
      cc.dispose();
      opp.dispose();
      gm.dispose();
      gm2.dispose();
    });
  });

  group('billiards online sync', () {
    test('table json round trip keeps hash, groups and flags', () {
      final PoolMatch m = PoolMatch.newRack(breaker: 1);
      m.playShot(const PoolShot(dirX: 0.01, dirY: -1, power: 0.95));
      final PoolMatch? back = billiardsMatchFromJson(_wire(<String, dynamic>{'b': billiardsMatchToJson(m)})['b']);
      expect(back, isNotNull);
      expect(back!.stateHash, m.stateHash);
      expect(back.current, m.current);
      expect(back.groups, m.groups);
      expect(back.isBreak, m.isBreak);
      expect(back.ballInHand, m.ballInHand);
      expect(back.shotCount, m.shotCount);
    });

    test('replay of the submitted shot is deterministic', () {
      final PoolMatch m = PoolMatch.newRack(breaker: 0);
      final PoolMatch prev = m.clone();
      const PoolShot shot = PoolShot(dirX: -0.02, dirY: -1, power: 0.9, spin: 0.2, side: -0.1);
      m.playShot(shot);
      final Map<String, dynamic> st = BilliardsOnlineSync.encode(prev: prev, shot: shot, after: m, shooter: 0, seed: 1);
      expect(jsonEncode(st).length, lessThan(20000));
      final GmView opp = GmView(_hostView('billiards', turn: m.current, mySeat: 1, state: <String, dynamic>{..._wire(st), 'shots': 1}));
      expect(BilliardsOnlineSync.shouldReplay(opp, 0), isTrue);
      final PoolMatch? r = BilliardsOnlineSync.replay(opp);
      expect(r!.stateHash, gmInt(opp.state['hash']));
      expect(BilliardsOnlineSync.derive(opp).stateHash, m.stateHash);
    });

    test('fresh match: seat on turn breaks; timeout gives ball in hand', () {
      final PoolMatch d = BilliardsOnlineSync.derive(GmView(_hostView('billiards', turn: 1)));
      expect(d.current, 1);
      expect(d.isBreak, isTrue);
      final PoolMatch m = PoolMatch.newRack(breaker: 0);
      m.playShot(const PoolShot(dirX: 0, dirY: -1, power: 0.9));
      m.ballInHand = false;
      final int other = 1 - m.current;
      final GmView v = GmView(_hostView('billiards', turn: other, state: <String, dynamic>{
        'board': _wire(<String, dynamic>{'b': billiardsMatchToJson(m)})['b'],
        'shots': 1,
      }));
      final PoolMatch t = BilliardsOnlineSync.derive(v);
      expect(t.current, other);
      expect(t.ballInHand, isTrue);
    });

    test('finish payload names the winner', () {
      final PoolMatch m = PoolMatch.newRack();
      expect(BilliardsOnlineSync.finishOf(m), isNull);
      m.phase = PoolPhase.over;
      m.winner = 1;
      m.endReason = PoolEndReason.eightEarly;
      expect(BilliardsOnlineSync.finishOf(m), <String, dynamic>{'winners': <int>[1], 'reason': 'eight_early'});
    });
  });

  group('online boards render', () {
    Future<void> pumpBoard(WidgetTester tester, Map<String, dynamic> view, Widget Function(GmMatchController c) b) async {
      final FakeBackend be = FakeBackend(view);
      final GmMatchController c = GmMatchController(matchId: 'm1', backend: be, uid: 'u0', autoStart: false, isFa: false);
      c.accept(view);
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 2.6;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: b(c))));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }

    tearDown(() {
      final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.instance;
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    testWidgets('carrom board (my turn and spectating)', (WidgetTester tester) async {
      await pumpBoard(tester, _hostView('carrom'), buildCarromOnline);
      await pumpBoard(tester, _hostView('carrom', mySeat: null), (GmMatchController c) => CarromOnlineBoard(c: c));
    });

    testWidgets('billiards board (my turn and opponent turn)', (WidgetTester tester) async {
      await pumpBoard(tester, _hostView('billiards'), buildBilliardsOnline);
      await pumpBoard(tester, _hostView('billiards', turn: 1), (GmMatchController c) => BilliardsOnlineBoard(c: c));
    });
  });
}
