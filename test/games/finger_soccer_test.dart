import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bot.dart';
import 'package:nexora/games/finger_soccer/core/config.dart';
import 'package:nexora/games/finger_soccer/core/fs_match.dart';
import 'package:nexora/games/finger_soccer/core/physics.dart';

void main() {
  test('golden vector matches TypeScript reference (server parity)', () {
    final m = FsMatch.kickoff();
    final o1 = m.playShot(const FsShot(bodyId: 2, dirX: 0.05, dirY: -1, power: 0.8));
    expect(o1.scorer, -1);
    expect(o1.steps, 498);
    expect(m.stateHash(), 1526070575);
    expect(m.bodies[2].x, closeTo(455.659, 1e-9));
    expect(m.bodies[2].y, closeTo(276.911, 1e-9));
    expect(m.ball.x, closeTo(616.52, 1e-9));
    expect(m.ball.y, closeTo(368.623, 1e-9));
    expect(m.turnTeam, 1);

    final o2 = m.playShot(const FsShot(bodyId: 7, dirX: 0.1, dirY: 1, power: 0.7));
    expect(o2.steps, 457);
    expect(m.stateHash(), 92252167);
  });

  test('simulation is deterministic', () {
    String run() {
      final m = FsMatch.kickoff();
      m.playShot(const FsShot(bodyId: 0, dirX: 0.3, dirY: -1, power: 1));
      return m.stateHash().toString();
    }

    expect(run(), run());
  });

  test('goal is detected and kickoff goes to the conceding team', () {
    final m = FsMatch.kickoff();
    m.ball
      ..x = 340
      ..y = 140;
    m.bodies[2]
      ..x = 340
      ..y = 260;
    final out = m.playShot(const FsShot(bodyId: 2, dirX: 0, dirY: -1, power: 0.9));
    expect(out.scorer, 0);
    expect(m.score, [1, 0]);
    expect(m.turnTeam, 1);
    expect(m.ball.x, FsConfig.fieldW / 2);
  });

  test('illegal shots are rejected', () {
    final m = FsMatch.kickoff();
    expect(m.validate(const FsShot(bodyId: 7, dirX: 0, dirY: 1, power: 0.5)), 'not_your_disc');
    expect(m.validate(const FsShot(bodyId: 0, dirX: 0, dirY: 0, power: 0.5)), 'zero_dir');
    expect(m.validate(const FsShot(bodyId: 0, dirX: 0, dirY: 1, power: 1.5)), 'bad_power');
    expect(m.validate(const FsShot(bodyId: 10, dirX: 0, dirY: 1, power: 0.5)), 'bad_body');
  });

  test('simulation always terminates within max steps', () {
    final m = FsMatch.kickoff();
    m.bodies[3].vx = 2300;
    m.bodies[3].vy = -1500;
    final sim = FsSimulator(m.bodies)..runToEnd();
    expect(sim.steps <= FsConfig.maxSteps, isTrue);
    expect(fsIsSettled(m.bodies) || sim.scorer >= 0 || sim.steps == FsConfig.maxSteps, isTrue);
  });

  test('bot returns a legal shot', () {
    final m = FsMatch.kickoff(firstTeam: 1);
    final shot = FsBot(team: 1, level: FsBotLevel.easy).choose(m);
    expect(m.validate(shot), isNull);
  });

  test('match json round trip keeps the hash', () {
    final m = FsMatch.kickoff();
    m.playShot(const FsShot(bodyId: 1, dirX: -0.2, dirY: -1, power: 0.6));
    final copy = FsMatch.fromJson(m.toJson());
    expect(copy.stateHash(), m.stateHash());
    expect(copy.turnTeam, m.turnTeam);
  });

  test('impact sink never changes the simulation (render-only)', () {
    final a = FsMatch.kickoff();
    final b = FsMatch.kickoff();
    const shot = FsShot(bodyId: 2, dirX: 0.05, dirY: -1, power: 0.8);
    a.beginShot(shot);
    b.beginShot(shot);
    final sink = <FsImpact>[];
    final sa = FsSimulator(a.bodies)..runToEnd();
    final sb = FsSimulator(b.bodies, impactSink: sink)..runToEnd();
    expect(sa.steps, sb.steps);
    expect(fsStateHash(a.bodies), fsStateHash(b.bodies));
    expect(sink.isNotEmpty, isTrue);
  });

  test('incremental bot search returns a legal shot for every level', () {
    for (final level in FsBotLevel.values) {
      final m = FsMatch.kickoff(firstTeam: 1);
      final search = FsBotSearch(FsBot(team: 1, level: level), m);
      var guard = 0;
      while (!search.step(4)) {
        guard++;
        expect(guard < 100, isTrue);
      }
      expect(m.validate(search.best), isNull);
      // the search ran on a clone: the real match is untouched
      expect(m.turnNumber, 0);
    }
  });

  test('timer pass and 40-turn limit finish the match with a draw at 0-0', () {
    final m = FsMatch.kickoff();
    for (var i = 0; i < FsConfig.maxTurns; i++) {
      m.passTurn();
    }
    expect(m.phase, FsPhase.finished);
    expect(m.winner, -1);
  });

  test('first to five goals wins', () {
    final m = FsMatch.kickoff();
    m.score[0] = 4;
    m.ball
      ..x = 340
      ..y = 140;
    m.bodies[2]
      ..x = 340
      ..y = 260;
    final out = m.playShot(const FsShot(bodyId: 2, dirX: 0, dirY: -1, power: 0.9));
    expect(out.scorer, 0);
    expect(out.matchOver, isTrue);
    expect(m.winner, 0);
    expect(m.phase, FsPhase.finished);
  });
}
