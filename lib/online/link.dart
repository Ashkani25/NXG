/// RoomLink — one realtime connection per joined room, shared by the lobby and the online match.
/// Port of the Godot app's src/net/room_link.gd (itself a port of Expo link.ts) so Flutter, Godot and
/// Expo clients interoperate in one room (same topics, events, payloads, `gi` dedupe counter).
///
///  - postgres_changes on rooms / room_players  → refetch room state (debounced 150 ms)
///  - broadcast 'chat'                           → text chat
///  - broadcast 'g'                              → match netcode (game payloads, any game)
///  - broadcast 'sync'                           → "please refetch" pings (covers DELETEs, kicks)
///  - broadcast 'pi' / 'po'                      → RTT probe every 3 s (never touches the DB)
///  - presence (key = user id, payload {name})   → who is connected right now
///  - rpc heartbeat every 15 s (server sweeps players silent for 45 s), full refetch every 12 s
///
/// PUBLIC API (used by every online game screen — see lib/online/README.md):
///   link.sendGame(Map)                 broadcast a game message; `from` = my uid is added
///   link.games                         Stream<(Map payload, String? fromUid)>
///   link.state / link.addListener      LinkState (room incl. host + game, players, online, chat, rtt …)
///   link.me / link.myName / link.id
///   link.ping()                        ask everyone to refetch room state
///   link.refresh()                     refetch now
///   link.voice                         VoiceSession (LiveKit)
///   link.dispose()
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'online_core.dart';
import 'supabase_client.dart';
import 'voice.dart';

class ChatMsg {
  const ChatMsg({required this.id, required this.uid, required this.name, required this.text, required this.ts});
  final String id, uid, name, text;
  final int ts;

  static ChatMsg? tryParse(Object? p) {
    if (p is! Map) return null;
    final text = p['text'];
    if (text is! String) return null;
    return ChatMsg(
      id: '${p['id'] ?? ''}',
      uid: '${p['uid'] ?? ''}',
      name: '${p['name'] ?? ''}',
      text: text.length > 200 ? text.substring(0, 200) : text,
      ts: p['ts'] is num ? (p['ts'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'uid': uid, 'name': name, 'text': text, 'ts': ts};
}

@immutable
class LinkState {
  const LinkState({
    this.room,
    this.players = const [],
    this.online = const {},
    this.chat = const [],
    this.connected = false,
    this.loaded = false,
    this.gone = false,
    this.unread = 0,
    this.rtt,
    this.offlineSince = 0,
    this.rejoined = false,
  });
  final Room? room;
  final List<RoomPlayer> players;
  /// presence: uid → display name
  final Map<String, String> online;
  final List<ChatMsg> chat;
  final bool connected, loaded, gone;
  final int unread;
  /// smoothed round-trip time (ms) to the room host (or a peer when I am the host); null = unknown
  final int? rtt;
  /// ms epoch when the realtime link dropped (0 while connected)
  final int offlineSince;
  /// true after an automatic re-entry (resumed after the server sweep dropped us from a waiting room)
  final bool rejoined;

  static const _keep = Object();
  LinkState copyWith({
    Object? room = _keep,
    List<RoomPlayer>? players,
    Map<String, String>? online,
    List<ChatMsg>? chat,
    bool? connected,
    bool? loaded,
    bool? gone,
    int? unread,
    Object? rtt = _keep,
    int? offlineSince,
    bool? rejoined,
  }) =>
      LinkState(
        room: identical(room, _keep) ? this.room : room as Room?,
        players: players ?? this.players,
        online: online ?? this.online,
        chat: chat ?? this.chat,
        connected: connected ?? this.connected,
        loaded: loaded ?? this.loaded,
        gone: gone ?? this.gone,
        unread: unread ?? this.unread,
        rtt: identical(rtt, _keep) ? this.rtt : rtt as int?,
        offlineSince: offlineSince ?? this.offlineSince,
        rejoined: rejoined ?? this.rejoined,
      );

  RoomPlayer? player(String uid) {
    for (final p in players) {
      if (p.userId == uid) return p;
    }
    return null;
  }

  /// players of team t sorted by slot (OnlineMatch.teamOf)
  List<RoomPlayer> team(int t) =>
      players.where((p) => p.isPlayer && p.team == t).toList()..sort((a, b) => (a.slot ?? 0).compareTo(b.slot ?? 0));
}

/// Realtime subscribe status, same names as supabase-js.
enum LinkStatus { subscribed, channelError, timedOut, closed }

/// The transport RoomLink talks to. [SupabaseRoomIO] is the real one; tests pass a fake.
abstract class RoomIO {
  /// Fetch `rooms` row + `room_players` (with profiles) ordered by joined_at. Throw on error.
  Future<(Map<String, dynamic>?, List<Map<String, dynamic>>)> fetch(String roomId);

  /// heartbeat rpc; true when it succeeded
  Future<bool> heartbeat(String roomId);

  /// any rpc (join_room / host_forfeit / abandon_match / claim_host_lost); never throws
  Future<OnlineResult> rpc(String fn, Map<String, dynamic> args);

  /// Open channel `room:<id>` with presence key = me and broadcast self:false/ack:false.
  RoomChannel open(String topic, String presenceKey);
}

abstract class RoomChannel {
  void onTableChange(String table, String column, String value, void Function() cb);
  /// cb receives the *inner* broadcast payload (what JS gets as `({ payload })`).
  void onBroadcast(String event, void Function(Map<String, dynamic> payload) cb);
  /// cb receives presence key → first meta payload.
  void onPresenceSync(void Function(Map<String, Map<String, dynamic>> state) cb);
  void subscribe(void Function(LinkStatus status) cb);
  Future<void> track(Map<String, dynamic> payload);
  Future<void> send(String event, Map<String, dynamic> payload);
  Future<void> close();
}

/// Game message kinds that are worthless when stale: sent only while joined, never queued.
const List<String> kEphemeralGame = <String>['s', 'aim'];

/// Seconds after which the server sweep (45 s) may have dropped a backgrounded player.
const double kSweepAfter = 40;

class RoomLink extends ChangeNotifier {
  RoomLink(this.id, this.me, this.myName, {RoomIO? io, int Function()? clock, VoiceSession? voice, bool register = true})
      : _io = io ?? SupabaseRoomIO(),
        _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _voice = voice,
        _registered = register {
    if (_registered) OnlineCore.instance.registerLink(this);
    _resumeSub = OnlineCore.instance.resumed.listen(onResumed);
    _connect();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    _beatTimer = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
    _heartbeat();
    _pinger = Timer.periodic(const Duration(seconds: 3), (_) => probe());
  }

  final String id;
  final String me;
  String myName;
  final RoomIO _io;
  final int Function() _now;
  final bool _registered;

  LinkState _state = const LinkState();
  LinkState get state => _state;

  RoomChannel? _ch;
  Timer? _debounce, _poll, _beatTimer, _pinger, _beatRetry;
  StreamSubscription<double>? _resumeSub;
  bool _dead = false;
  bool get disposed => _dead;
  final Set<String> _seenOnline = {};
  final _games = StreamController<(Map<String, dynamic>, String?)>.broadcast();
  final _events = StreamController<String>.broadcast();
  bool _refreshing = false, _refreshAgain = false;
  int _gi = 0;
  final Map<String, Set<int>> _seenGi = <String, Set<int>>{};
  final Map<String, List<int>> _seenOrder = <String, List<int>>{};
  final List<String> _chatIds = <String>[];
  int _lastBeatOk = 0;
  bool _maybeSwept = false;
  bool _rejoining = false;

  /// Chat sheet open → incoming messages do not count as unread.
  bool chatOpen = false;

  VoiceSession? _voice;
  VoiceSession get voice => _voice ??= VoiceSession(id);

  /// Join this room's voice chat (one voice session at a time app-wide).
  void voiceJoin() => voice.join();
  void voiceLeave() => _voice?.leave();

  /// Game netcode messages: (payload, sender uid). Duplicates (same sender + gi) are dropped.
  Stream<(Map<String, dynamic>, String?)> get games => _games.stream;

  /// Sound cues ('join' | 'leave' | 'chat') — the UI may play a sound / haptic.
  Stream<String> get cues => _events.stream;

  /// Same as `link.on_game(f)`; returns a cancel function.
  void Function() onGame(void Function(Map<String, dynamic> m, String? from) f) {
    final sub = games.listen((e) => f(e.$1, e.$2));
    return () => sub.cancel();
  }

  void _set(LinkState s) {
    if (_dead) return;
    _state = s;
    notifyListeners();
  }

  /// heartbeat rpc (server sweeps silent players after 45 s); a failure retries after 4 s
  Future<void> _heartbeat() async {
    if (_dead) return;
    bool ok = false;
    try {
      ok = await _io.heartbeat(id);
    } catch (_) {}
    if (_dead) return;
    if (ok) {
      _lastBeatOk = _now();
    } else {
      _beatRetry?.cancel();
      _beatRetry = Timer(const Duration(seconds: 4), _heartbeat);
    }
  }

  /// Back from the background: resync everything right away (rejoin if the sweep dropped us).
  @visibleForTesting
  void onResumed(double away) {
    if (_dead) return;
    if (away >= kSweepAfter || (_lastBeatOk > 0 && _now() - _lastBeatOk >= kSweepAfter * 1000)) _maybeSwept = true;
    _heartbeat();
    refresh();
    ping();
    Timer(const Duration(seconds: 1), probe);
  }

  /// RTT probe: tiny ping/pong broadcast (host, or any online peer when I am the host).
  @visibleForTesting
  void probe() {
    final ch = _ch;
    if (_dead || ch == null || !_state.connected) return;
    final host = _state.room?.host;
    String? to;
    if (host != null && host != me && _state.online.containsKey(host)) {
      to = host;
    } else {
      for (final k in _state.online.keys) {
        if (k != me) {
          to = k;
          break;
        }
      }
    }
    if (to == null) {
      if (_state.rtt != null) _set(_state.copyWith(rtt: null));
      return;
    }
    ch.send('pi', {'t': _now(), 'f': me, 'to': to}).catchError((_) {});
  }

  void _connect() {
    final ch = _io.open('room:$id', me);
    ch.onTableChange('rooms', 'id', id, soon);
    ch.onTableChange('room_players', 'room_id', id, soon);
    ch.onBroadcast('sync', (_) => soon());
    ch.onBroadcast('chat', (p) {
      final c = ChatMsg.tryParse(p);
      if (c != null) addChat(c);
    });
    ch.onBroadcast('pi', (m) {
      if (m['to'] == me && _state.connected) ch.send('po', {'t': m['t'], 'to': m['f']}).catchError((_) {});
    });
    ch.onBroadcast('po', handlePong);
    ch.onBroadcast('g', handleGame);
    ch.onPresenceSync((ps) {
      final online = <String, String>{};
      ps.forEach((k, v) => online[k] = '${v['name'] ?? ''}');
      for (final k in online.keys) {
        if (_seenOnline.add(k) && k != me && _state.connected) _cue('join');
      }
      for (final k in _seenOnline.toList()) {
        if (!online.containsKey(k)) {
          _seenOnline.remove(k);
          if (k != me) _cue('leave');
        }
      }
      _set(_state.copyWith(online: online));
      soon();
    });
    ch.subscribe(handleStatus);
    _ch = ch;
  }

  @visibleForTesting
  Future<void> handleStatus(LinkStatus st) async {
    if (_dead) return;
    final ch = _ch;
    if (st == LinkStatus.subscribed) {
      _set(_state.copyWith(connected: true, offlineSince: 0));
      try {
        await ch?.track({'name': myName});
      } catch (_) {}
      refresh();
      ping(); // others refetch: covers changes we missed while offline
    } else {
      _set(_state.copyWith(connected: false, offlineSince: _state.offlineSince > 0 ? _state.offlineSince : _now()));
    }
  }

  /// 'g' handler: drops my own echoes and duplicates (from + gi), then forwards to listeners.
  @visibleForTesting
  void handleGame(Map<String, dynamic> m) {
    if (_games.isClosed) return;
    final Object? f = m['from'];
    final String from = f is String ? f : '';
    if (from.isNotEmpty && from == me) return;
    if (isDuplicate(from, m['gi'])) return;
    _games.add((m, from.isEmpty ? null : from));
  }

  /// true when (from, gi) was seen already (messages without gi are never duplicates)
  @visibleForTesting
  bool isDuplicate(String from, Object? gi) {
    if (gi is! num) return false;
    final int g = gi.toInt();
    final Set<int> seen = _seenGi.putIfAbsent(from, () => <int>{});
    if (seen.contains(g)) return true;
    seen.add(g);
    final List<int> order = _seenOrder.putIfAbsent(from, () => <int>[]);
    order.add(g);
    if (order.length > 256) seen.remove(order.removeAt(0));
    return false;
  }

  /// 'po' handler: exponential smoothing rtt = prev*.6 + r*.4, samples > 10 s ignored.
  @visibleForTesting
  void handlePong(Map<String, dynamic> m) {
    if (m['to'] != me || m['t'] is! num) return;
    final r = math.max(1, _now() - (m['t'] as num).toInt());
    if (r > 10000) return;
    final prev = _state.rtt;
    _set(_state.copyWith(rtt: (prev == null ? r : prev * .6 + r * .4).round()));
  }

  void _cue(String c) {
    if (!_events.isClosed) _events.add(c);
  }

  /// debounced refetch (150 ms)
  void soon() {
    if (_dead) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), refresh);
  }

  /// Refetch room + players. Marks `gone` when the room vanished or I am no longer in it;
  /// re-enters once when the server sweep dropped us while backgrounded.
  Future<void> refresh() async {
    if (_dead) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    (Map<String, dynamic>?, List<Map<String, dynamic>>)? res;
    try {
      res = await _io.fetch(id);
    } catch (_) {
      res = null;
    }
    _refreshing = false;
    if (_dead) return;
    if (res != null) {
      final players = res.$2.map(RoomPlayer.fromJson).toList();
      final mine = players.any((p) => p.userId == me);
      final gone = res.$1 == null || !mine;
      if (gone && res.$1 != null && _maybeSwept && !_rejoining) {
        _maybeSwept = false;
        _rejoining = true;
        final OnlineResult j = await _io.rpc('join_room', <String, dynamic>{'p_room': id});
        _rejoining = false;
        if (_dead) return;
        if (j.ok) {
          _set(_state.copyWith(rejoined: true));
          ping();
          _refreshAgain = false;
          await refresh();
          return;
        }
      }
      if (mine) _maybeSwept = false;
      _set(_state.copyWith(room: res.$1 != null ? Room.fromJson(res.$1!) : _state.room, players: players, loaded: true, gone: gone));
    }
    if (_refreshAgain) {
      _refreshAgain = false;
      await refresh();
    }
  }

  /// Ask every client in the room to refetch.
  void ping() {
    if (_dead) return;
    _ch?.send('sync', {}).catchError((_) {});
  }

  @visibleForTesting
  void addChat(ChatMsg c) {
    if (c.id.isNotEmpty) {
      if (_chatIds.contains(c.id)) return;
      _chatIds.add(c.id);
      if (_chatIds.length > 200) _chatIds.removeAt(0);
    }
    final chat = [..._state.chat, c];
    final trimmed = chat.length > 80 ? chat.sublist(chat.length - 80) : chat;
    if (c.uid != me) _cue('chat');
    _set(_state.copyWith(chat: trimmed, unread: chatOpen || c.uid == me ? 0 : _state.unread + 1));
  }

  void sendChat(String text) {
    var t = text.trim();
    if (t.length > 200) t = t.substring(0, 200);
    if (t.isEmpty) return;
    final now = _now();
    final c = ChatMsg(id: '$now-${_rand36(5)}', uid: me, name: myName, text: t, ts: now);
    addChat(c);
    _ch?.send('chat', c.toJson()).catchError((_) {});
  }

  void markRead() {
    if (_state.unread != 0) _set(_state.copyWith(unread: 0));
  }

  /// Broadcast a game message (`from` = my uid and a per-sender counter `gi` are added).
  /// Ephemeral kinds ('s', 'aim') are dropped while the channel is not joined. Returns false then.
  bool sendGame(Map<String, dynamic> m) {
    final ch = _ch;
    if (_dead || ch == null) return false;
    final String k = '${m['k'] ?? ''}';
    if (kEphemeralGame.contains(k) && !_state.connected) return false;
    _gi++;
    ch.send('g', {...m, 'from': me, 'gi': _gi}).catchError((_) {});
    return true;
  }

  // ---------------------------------------------------------------- match end (server: 20261113170000_online_fixes.sql)
  /// Host quits a running match: forfeit when opponents are still here, plain abandon otherwise.
  /// Falls back to abandon_match on servers without host_forfeit. data['outcome'] = forfeit|abandoned|none.
  Future<OnlineResult> hostQuit(String matchId, List<int> score) async {
    OnlineResult r = await _io.rpc('host_forfeit', <String, dynamic>{
      'p_match': matchId,
      'p_score_a': score.isNotEmpty ? score[0] : 0,
      'p_score_b': score.length > 1 ? score[1] : 0,
    });
    if (!r.ok && (r.raw.contains('PGRST202') || r.raw.contains('Could not find the function'))) {
      r = await _io.rpc('abandon_match', <String, dynamic>{'p_match': matchId});
    }
    if (!_dead) ping();
    return r;
  }

  /// The host vanished mid-match (≥30 s silent server-side): take over the room and settle the match.
  /// Errors: "host still online" (retry later) / "match not live" (already settled).
  Future<OnlineResult> claimHostLost(String matchId, List<int> score) async {
    final OnlineResult r = await _io.rpc('claim_host_lost', <String, dynamic>{
      'p_match': matchId,
      'p_score_a': score.isNotEmpty ? score[0] : 0,
      'p_score_b': score.length > 1 ? score[1] : 0,
    });
    if (!_dead) {
      ping();
      refresh();
    }
    return r;
  }

  /// TS / Godot name: destroy().
  void destroy() => dispose();

  @override
  void dispose() {
    if (_dead) return;
    _dead = true;
    if (_registered) OnlineCore.instance.unregisterLink(this);
    _resumeSub?.cancel();
    _debounce?.cancel();
    _poll?.cancel();
    _beatTimer?.cancel();
    _beatRetry?.cancel();
    _pinger?.cancel();
    _voice?.destroy();
    final c = _ch;
    _ch = null;
    if (c != null) c.close().catchError((_) {});
    _games.close();
    _events.close();
    super.dispose();
  }
}

String _rand36(int n) {
  const String a = '0123456789abcdefghijklmnopqrstuvwxyz';
  final math.Random r = math.Random();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < n; i++) {
    b.write(a[r.nextInt(36)]);
  }
  return b.toString();
}

/// Unwraps a broadcast message the way supabase-js does: JS sends {type, event, payload:{…}};
/// older Dart clients flatten the fields. Accept both.
Map<String, dynamic> unwrapBroadcast(Map<String, dynamic> msg) {
  final p = msg['payload'];
  if (p is Map) return Map<String, dynamic>.from(p);
  final m = Map<String, dynamic>.from(msg)
    ..remove('type')
    ..remove('event');
  return m;
}

/// Presence state → key → first meta (without presence_ref).
Map<String, Map<String, dynamic>> presenceMap(List<SinglePresenceState> ps) {
  final out = <String, Map<String, dynamic>>{};
  for (final s in ps) {
    out[s.key] = s.presences.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(s.presences.first.payload);
  }
  return out;
}

// ---------------- real transport ----------------

class SupabaseRoomIO implements RoomIO {
  @override
  Future<(Map<String, dynamic>?, List<Map<String, dynamic>>)> fetch(String roomId) async {
    final db = Online.client;
    final r = db.from('rooms').select().eq('id', roomId).maybeSingle();
    final p = db
        .from('room_players')
        .select('*, profiles(username, avatar, avatar_url, level, rating, league, equipped_disc)')
        .eq('room_id', roomId)
        .order('joined_at');
    final room = await r;
    final players = await p;
    return (room, List<Map<String, dynamic>>.from(players));
  }

  @override
  Future<bool> heartbeat(String roomId) async => (await callRpc('heartbeat', <String, dynamic>{'p_room': roomId})).ok;

  @override
  Future<OnlineResult> rpc(String fn, Map<String, dynamic> args) => callRpc(fn, args);

  @override
  RoomChannel open(String topic, String presenceKey) => _SupabaseRoomChannel(
        Online.client.channel(topic, opts: RealtimeChannelConfig(self: false, ack: false, key: presenceKey)),
      );
}

class _SupabaseRoomChannel implements RoomChannel {
  _SupabaseRoomChannel(this.ch);
  final RealtimeChannel ch;

  @override
  void onTableChange(String table, String column, String value, void Function() cb) {
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: value),
      callback: (_) => cb(),
    );
  }

  @override
  void onBroadcast(String event, void Function(Map<String, dynamic> payload) cb) {
    ch.onBroadcast(event: event, callback: (msg) => cb(unwrapBroadcast(msg)));
  }

  @override
  void onPresenceSync(void Function(Map<String, Map<String, dynamic>> state) cb) {
    ch.onPresenceSync((_) => cb(presenceMap(ch.presenceState())));
  }

  @override
  void subscribe(void Function(LinkStatus status) cb) {
    ch.subscribe((status, _) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          cb(LinkStatus.subscribed);
        case RealtimeSubscribeStatus.channelError:
          cb(LinkStatus.channelError);
        case RealtimeSubscribeStatus.timedOut:
          cb(LinkStatus.timedOut);
        case RealtimeSubscribeStatus.closed:
          cb(LinkStatus.closed);
      }
    });
  }

  @override
  Future<void> track(Map<String, dynamic> payload) => ch.track(payload);

  /// Wire format identical to supabase-js `send({type:'broadcast', event, payload})`.
  @override
  Future<void> send(String event, Map<String, dynamic> payload) =>
      ch.sendBroadcastMessage(event: event, payload: {'payload': payload});

  @override
  Future<void> close() async {
    try {
      await ch.untrack();
    } catch (_) {}
    try {
      await Online.client.removeChannel(ch);
    } catch (_) {}
  }
}
