// Pure-part tests for the online port: wire codec vs the Godot format, client interpolation,
// shot seq handling / controller rotation (OnlineMatchNet) and RoomLink dedupe rules.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/disc_football/core/engine.dart';
import 'package:nexora/games/disc_football/core/net_codec.dart';
import 'package:nexora/games/disc_football/online/online_match_net.dart';

class FakeLink implements MatchLink {
  FakeLink(this.me, this.players, {this.host = 'host'});
  @override
  final String me;
  @override
  List<NetPlayer> players;
  String host;
  bool up = true;
  final Set<String> online = <String>{'host', 'guest', 'g2'};
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  @override
  bool get connected => up;
  @override
  bool isOnline(String uid) => online.contains(uid);
  @override
  int get onlineCount => online.length;
  @override
  String get currentHost => host;
  @override
  bool send(Map<String, dynamic> m) {
    sent.add(Map<String, dynamic>.of(m));
    return true;
  }

  @override
  void ping() {}
  @override
  void refresh() {}
}

class FakeBackend implements MatchBackend {
  int reports = 0;
  @override
  Future<NetRes> reportMatch(String matchId, int scoreA, int scoreB, int duration) async {
    reports++;
    return const NetRes(true, data: <String, dynamic>{'rating_delta': 12});
  }

  @override
  Future<NetRes> hostQuit(String matchId, List<int> score) async => const NetRes(true);
  @override
  Future<NetRes> claimHostLost(String matchId, List<int> score) async => const NetRes(false, raw: 'host still online');
  @override
  Future<Map<String, dynamic>?> fetchMatch(String matchId) async => null;
}

List<NetPlayer> players1v1() => const <NetPlayer>[
      NetPlayer(userId: 'host', role: 'player', team: 0, slot: 0, disc: 'club0', name: 'H'),
      NetPlayer(userId: 'guest', role: 'player', team: 1, slot: 0, disc: 'club1', name: 'G'),
    ];

OnlineMatchNet mk(String me, FakeLink l, double Function() clock) => OnlineMatchNet(
      link: l,
      backend: FakeBackend(),
      matchId: 'm1',
      roomSettings: const <String, dynamic>{'goals': 3, 'time': 0, 'turn': 15, 'field': 0},
      roomHost: 'host',
      ranked: true,
      statsOf: (String d) => const DiscStats(power: 5, accuracy: 5),
      clock: clock,
      wait: (Duration d) async {},
    );

void main() {
  group('codec (Godot online_match.gd format)', () {
    test('enc_ev / dec_ev round trip', () {
      final List<EngineEvent> evs = <EngineEvent>[
        const EngineEvent.hit(ball: true, power: .42),
        const EngineEvent.wall(.3),
        const EngineEvent.post(.91),
        const EngineEvent.goal(1, false),
        const EngineEvent.goal(0, true),
        const EngineEvent.turn(1),
        const EngineEvent.shot(0),
        const EngineEvent.end(<int>[3, 2]),
        const EngineEvent.clock(),
      ];
      final List<List<int>> enc = evs.map(encEv).toList();
      expect(enc[0], <int>[0, 1, 42]);
      expect(enc[3], <int>[3, 1, 0]);
      expect(enc[4], <int>[3, 0, 1]);
      expect(enc[7], <int>[6, 3, 2]);
      expect(enc[8], <int>[7]);
      for (int i = 0; i < evs.length; i++) {
        final EngineEvent d = decEv(enc[i]);
        expect(d.t, evs[i].t);
        expect(d.team, evs[i].team);
        expect(d.nogoal, evs[i].nogoal);
      }
      // Godot JSON numbers may arrive as floats
      final EngineEvent g = decEv(<dynamic>[3.0, 1.0, 0.0]);
      expect(g.t, 'goal');
      expect(g.team, 1);
    });

    test('snapshot JSON round trip + Godot literal', () {
      final OnlineMatchNet n = mk('host', FakeLink('host', players1v1()), () => 100);
      final Snap s = Snap.capture(n.eng, q: 7, ts: 123456, hz: 30, ctrl: 'host', seq: 3, evs: <List<int>>[<int>[4, 0]]);
      final Map<String, dynamic> wire = jsonDecode(jsonEncode(<String, dynamic>{'k': 's', 's': s.toJson()})) as Map<String, dynamic>;
      final Snap? back = Snap.fromJson(wire['s']);
      expect(back, isNotNull);
      expect(back!.q, 7);
      expect(back.p.length, n.eng.bodies.length * 3);
      expect(back.R.length, 9);
      expect(back.c, 'host');
      expect(back.ph, Phase.aim);
      // what a Godot host sends (JSON.stringify of the snapshot dictionary)
      const String godot =
          '{"q":5,"ts":1731590000000.0,"hz":30,"ph":"move","tu":1,"sc":[1,0],"ml":0.0,"tl":12.3,"su":0,"c":null,"n":4,"p":[1000,2000,314],"R":[1000,0,0,0,1000,0,0,0,1000],"ev":[[5,1]]}';
      final Snap? gs = Snap.fromJson(jsonDecode(godot));
      expect(gs!.q, 5);
      expect(gs.ph, Phase.move);
      expect(gs.tu, 1);
      expect(gs.c, isNull);
      expect(gs.tl, closeTo(12.3, 1e-9));
      expect(gs.ev.first, <dynamic>[5, 1]);
    });
  });

  group('OnlineMatchNet host', () {
    test('first tick: turn 1 → seq 1, controller = host, snapshot sent with mid', () {
      double t = 100;
      final FakeLink l = FakeLink('host', players1v1());
      final OnlineMatchNet n = mk('host', l, () => t);
      n.tick(1 / 60);
      expect(n.seq, 1);
      expect(n.hostCtrl, 'host');
      final Map<String, dynamic> snap = l.sent.firstWhere((Map<String, dynamic> m) => m['k'] == 's');
      expect(snap['mid'], 'm1');
      expect((snap['s'] as Map<String, dynamic>)['c'], 'host');
      t += .01;
    });

    test('remote shot: wrong sender / wrong seq ignored, right one fires', () {
      final FakeLink l = FakeLink('host', players1v1());
      final OnlineMatchNet n = mk('host', l, () => 100);
      n.tick(1 / 60);
      // force guest's turn
      n.eng.turn = 1;
      n.turnCount[1] = 1;
      n.tick(1 / 60);
      expect(n.hostCtrl, 'guest');
      final Body b = n.eng.bodies.firstWhere((Body x) => x.team == 1);
      n.onMsg(<String, dynamic>{'k': 'shot', 'b': b.id, 'dx': 0, 'dy': -120, 'n': n.seq + 1, 'mid': 'm1'}, 'guest');
      expect(n.eng.phase, Phase.aim);
      n.onMsg(<String, dynamic>{'k': 'shot', 'b': b.id, 'dx': 0, 'dy': -120, 'n': n.seq, 'mid': 'm1'}, 'intruder');
      expect(n.eng.phase, Phase.aim);
      n.onMsg(<String, dynamic>{'k': 'shot', 'b': b.id, 'dx': 0, 'dy': -120, 'n': n.seq, 'mid': 'other-match'}, 'guest');
      expect(n.eng.phase, Phase.aim);
      n.onMsg(<String, dynamic>{'k': 'shot', 'b': b.id, 'dx': 0, 'dy': -120, 'n': n.seq, 'mid': 'm1'}, 'guest');
      expect(n.eng.phase, Phase.move);
    });

    test('controller rotation skips offline humans; empty team → bot', () {
      final FakeLink l = FakeLink('host', <NetPlayer>[
        const NetPlayer(userId: 'host', role: 'player', team: 0, slot: 0),
        const NetPlayer(userId: 'guest', role: 'player', team: 1, slot: 0),
        const NetPlayer(userId: 'g2', role: 'player', team: 1, slot: 1),
      ]);
      final OnlineMatchNet n = mk('host', l, () => 100);
      n.turnCount[1] = 1;
      expect(n.ctrlFor(1), 'guest');
      n.turnCount[1] = 2;
      expect(n.ctrlFor(1), 'g2');
      l.online.remove('g2');
      expect(n.ctrlFor(1), 'guest');
      l.online.remove('guest');
      expect(n.ctrlFor(1), '');
    });
  });

  group('OnlineMatchNet client', () {
    test('interpolates between buffered snapshots in the past', () {
      double t = 1000;
      final FakeLink hl = FakeLink('host', players1v1());
      final OnlineMatchNet host = mk('host', hl, () => t);
      final FakeLink gl = FakeLink('guest', players1v1());
      final OnlineMatchNet g = mk('guest', gl, () => t);
      expect(g.isHost, isFalse);
      // two snapshots 100 ms apart, ball moved by +100 world units in x
      final Snap a = Snap.capture(host.eng, q: 1, ts: (t * 1000).round(), hz: 10, ctrl: 'host', seq: 1, evs: <List<int>>[]);
      final Map<String, dynamic> sa = a.toJson();
      final Map<String, dynamic> sb = Map<String, dynamic>.of(sa);
      final List<int> p = List<int>.of(sa['p'] as List<int>);
      final int bi = host.eng.bodies.indexOf(host.eng.ball);
      final double x0 = p[bi * 3] / 10.0;
      p[bi * 3] += 1000;
      sb['p'] = p;
      sb['q'] = 2;
      sb['ts'] = (t * 1000).round() + 100;
      g.onMsg(<String, dynamic>{'k': 's', 's': sa, 'mid': 'm1'}, 'host');
      t += .1; // b arrives 100 ms later (same clock offset)
      g.onMsg(<String, dynamic>{'k': 's', 's': sb, 'mid': 'm1'}, 'host');
      // duplicate and foreign-sender snapshots are ignored
      g.onMsg(<String, dynamic>{'k': 's', 's': sb, 'mid': 'm1'}, 'host');
      g.onMsg(<String, dynamic>{'k': 's', 's': <String, dynamic>{...sb, 'q': 9}, 'mid': 'm1'}, 'guest-not-host');
      expect(g.buf.length, 2);
      // render time = now - offset - 1700/hz = ts_a + 50 ms → halfway between a and b
      t += .12;
      g.tick(1 / 60);
      expect(g.got, isTrue);
      expect(g.eng.ball.x, closeTo(x0 + 50, 1.0));
    });

    test('shot request carries the snapshot seq and is resent until acknowledged', () {
      double t = 1000;
      final FakeLink hl = FakeLink('host', players1v1());
      final OnlineMatchNet host = mk('host', hl, () => t);
      host.eng.turn = 1;
      final FakeLink gl = FakeLink('guest', players1v1());
      final OnlineMatchNet g = mk('guest', gl, () => t);
      final Snap a = Snap.capture(host.eng, q: 1, ts: (t * 1000).round(), hz: 30, ctrl: 'guest', seq: 5, evs: <List<int>>[]);
      g.onMsg(<String, dynamic>{'k': 's', 's': a.toJson(), 'mid': 'm1'}, 'host');
      t += .1;
      g.tick(1 / 60);
      expect(g.clientCtrl, 'guest');
      expect(g.clientSeq, 5);
      expect(g.canAct(), isTrue);
      final Body b = g.eng.bodies.firstWhere((Body x) => x.team == 1);
      expect(g.grant(b.x, b.y), isTrue);
      g.move(b.x, b.y + 150);
      g.release();
      final List<Map<String, dynamic>> shots = gl.sent.where((Map<String, dynamic> m) => m['k'] == 'shot').toList();
      expect(shots.length, 1);
      expect(shots.first['n'], 5);
      expect(shots.first['mid'], 'm1');
      expect(shots.first['dy'], closeTo(-150, .1));
      t += .5;
      g.tick(1 / 60);
      expect(gl.sent.where((Map<String, dynamic> m) => m['k'] == 'shot').length, 2);
    });

    test('abort from the host ends the match for guests', () {
      final FakeLink gl = FakeLink('guest', players1v1());
      final OnlineMatchNet g = mk('guest', gl, () => 10);
      String why = '';
      g.onExit = (String w) => why = w;
      g.onMsg(<String, dynamic>{'k': 'abort', 'mid': 'm1'}, 'guest-x');
      expect(why, '');
      g.onMsg(<String, dynamic>{'k': 'abort', 'mid': 'm1'}, 'host');
      expect(why, 'aborted');
      expect(g.done, NetDone.aborted);
    });

    test('outcome rating delta is signed for my team, 0 when unranked', () {
      final OnlineMatchNet g = mk('guest', FakeLink('guest', players1v1()), () => 10);
      final NetOutcome o = g.outcome(<int>[1, 3], 12, true);
      expect(o.winner, 1);
      expect(o.myTeam, 1);
      expect(o.ratingDelta, -12);
    });
  });
}
