import 'dart:math' as math;

import 'body.dart';
import 'config.dart';
import 'physics.dart';

enum FsPhase { aiming, simulating, finished }

class FsShot {
  const FsShot({required this.bodyId, required this.dirX, required this.dirY, required this.power});
  final int bodyId;
  final double dirX;
  final double dirY;

  /// 0 < power <= 1
  final double power;

  Map<String, dynamic> toJson() => {'bodyId': bodyId, 'dirX': dirX, 'dirY': dirY, 'power': power};

  factory FsShot.fromJson(Map<String, dynamic> j) => FsShot(
        bodyId: (j['bodyId'] as num).toInt(),
        dirX: (j['dirX'] as num).toDouble(),
        dirY: (j['dirY'] as num).toDouble(),
        power: (j['power'] as num).toDouble(),
      );
}

class FsTurnOutcome {
  const FsTurnOutcome({required this.scorer, required this.steps, required this.matchOver});

  /// Team that scored (0/1) or -1.
  final int scorer;
  final int steps;
  final bool matchOver;
}

/// Authoritative match state + rules. Pure Dart: no Flame/Flutter imports, so it can run
/// on the client, in tests and (via the TS mirror) on the server.
class FsMatch {
  FsMatch._({
    required this.bodies,
    required this.score,
    required this.turnTeam,
    required this.turnNumber,
    required this.phase,
    required this.winner,
  });

  factory FsMatch.kickoff({int firstTeam = 0}) => FsMatch._(
        bodies: fsKickoffBodies(),
        score: [0, 0],
        turnTeam: firstTeam,
        turnNumber: 0,
        phase: FsPhase.aiming,
        winner: null,
      );

  List<FsBody> bodies;
  List<int> score;
  int turnTeam;
  int turnNumber;
  FsPhase phase;

  /// null = running, 0/1 = winner, -1 = draw.
  int? winner;

  FsBody get ball => bodies[bodies.length - 1];

  FsMatch clone() => FsMatch._(
        bodies: bodies.map((b) => b.clone()).toList(),
        score: List<int>.from(score),
        turnTeam: turnTeam,
        turnNumber: turnNumber,
        phase: phase,
        winner: winner,
      );

  /// Returns an error code or null when the shot is legal.
  String? validate(FsShot s) {
    if (phase != FsPhase.aiming) return 'not_aiming';
    if (s.bodyId < 0 || s.bodyId >= bodies.length - 1) return 'bad_body';
    if (bodies[s.bodyId].team != turnTeam) return 'not_your_disc';
    if (!s.dirX.isFinite || !s.dirY.isFinite || !s.power.isFinite) return 'not_finite';
    if (s.dirX * s.dirX + s.dirY * s.dirY < 1e-12) return 'zero_dir';
    if (s.power <= 0 || s.power > 1) return 'bad_power';
    return null;
  }

  /// Applies the impulse and enters the simulating phase (live mode).
  void beginShot(FsShot s) {
    final len = math.sqrt(s.dirX * s.dirX + s.dirY * s.dirY);
    final b = bodies[s.bodyId];
    b.vx = s.dirX / len * s.power * FsConfig.maxShotSpeed;
    b.vy = s.dirY / len * s.power * FsConfig.maxShotSpeed;
    phase = FsPhase.simulating;
  }

  /// Call when the live simulator is done.
  FsTurnOutcome finishShot(int scorer, int steps) {
    var over = false;
    if (scorer >= 0) {
      score[scorer] += 1;
      if (score[scorer] >= FsConfig.goalsToWin) {
        over = true;
        winner = scorer;
        fsSnap(bodies);
      } else {
        bodies = fsKickoffBodies();
        turnTeam = 1 - scorer; // conceding team kicks off
      }
    } else {
      fsSnap(bodies);
      turnTeam = 1 - turnTeam;
    }
    turnNumber += 1;
    if (!over && turnNumber >= FsConfig.maxTurns) {
      over = true;
      winner = score[0] == score[1] ? -1 : (score[0] > score[1] ? 0 : 1);
    }
    phase = over ? FsPhase.finished : FsPhase.aiming;
    return FsTurnOutcome(scorer: scorer, steps: steps, matchOver: over);
  }

  /// Headless shot (server, tests, bot search). Throws StateError on illegal shots.
  FsTurnOutcome playShot(FsShot s) {
    final err = validate(s);
    if (err != null) throw StateError(err);
    beginShot(s);
    final sim = FsSimulator(bodies)..runToEnd();
    return finishShot(sim.scorer, sim.steps);
  }

  /// Turn timer expired.
  void passTurn() {
    if (phase != FsPhase.aiming) return;
    turnTeam = 1 - turnTeam;
    turnNumber += 1;
    if (turnNumber >= FsConfig.maxTurns) {
      phase = FsPhase.finished;
      winner = score[0] == score[1] ? -1 : (score[0] > score[1] ? 0 : 1);
    }
  }

  int stateHash() => fsStateHash(bodies);

  Map<String, dynamic> toJson() => {
        'bodies': bodies.map((b) => b.toJson()).toList(),
        'score': score,
        'turnTeam': turnTeam,
        'turnNumber': turnNumber,
        'phase': phase.index,
        'winner': winner,
      };

  factory FsMatch.fromJson(Map<String, dynamic> j) {
    final list = (j['bodies'] as List).cast<Map<String, dynamic>>();
    final bs = list.map((m) {
      final isBall = FsKind.values[(m['kind'] as num).toInt()] == FsKind.ball;
      return FsBody.fromJson(m, r: isBall ? FsConfig.ballR : FsConfig.discR, m: isBall ? FsConfig.ballMass : FsConfig.discMass);
    }).toList();
    return FsMatch._(
      bodies: bs,
      score: (j['score'] as List).map((e) => (e as num).toInt()).toList(),
      turnTeam: (j['turnTeam'] as num).toInt(),
      turnNumber: (j['turnNumber'] as num).toInt(),
      phase: FsPhase.values[(j['phase'] as num).toInt()],
      winner: j['winner'] == null ? null : (j['winner'] as num).toInt(),
    );
  }
}
