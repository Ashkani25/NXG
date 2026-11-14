// Test doubles for the online games client (imported by the *_test.dart files here).
import 'package:nexora/games/core/online/gm_backend.dart';

class FakeWatch implements GmWatch {
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
  FakeWatch? watcher;

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
    return watcher = FakeWatch();
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

