/// Transport for online arcade games. [SupabaseGmBackend] talks to the live NEXORA project
/// (RPC names / args documented in supabase/migrations/20261112100000_games_online_core.sql);
/// tests pass a fake implementing [GmBackend].
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nexora/online/supabase_client.dart';

/// A live subscription; call [close] when done.
abstract class GmWatch {
  Future<void> close();
}

abstract class GmBackend {
  // ---- match
  Future<Map<String, dynamic>> view(String matchId);
  Future<Map<String, dynamic>> move(String matchId, Map<String, dynamic> move, {int? version});
  Future<Map<String, dynamic>> tick(String matchId);
  Future<Map<String, dynamic>> resign(String matchId);
  Future<Map<String, dynamic>> shot(String matchId, int version, Map<String, dynamic> state, int nextTurn,
      {Map<String, dynamic>? finish});

  /// Calls [onChange] whenever the public state or my private row of [matchId] changes;
  /// [onStatus] gets true when the realtime channel is subscribed, false when it dropped.
  GmWatch watch(String matchId, String uid, void Function() onChange, void Function(bool connected) onStatus);

  // ---- lobby
  Future<Map<String, dynamic>> createRoom(String game, int seats,
      {String? name, bool private = false, Map<String, dynamic>? settings});
  Future<Map<String, dynamic>> joinRoom({String? code, String? roomId, bool spectate = false});
  Future<Map<String, dynamic>> quick(String game, int seats);
  Future<void> takeSeat(String roomId, int seat);
  Future<Map<String, dynamic>> updateRoom(String roomId, {int? seats, Map<String, dynamic>? settings});
  Future<void> setReady(String roomId, bool ready);
  Future<String> start(String roomId);
  Future<void> leave(String roomId);
  Future<String?> roomMatch(String roomId);
  Future<List<Map<String, dynamic>>> rooms(String game);
  Future<List<Map<String, dynamic>>> leaderboard(String game, {int limit = 20});
  Future<Map<String, dynamic>?> myRating(String game, String uid);
}

Map<String, dynamic> _asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class SupabaseGmBackend implements GmBackend {
  const SupabaseGmBackend();

  SupabaseClient get _db => Online.client;

  Future<Map<String, dynamic>> _rpcMap(String fn, Map<String, dynamic> args) async {
    final dynamic r = await _db.rpc<dynamic>(fn, params: args);
    return _asMap(r);
  }

  @override
  Future<Map<String, dynamic>> view(String matchId) => _rpcMap('gm_view', <String, dynamic>{'p_match': matchId});

  @override
  Future<Map<String, dynamic>> move(String matchId, Map<String, dynamic> move, {int? version}) =>
      _rpcMap('gm_move', <String, dynamic>{'p_match': matchId, 'p_move': move, 'p_version': version});

  @override
  Future<Map<String, dynamic>> tick(String matchId) => _rpcMap('gm_tick', <String, dynamic>{'p_match': matchId});

  @override
  Future<Map<String, dynamic>> resign(String matchId) => _rpcMap('gm_resign', <String, dynamic>{'p_match': matchId});

  @override
  Future<Map<String, dynamic>> shot(String matchId, int version, Map<String, dynamic> state, int nextTurn,
          {Map<String, dynamic>? finish}) =>
      _rpcMap('gm_shot', <String, dynamic>{
        'p_match': matchId,
        'p_version': version,
        'p_state': state,
        'p_turn': nextTurn,
        'p_finish': finish,
      });

  @override
  GmWatch watch(String matchId, String uid, void Function() onChange, void Function(bool connected) onStatus) {
    final RealtimeChannel ch = _db.channel('gm:$matchId:$uid');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'game_state',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
      callback: (PostgresChangePayload _) => onChange(),
    );
    // RLS only delivers my own private row
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'game_private',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'match_id', value: matchId),
      callback: (PostgresChangePayload _) => onChange(),
    );
    ch.subscribe((RealtimeSubscribeStatus s, Object? _) {
      onStatus(s == RealtimeSubscribeStatus.subscribed);
      if (s == RealtimeSubscribeStatus.subscribed) onChange();
    });
    return _SupabaseWatch(_db, ch);
  }

  @override
  Future<Map<String, dynamic>> createRoom(String game, int seats,
          {String? name, bool private = false, Map<String, dynamic>? settings}) =>
      _rpcMap('gm_create_room', <String, dynamic>{
        'p_game': game,
        'p_seats': seats,
        'p_name': name,
        'p_private': private,
        'p_settings': settings ?? <String, dynamic>{},
        'p_quick': false,
      });

  @override
  Future<Map<String, dynamic>> joinRoom({String? code, String? roomId, bool spectate = false}) =>
      _rpcMap('gm_join_room', <String, dynamic>{'p_code': code, 'p_room': roomId, 'p_spectate': spectate});

  @override
  Future<Map<String, dynamic>> quick(String game, int seats) =>
      _rpcMap('gm_quick', <String, dynamic>{'p_game': game, 'p_seats': seats});

  @override
  Future<void> takeSeat(String roomId, int seat) async {
    await _db.rpc<dynamic>('gm_take_seat', params: <String, dynamic>{'p_room': roomId, 'p_seat': seat});
  }

  @override
  Future<Map<String, dynamic>> updateRoom(String roomId, {int? seats, Map<String, dynamic>? settings}) =>
      _rpcMap('gm_update_room', <String, dynamic>{'p_room': roomId, 'p_seats': seats, 'p_settings': settings});

  @override
  Future<void> setReady(String roomId, bool ready) async {
    await _db.rpc<dynamic>('set_ready', params: <String, dynamic>{'p_room': roomId, 'p_ready': ready});
  }

  @override
  Future<String> start(String roomId) async {
    final dynamic r = await _db.rpc<dynamic>('gm_start', params: <String, dynamic>{'p_room': roomId});
    return '${r ?? ''}';
  }

  @override
  Future<void> leave(String roomId) async {
    await _db.rpc<dynamic>('leave_room', params: <String, dynamic>{'p_room': roomId});
  }

  @override
  Future<String?> roomMatch(String roomId) async {
    final dynamic r = await _db.rpc<dynamic>('gm_room_match', params: <String, dynamic>{'p_room': roomId});
    return r == null ? null : '$r';
  }

  @override
  Future<List<Map<String, dynamic>>> rooms(String game) async {
    final List<dynamic> r = await _db
        .from('game_room_list')
        .select()
        .eq('game', game)
        .order('created_at', ascending: false)
        .limit(40);
    return <Map<String, dynamic>>[for (final dynamic x in r) _asMap(x)];
  }

  @override
  Future<List<Map<String, dynamic>>> leaderboard(String game, {int limit = 20}) async {
    final List<dynamic> r = await _db.from('game_leaderboard').select().eq('game', game).order('rank').limit(limit);
    return <Map<String, dynamic>>[for (final dynamic x in r) _asMap(x)];
  }

  @override
  Future<Map<String, dynamic>?> myRating(String game, String uid) async {
    final dynamic r = await _db.from('game_ratings').select().eq('game', game).eq('user_id', uid).maybeSingle();
    return r == null ? null : _asMap(r);
  }
}

class _SupabaseWatch implements GmWatch {
  _SupabaseWatch(this._db, this._ch);
  final SupabaseClient _db;
  final RealtimeChannel _ch;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _db.removeChannel(_ch);
    } catch (_) {}
  }
}
