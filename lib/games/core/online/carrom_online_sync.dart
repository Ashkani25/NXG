/// Online Carrom: wire format + pure sync rules (no Flutter imports).
///
/// Carrom is host-authoritative on the server (`gm_shot`, see
/// supabase/migrations/20261112100000_games_online_core.sql §7): the shooter's device runs the
/// deterministic offline engine ([CrMatch] / carrom_physics) and submits the resulting state.
/// The server only checks seat, turn order and version, runs the 45 s clock (idle shooter →
/// strike + turn passes, 3 strikes = out) and ends the match on `p_finish`.
///
/// Wire state (`view.state`, written by the shooter, merged by the server):
///   board  = [CrMatch.toJson] after the shot (the authoritative board)
///   prev   = [CrMatch.toJson] right before the shot (lets the opponent replay it)
///   shot   = [CrShot.toJson]
///   by     = shooter seat
///   hash   = [CrMatch.stateHash] of `board` (replay check)
///   seed   = kept from the server's init
///   scores = coins pocketed per seat (server copies them into the result)
///   shots  = server counter (+1 per accepted shot) — used to detect a new shot to replay
///   foul   = {seat, reason: 'timeout'} written by the server when a shooter idles out
library;

import 'package:nexora/games/carrom/core/carrom_config.dart';
import 'package:nexora/games/carrom/core/carrom_match.dart';

import 'gm_models.dart';

/// Recursively turns decoded JSON (Map<dynamic, dynamic> / List<dynamic>) into String-keyed maps.
Object? carromDeepJson(Object? v) {
  if (v is Map) {
    return <String, dynamic>{for (final MapEntry<dynamic, dynamic> e in v.entries) '${e.key}': carromDeepJson(e.value)};
  }
  if (v is List) return <dynamic>[for (final Object? x in v) carromDeepJson(x)];
  return v;
}

class CarromOnlineSync {
  CarromOnlineSync._();

  /// Parses a board written by [CrMatch.toJson]; null when missing or malformed.
  static CrMatch? boardFrom(Object? raw) {
    if (raw is! Map) return null;
    try {
      final Object? j = carromDeepJson(raw);
      if (j is! Map<String, dynamic>) return null;
      final CrMatch m = CrMatch.fromJson(j);
      if (m.phase == CrPhase.simulating) m.phase = CrPhase.aiming;
      return m;
    } catch (_) {
      return null;
    }
  }

  static CrShot? shotFrom(Object? raw) {
    if (raw is! Map) return null;
    try {
      final Object? j = carromDeepJson(raw);
      if (j is! Map<String, dynamic>) return null;
      return CrShot.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// Number of shots the server accepted so far.
  static int shotsOf(GmView v) => gmInt(v.state['shots']);

  /// Seat of the last shooter, or null.
  static int? shooterOf(GmView v) => gmIntOrNull(v.state['by']);

  /// The board every client shows for [v].
  ///
  /// No board yet = fresh break (seat [GmView.turn] shoots first). When the server moved the
  /// turn on its own (idle timeout) the board's turn lags behind: apply the same rule as the
  /// offline timer ([CrMatch.passTurn]) so both devices agree on the queen and turn count.
  static CrMatch derive(GmView v) {
    final int first = v.turn == 1 ? 1 : 0;
    final CrMatch m = boardFrom(v.state['board']) ?? CrMatch.newBoard(firstTurn: first);
    if (v.live && m.phase == CrPhase.aiming && (v.turn == 0 || v.turn == 1) && m.turn != v.turn) {
      m.passTurn();
    }
    return m;
  }

  /// Coins pocketed per seat (shown as the match score).
  static List<int> scoresOf(CrMatch m) => <int>[m.pocketedCount(0), m.pocketedCount(1)];

  /// State to submit with `gm_shot` after [after] finished the shot [shot] started from [prev].
  static Map<String, dynamic> encode({
    required CrMatch prev,
    required CrShot shot,
    required CrMatch after,
    required int shooter,
    Object? seed,
  }) =>
      <String, dynamic>{
        if (seed != null) 'seed': seed,
        'board': after.toJson(),
        'prev': prev.toJson(),
        'shot': shot.toJson(),
        'by': shooter,
        'hash': after.stateHash(),
        'scores': scoresOf(after),
      };

  /// Seat that shoots next (same seat on a pocket, else the opponent).
  static int nextTurn(CrMatch after) => after.turn;

  /// `p_finish` for a finished board, or null while the board goes on.
  static Map<String, dynamic>? finishOf(CrMatch m) {
    if (m.phase != CrPhase.finished) return null;
    final int? w = m.winner;
    if (w == null) return null;
    final bool byLimit = m.turnNumber >= CrConfig.maxTurns;
    return <String, dynamic>{
      'winners': w >= 0 ? <int>[w] : <int>[],
      'reason': w < 0 ? 'draw' : (byLimit ? 'turn_limit' : 'cleared'),
    };
  }

  /// True when the opponent's device should animate the newest shot of [v] from its `prev` board
  /// (exactly one new shot since [appliedShots], not mine, and a replayable payload).
  static bool shouldReplay(GmView v, int appliedShots) {
    if (appliedShots < 0) return false;
    if (shotsOf(v) != appliedShots + 1) return false;
    final int? by = shooterOf(v);
    if (by == null || (v.mySeat != null && by == v.mySeat)) return false;
    return boardFrom(v.state['prev']) != null && shotFrom(v.state['shot']) != null;
  }
}
