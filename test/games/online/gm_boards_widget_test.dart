import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/backgammon/online/backgammon_online.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';
import 'package:nexora/games/ludo/online/ludo_online.dart';
import 'package:nexora/games/mafia/online/mafia_online.dart';
import 'package:nexora/games/quiz/online/quiz_online.dart';
import 'package:nexora/games/snakes_ladders/online/snl_online.dart';
import 'package:nexora/games/uno/online/uno_online.dart';

import 'fake_gm_backend.dart';

Map<String, dynamic> _view(String game, String phase, Map<String, dynamic> state,
    {int seats = 2, int turn = 0, int? mySeat = 0, Map<String, dynamic>? private, String status = 'live'}) {
  final DateTime now = DateTime.now().toUtc();
  return <String, dynamic>{
    'match_id': 'm1',
    'room_id': 'r1',
    'game': game,
    'seats': <String>[for (int i = 0; i < seats; i++) 'u$i'],
    'names': <String>[for (int i = 0; i < seats; i++) 'P$i'],
    'status': status,
    'phase': phase,
    'turn': turn,
    'version': 5,
    'state': <String, dynamic>{
      'out': List<bool>.filled(seats, false),
      'strikes': List<int>.filled(seats, 0),
      'scores': List<int>.filled(seats, 0),
      ...state,
    },
    'deadline': now.add(const Duration(seconds: 20)).toIso8601String(),
    'now': now.toIso8601String(),
    'result': null,
    'authority': 'server',
    'ranked': true,
    'my_seat': mySeat,
    'private': private ?? <String, dynamic>{},
  };
}

Future<(GmMatchController, FakeBackend)> _pump(WidgetTester tester, Map<String, dynamic> view, Widget Function(GmMatchController c) board) async {
  final FakeBackend b = FakeBackend(view);
  final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', autoStart: false, isFa: false);
  c.accept(view);
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 2.6;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AnimatedBuilder(animation: c, builder: (BuildContext context, Widget? _) => board(c))),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return (c, b);
}

void main() {
  tearDown(() {
    final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('backgammon: roll button sends a roll', (WidgetTester tester) async {
    final List<int> b = List<int>.filled(28, 0);
    b[23] = 2;
    b[12] = 5;
    b[7] = 3;
    b[5] = 5;
    b[0] = -2;
    b[11] = -5;
    b[16] = -3;
    b[18] = -5;
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester, _view('backgammon', 'roll', <String, dynamic>{'b': b, 'dice': <int>[], 'last': null}), (GmMatchController c) => BackgammonOnlineBoard(c: c));
    await tester.tap(find.text('Roll'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.single['a'], 'roll');
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('backgammon: move phase shows undo / confirm', (WidgetTester tester) async {
    final List<int> b = List<int>.filled(28, 0);
    b[5] = 15;
    b[18] = -15;
    final (GmMatchController c, FakeBackend _) = await _pump(
        tester, _view('backgammon', 'move', <String, dynamic>{'b': b, 'dice': <int>[3, 1]}), (GmMatchController c) => BackgammonOnlineBoard(c: c));
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    c.dispose();
  });

  testWidgets('ludo renders and rolls', (WidgetTester tester) async {
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester,
        _view('ludo', 'roll', <String, dynamic>{
          'n': 3,
          'corners': <int>[3, 0, 1],
          'tk': <List<int>>[<int>[-1, -1, 4, 56], <int>[-1, -1, -1, -1], <int>[10, -1, -1, -1]],
          'six': 0,
          'legal': <int>[],
        }, seats: 3),
        (GmMatchController c) => LudoOnlineBoard(c: c));
    await tester.tap(find.byIcon(Icons.casino_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.single['a'], 'roll');
    c.dispose();
  });

  testWidgets('snakes & ladders renders', (WidgetTester tester) async {
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester,
        _view('snakes_ladders', 'roll', <String, dynamic>{
          'pos': <int>[12, 38],
          'last': <String, dynamic>{'seat': 1, 'roll': 1, 'from': 0, 'steps': <int>[1], 'landed': 1, 'final': 38, 'extra': false},
        }),
        (GmMatchController c) => SnlOnlineBoard(c: c));
    expect(find.textContaining('climbed'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.casino_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.single['a'], 'roll');
    c.dispose();
  });

  testWidgets('uno: legal card plays, wild asks for a colour', (WidgetTester tester) async {
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester,
        _view('uno', 'play', <String, dynamic>{
          'top': 9,
          'color': 0,
          'dir': 1,
          'counts': <int>[3, 4, 5],
          'pile': 70,
          'drawn': false,
          'nx': <bool>[false, false, false],
          'vul': null,
        }, seats: 3, private: <String, dynamic>{'hand': <int>[34, 60, 100], 'drawn': null}),
        (GmMatchController c) => UnoOnlineBoard(c: c));
    expect(find.text('Draw'), findsOneWidget);
    await tester.tap(find.text('Draw'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.last['a'], 'draw');
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  testWidgets('quiz: answering sends the choice', (WidgetTester tester) async {
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester,
        _view('quiz', 'question', <String, dynamic>{
          'round': 0,
          'total': 10,
          'qid': 'space_001',
          'answered': <bool>[false, false],
          'correct': <int>[0, 0],
        }),
        (GmMatchController c) => QuizOnlineBoard(c: c));
    expect(find.text('Which planet is closest to the Sun?'), findsOneWidget);
    await tester.tap(find.text('Mercury'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.single, <String, dynamic>{'a': 'answer', 'c': 3});
    c.dispose();
  });

  testWidgets('mafia: night target and role chip', (WidgetTester tester) async {
    final (GmMatchController c, FakeBackend fake) = await _pump(
        tester,
        _view('mafia', 'night', <String, dynamic>{
          'day': 1,
          'alive': List<bool>.filled(6, true),
          'shown': List<String?>.filled(6, null),
          'defendants': <int>[],
          'voted': List<bool>.filled(6, false),
          'ready': List<bool>.filled(6, false),
          'ev': <Map<String, dynamic>>[<String, dynamic>{'k': 'night', 'd': 1}],
        }, seats: 6, private: <String, dynamic>{
          'role': 'godfather',
          'mates': <Map<String, dynamic>>[<String, dynamic>{'seat': 0, 'role': 'godfather'}, <String, dynamic>{'seat': 3, 'role': 'mafia'}],
          'checks': <String, dynamic>{},
          'team_pick': <String, dynamic>{},
        }),
        (GmMatchController c) => MafiaOnlineBoard(c: c));
    expect(find.text('Night 1'), findsOneWidget);
    await tester.tap(find.text('P2').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.moves.single, <String, dynamic>{'a': 'night', 't': 2});
    c.dispose();
  });

  testWidgets('result overlay shows the winner', (WidgetTester tester) async {
    final Map<String, dynamic> v = _view('uno', 'play', <String, dynamic>{}, status: 'finished');
    v['result'] = <String, dynamic>{'winners': <int>[0], 'scores': <int>[40, 0], 'reason': 'win', 'rating_delta': <int>[16, -16]};
    final FakeBackend b = FakeBackend(v);
    final GmMatchController c = GmMatchController(matchId: 'm1', backend: b, uid: 'u0', autoStart: false);
    c.accept(v);
    bool back = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GmResultOverlay(v: c.view!, onBack: () => back = true))));
    expect(find.text('You won!'), findsOneWidget);
    expect(find.textContaining('+16'), findsOneWidget);
    await tester.tap(find.text('Back to the room'));
    expect(back, isTrue);
    c.dispose();
  });
}
