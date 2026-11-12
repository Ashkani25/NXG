/// RoomLink — one realtime connection per joined room, shared by the lobby and the online match.
/// 1:1 port of src/online/link.ts (Expo) so Flutter and Expo clients interoperate in one room.
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
  Future<void> heartbeat(String roomId);

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

class RoomLink extends ChangeNotifier {
  RoomLink(this.id, this.me, this.myName, {RoomIO? io, int Function()? clock, VoiceSession? voice})
      : _io = io ?? SupabaseRoomIO(),
        _now = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _voice = voice {
    _connect();
    refresh();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => refresh());
    _beat = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
    _heartbeat();
    _pinger = Timer.periodic(const Duration(seconds: 3), (_) => probe());
  }

  final String id;
  final String me;
  String myName;
  final RoomIO _io;
  final int Function() _now;

  LinkState _state = const LinkState();
  LinkState get state => _state;

  RoomChannel? _ch;
  Timer? _debounce, _poll, _beat, _pinger;
  bool _dead = false;
  bool get disposed => _dead;
  final Set<String> _seenOnline = {};
  final _games = StreamController<(Map<String, dynamic>, String?)>.broadcast();
  final _events = StreamController<String>.broadcast();

  /// Chat sheet open → incoming messages do not count as unread.
  bool chatOpen = false;

  VoiceSession? _voice;
  VoiceSession get voice => _voice ??= VoiceSession(id);

  /// Game netcode messages: (payload, sender uid). Payload shapes are the same as Expo.
  Stream<(Map<String, dynamic>, String?)> get games => _games.stream;

  /// Sound cues ('join' | 'leave' | 'chat') — the UI may play a sound / haptic.
  Stream<String> get cues => _events.stream;

  /// Same as `link.onGame(f)` in TS; returns a cancel function.
  void Function() onGame(void Function(Map<String, dynamic> m, String? from) f) {
    final sub = games.listen((e) => f(e.$1, e.$2));
    return () => sub.cancel();
  }

  void _set(LinkState s) {
    if (_dead) return;
    _state = s;
    notifyListeners();
  }

  void _heartbeat() {
    if (_dead) return;
    _io.heartbeat(id).catchError((_) {});
  }

  /// RTT probe: tiny ping/pong broadcast (host, or any online peer when I am the host).
  @visibleForTesting
  void probe() {
    final ch = _ch;
    if (ch == null || !_state.connected) return;
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
    ch.onTableChange('rooms', 'id', id, _soon);
    ch.onTableChange('room_players', 'room_id', id, _soon);
    ch.onBroadcast('sync', (_) => _soon());
    ch.onBroadcast('chat', (p) {
      final c = ChatMsg.tryParse(p);
      if (c != null) _addChat(c);
    });
    ch.onBroadcast('pi', (m) {
      if (m['to'] == me) ch.send('po', {'t': m['t'], 'to': m['f']}).catchError((_) {});
    });
    ch.onBroadcast('po', handlePong);
    ch.onBroadcast('g', (m) {
      if (_games.isClosed) return;
      final from = m['from'];
      _games.add((m, from is String ? from : null));
    });
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
      _soon();
    });
    ch.subscribe((st) async {
      if (_dead) return;
      if (st == LinkStatus.subscribed) {
        _set(_state.copyWith(connected: true));
        try {
          await ch.track({'name': myName});
        } catch (_) {}
        refresh();
      } else {
        _set(_state.copyWith(connected: false));
      }
    });
    _ch = ch;
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

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), refresh);
  }

  /// Refetch room + players. Marks `gone` when the room vanished or I am no longer in it.
  Future<void> refresh() async {
    if (_dead) return;
    (Map<String, dynamic>?, List<Map<String, dynamic>>) res;
    try {
      res = await _io.fetch(id);
    } catch (_) {
      return;
    }
    if (_dead) return;
    final players = res.$2.map(RoomPlayer.fromJson).toList();
    final gone = res.$1 == null || !players.any((p) => p.userId == me);
    _set(_state.copyWith(room: res.$1 != null ? Room.fromJson(res.$1!) : _state.room, players: players, loaded: true, gone: gone));
  }

  /// Ask every client in the room to refetch.
  void ping() {
    _ch?.send('sync', {}).catchError((_) {});
  }

  void _addChat(ChatMsg c) {
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
    final c = ChatMsg(id: '$now-${math.Random().nextInt(1 << 30).toRadixString(36)}', uid: me, name: myName, text: t, ts: now);
    _addChat(c);
    _ch?.send('chat', c.toJson()).catchError((_) {});
  }

  void markRead() {
    if (_state.unread != 0) _set(_state.copyWith(unread: 0));
  }

  /// Broadcast a game message to the room (`from` = my uid is added, like TS).
  void sendGame(Map<String, dynamic> m) {
    _ch?.send('g', {...m, 'from': me}).catchError((_) {});
  }

  /// TS name: destroy().
  void destroy() => dispose();

  @override
  void dispose() {
    if (_dead) return;
    _dead = true;
    _debounce?.cancel();
    _poll?.cancel();
    _beat?.cancel();
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
  Future<void> heartbeat(String roomId) => rpcQuiet('heartbeat', {'p_room': roomId});

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
