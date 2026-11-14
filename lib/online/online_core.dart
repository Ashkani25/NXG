/// OnlineCore — session, own profile row, auth actions, live RoomLinks and the current room.
/// Port of the Godot app's Supa autoload (src/net/supa.gd) + OUI auth/room bookkeeping
/// (src/online/oui.gd) on top of supabase_flutter.
///
///  - session persisted by supabase_flutter (SharedPreferences) and auto-refreshed by the SDK;
///  - guests are signed in anonymously on demand ([ensure], deduped);
///  - the own `profiles` row is loaded on sign-in, `online_at` stamped, and kept live over realtime
///    (channel `profile:<uid>`, UPDATE events) — the row itself is created by the DB trigger
///    `on_auth_user_created` (handle_new_user), exactly like Godot / Expo;
///  - account switch / sign-out destroys every live RoomLink; sign-out calls `leave_all_rooms` first;
///  - app resume emits [resumed] (seconds away) so RoomLinks / the match can resync.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'link.dart';
import 'supabase_client.dart';

/// Result of an online call (Godot's {ok, data, error, raw}). Never thrown.
class OnlineResult {
  const OnlineResult.ok([this.data])
      : ok = true,
        error = '',
        raw = '';
  const OnlineResult.fail(this.error, this.raw)
      : ok = false,
        data = null;
  final bool ok;
  final Object? data;

  /// Persian, user-facing (errFa)
  final String error;

  /// original message (for checks like "not live" / "host still online" / PGRST202)
  final String raw;

  Map<String, dynamic> get map => data is Map ? Map<String, dynamic>.from(data as Map) : <String, dynamic>{};
  List<Map<String, dynamic>> get rows {
    final Object? d = data;
    if (d is List) return d.whereType<Map<dynamic, dynamic>>().map((Map<dynamic, dynamic> m) => Map<String, dynamic>.from(m)).toList();
    if (d is Map) return <Map<String, dynamic>>[Map<String, dynamic>.from(d)];
    return <Map<String, dynamic>>[];
  }
}

OnlineResult failOf(Object e) {
  final String raw = errMessage(e);
  return OnlineResult.fail(errFa(e), raw);
}

/// Runs [f] and wraps the outcome; never throws.
Future<OnlineResult> guard(Future<Object?> Function() f) async {
  if (!Online.ready) return OnlineResult.fail(errFa('Network request failed'), 'Network request failed');
  try {
    final Object? d = await f();
    return OnlineResult.ok(d);
  } catch (e) {
    return failOf(e);
  }
}

/// rpc that never throws (Supa.call_rpc).
Future<OnlineResult> callRpc(String fn, [Map<String, dynamic>? args]) =>
    guard(() async {
      final dynamic d = await Online.client.rpc<dynamic>(fn, params: args ?? <String, dynamic>{});
      return d as Object?;
    });

class OnlineCore extends ChangeNotifier with WidgetsBindingObserver {
  OnlineCore._();
  static final OnlineCore instance = OnlineCore._();

  bool _booted = false;
  bool _booting = false;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _profileCh;
  String _lastUid = '';
  Future<String>? _ensuring;
  DateTime? _pausedAt;

  /// own profiles row (live) — empty when signed out / not loaded yet
  Map<String, dynamic> profile = <String, dynamic>{};

  /// set when a password-recovery link signed the user in: UI asks for a new password
  bool recovery = false;

  /// last auth event name (INITIAL_SESSION | SIGNED_IN | SIGNED_OUT | TOKEN_REFRESHED | USER_UPDATED | PASSWORD_RECOVERY)
  String lastEvent = '';

  final StreamController<double> _resumed = StreamController<double>.broadcast();

  /// app came back to the foreground after N seconds (Supa.app_resumed)
  Stream<double> get resumed => _resumed.stream;

  bool get ready => Online.ready;

  // ---------------------------------------------------------------- boot
  /// Initialises Supabase (if needed) and hooks auth/profile/lifecycle. Safe to call many times.
  Future<void> boot() async {
    if (_booted || _booting) return;
    _booting = true;
    await Online.init();
    _booting = false;
    if (!Online.ready) {
      notifyListeners();
      return;
    }
    _booted = true;
    WidgetsBinding.instance.addObserver(this);
    _authSub = Online.client.auth.onAuthStateChange.listen(_onAuth, onError: (Object _) {});
    _afterSignIn();
    notifyListeners();
  }

  void _onAuth(AuthState s) {
    lastEvent = _eventName(s.event);
    if (s.event == AuthChangeEvent.passwordRecovery) recovery = true;
    if (uid != _lastUid) _afterSignIn();
    notifyListeners();
  }

  static String _eventName(AuthChangeEvent e) {
    switch (e) {
      case AuthChangeEvent.initialSession:
        return 'INITIAL_SESSION';
      case AuthChangeEvent.signedIn:
        return 'SIGNED_IN';
      case AuthChangeEvent.signedOut:
        return 'SIGNED_OUT';
      case AuthChangeEvent.tokenRefreshed:
        return 'TOKEN_REFRESHED';
      case AuthChangeEvent.userUpdated:
        return 'USER_UPDATED';
      case AuthChangeEvent.passwordRecovery:
        return 'PASSWORD_RECOVERY';
      default:
        return e.name;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      double away = 0;
      final DateTime? p = _pausedAt;
      if (p != null) away = DateTime.now().difference(p).inMilliseconds / 1000.0;
      _pausedAt = null;
      if (!_resumed.isClosed) _resumed.add(away);
    }
  }

  // ---------------------------------------------------------------- session helpers
  User? get user => Online.ready ? Online.client.auth.currentUser : null;
  String get uid => user?.id ?? '';
  bool get signedIn => uid.isNotEmpty;
  String get email => user?.email ?? '';
  bool get isGuest {
    final User? u = user;
    if (u == null) return false;
    return u.isAnonymous || (u.email ?? '').isEmpty;
  }

  String get username {
    final String n = '${profile['username'] ?? ''}';
    return n.isEmpty ? 'Pilot' : n;
  }

  void _afterSignIn() {
    final String me = uid;
    final String prev = _lastUid;
    _lastUid = me;
    if (prev.isNotEmpty && prev != me) _dropLinks();
    final RealtimeChannel? old = _profileCh;
    _profileCh = null;
    if (old != null) Online.client.removeChannel(old).catchError((Object _) => 'error');
    if (me.isEmpty) {
      profile = <String, dynamic>{};
      notifyListeners();
      return;
    }
    refreshProfile();
    Online.client
        .from('profiles')
        .update(<String, dynamic>{'online_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', me)
        .then((dynamic _) {}, onError: (Object _) {});
    final RealtimeChannel ch = Online.client.channel('profile:$me');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'profiles',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: me),
      callback: (PostgresChangePayload p) {
        if (uid != me) return;
        profile = <String, dynamic>{...profile, ...p.newRecord};
        notifyListeners();
      },
    );
    ch.subscribe();
    _profileCh = ch;
  }

  /// Reload the own profiles row (null when signed out / failed).
  Future<Map<String, dynamic>?> refreshProfile() async {
    final String me = uid;
    if (me.isEmpty) return null;
    final OnlineResult r = await guard(() => Online.client.from('profiles').select().eq('id', me).maybeSingle());
    if (uid != me) return null;
    if (r.ok && r.data is Map) {
      profile = Map<String, dynamic>.from(r.data as Map);
      notifyListeners();
      return profile;
    }
    return null;
  }

  // ---------------------------------------------------------------- auth
  /// Guests are signed in anonymously on demand. Returns the uid ('' on failure).
  Future<String> ensure() async {
    if (!Online.ready) await boot();
    if (!Online.ready) return '';
    if (signedIn) return uid;
    final Future<String> f = _ensuring ??= () async {
      final OnlineResult r = await signInAnon();
      return r.ok ? uid : '';
    }();
    final String id = await f;
    _ensuring = null;
    return id;
  }

  Future<OnlineResult> signInAnon() => guard(() async {
        final AuthResponse res = await Online.client.auth.signInAnonymously();
        if (res.session == null) throw const AuthException('Anonymous sign-ins are disabled');
        return res.user?.id;
      });

  /// data['info'] == 'confirm' when e-mail confirmation is required (no session until the link is opened)
  Future<OnlineResult> signUpEmail(String email, String password, [String username = '']) => guard(() async {
        final Map<String, dynamic> data = <String, dynamic>{};
        if (username.trim().isNotEmpty) data['username'] = username.trim();
        final AuthResponse res = await Online.client.auth
            .signUp(email: email.trim(), password: password, data: data, emailRedirectTo: kAuthRedirect);
        return <String, dynamic>{'info': res.session != null ? '' : 'confirm'};
      });

  Future<OnlineResult> signInEmail(String email, String password) => guard(() async {
        final AuthResponse res = await Online.client.auth.signInWithPassword(email: email.trim(), password: password);
        return res.user?.id;
      });

  /// guest → e-mail upgrade keeping the same user id
  Future<OnlineResult> upgrade(String email, String password) => guard(() async {
        await Online.client.auth
            .updateUser(UserAttributes(email: email.trim(), password: password), emailRedirectTo: kAuthRedirect);
        return <String, dynamic>{'info': 'confirm'};
      });

  Future<OnlineResult> setNewPassword(String password) async {
    final OnlineResult r = await guard(() async {
      await Online.client.auth.updateUser(UserAttributes(password: password));
      return null;
    });
    if (r.ok) {
      recovery = false;
      notifyListeners();
    }
    return r;
  }

  Future<OnlineResult> resetPassword(String email) => guard(() async {
        await Online.client.auth.resetPasswordForEmail(email.trim(), redirectTo: kAuthRedirect);
        return null;
      });

  Future<OnlineResult> resend(String email) => guard(() async {
        await Online.client.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: kAuthRedirect);
        return null;
      });

  /// Auth deep link (nexora://auth#access_token=..&refresh_token=..&type=recovery).
  Future<OnlineResult> handleAuthUrl(Uri uri) async {
    if (!Online.ready) await boot();
    final Map<String, String> p = parseAuthParams(uri.toString());
    if (p.containsKey('error') || p.containsKey('error_description')) {
      if (p['error_code'] == 'otp_expired') {
        return const OnlineResult.fail('لینک ایمیل منقضی شده؛ دوباره درخواست بده', 'otp_expired');
      }
      final String m = p['error_description'] ?? p['error'] ?? '';
      return OnlineResult.fail(errFa(m), m);
    }
    if (!p.containsKey('access_token') || !p.containsKey('refresh_token')) {
      return OnlineResult.fail(errFa('bad link'), 'bad link');
    }
    final OnlineResult r = await guard(() async {
      await Online.client.auth.getSessionFromUrl(uri);
      return <String, dynamic>{'type': p['type'] ?? ''};
    });
    if (r.ok && p['type'] == 'recovery') {
      recovery = true;
      notifyListeners();
    }
    return r;
  }

  Future<void> signOut() async {
    dropLink();
    if (signedIn) {
      await callRpc('leave_all_rooms');
      try {
        await Online.client.auth.signOut(scope: SignOutScope.global);
      } catch (_) {
        try {
          await Online.client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {}
      }
    }
    profile = <String, dynamic>{};
    notifyListeners();
  }

  /// auth.tsx setUsername: validation + profiles update
  Future<OnlineResult> setUsername(String name) async {
    final String n = name.trim();
    final String? bad = validateUsername(n);
    if (bad != null) return OnlineResult.fail(bad, '');
    if (!signedIn) return OnlineResult.fail(errFa('not signed in'), 'not signed in');
    final OnlineResult r = await patchProfile(<String, dynamic>{'username': n});
    return r;
  }

  /// PATCH own profiles row and mirror it locally.
  Future<OnlineResult> patchProfile(Map<String, dynamic> patch) async {
    final String me = uid;
    if (me.isEmpty) return OnlineResult.fail(errFa('not signed in'), 'not signed in');
    final OnlineResult r = await guard(() async {
      await Online.client.from('profiles').update(patch).eq('id', me);
      return null;
    });
    if (r.ok) {
      profile = <String, dynamic>{...profile, ...patch};
      notifyListeners();
    }
    return r;
  }

  // ---------------------------------------------------------------- live RoomLinks
  final Map<String, RoomLink> _links = <String, RoomLink>{};

  void registerLink(RoomLink l) => _links[l.id] = l;
  void unregisterLink(RoomLink l) {
    if (identical(_links[l.id], l)) _links.remove(l.id);
  }

  RoomLink? linkFor(String roomId) {
    final RoomLink? l = _links[roomId];
    return l != null && !l.disposed ? l : null;
  }

  void _dropLinks() {
    for (final RoomLink l in _links.values.toList()) {
      if (!l.disposed) l.destroy();
    }
    _links.clear();
    link = null;
  }

  // ---------------------------------------------------------------- current room (OUI.link)
  RoomLink? link;
  String skipMatch = '';
  bool firstLoad = true;
  Map<String, dynamic> beforeProfile = <String, dynamic>{};

  /// Creates the RoomLink for [room] (once per room). Returns the room id or '' when not possible.
  String enterRoom(Object? room) {
    final Map<String, dynamic> r = room is Map ? Map<String, dynamic>.from(room) : <String, dynamic>{};
    final String me = uid;
    final String rid = '${r['id'] ?? ''}';
    if (rid.isEmpty || me.isEmpty) return '';
    final RoomLink? cur = link;
    if (cur != null && !cur.disposed && cur.id == rid) return rid;
    dropLink();
    firstLoad = true;
    skipMatch = '';
    link = RoomLink(rid, me, username);
    notifyListeners();
    return rid;
  }

  /// Adopt an existing link (lobby opened from match/result).
  RoomLink? linkForRoom(String roomId) {
    final RoomLink? cur = link;
    if (cur != null && !cur.disposed && cur.id == roomId) return cur;
    final RoomLink? l = linkFor(roomId);
    if (l != null) {
      if (cur != null && !identical(cur, l)) dropLink();
      link = l;
    }
    return l;
  }

  void dropLink() {
    final RoomLink? l = link;
    link = null;
    if (l != null && !l.disposed) l.destroy();
    notifyListeners();
  }

  /// leave_room rpc + destroy link
  Future<void> leaveRoom() async {
    final RoomLink? l = link;
    if (l != null) {
      callRpc('leave_room', <String, dynamic>{'p_room': l.id});
      dropLink();
    }
  }

  /// shared quick/arena matchmaking. Returns '' on success (room entered) or a Persian error.
  Future<(String, String)> quickMatch(String mode, [String kind = 'quick']) async {
    final OnlineResult r = await callRpc('quick_match', <String, dynamic>{'p_mode': mode, 'p_kind': kind});
    if (!r.ok) return (r.error, '');
    return ('', enterRoom(r.data));
  }

  // ---------------------------------------------------------------- leagues + disc stats caches
  List<Map<String, dynamic>> leagues = <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>>? _leaguesF;

  Future<List<Map<String, dynamic>>> loadLeagues() async {
    if (leagues.isNotEmpty) return leagues;
    final Future<List<Map<String, dynamic>>> f = _leaguesF ??= () async {
      final OnlineResult r = await guard(() => Online.client.from('leagues').select().order('sort'));
      if (r.ok) leagues = r.rows;
      return leagues;
    }();
    final List<Map<String, dynamic>> out = await f;
    _leaguesF = null;
    return out;
  }

  final Map<String, Map<String, dynamic>> discCatalog = <String, Map<String, dynamic>>{};
  bool discsLoaded = false;

  Future<void> loadDiscs() async {
    if (discsLoaded) return;
    final OnlineResult r = await guard(() => Online.client.from('discs').select());
    if (r.ok) {
      for (final Map<String, dynamic> d in r.rows) {
        discCatalog['${d['id']}'] = d;
      }
      discsLoaded = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Godot err map / RN setUsername validation. Returns a Persian error or null when valid.
String? validateUsername(String n) {
  if (n.length < 3 || n.length > 20) return 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد';
  if (!RegExp(r'^[A-Za-z0-9_.\- \u0600-\u06FF\u200c]+$').hasMatch(n)) return 'فقط حروف، عدد، فاصله و _ . - مجاز است';
  return null;
}

/// Godot email check (account.gd _email_ok)
bool emailOk(String e) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e.trim());

/// Fragment (or query) params of an auth deep link (Supa.handle_auth_url parsing).
Map<String, String> parseAuthParams(String url) {
  final int i = url.indexOf('#');
  final int q = url.indexOf('?');
  final String raw = i >= 0 ? url.substring(i + 1) : (q >= 0 ? url.substring(q + 1) : '');
  final Map<String, String> p = <String, String>{};
  for (final String kv in raw.split('&')) {
    if (kv.isEmpty) continue;
    final int e = kv.indexOf('=');
    final String k = e < 0 ? kv : kv.substring(0, e);
    final String v = e < 0 ? '' : kv.substring(e + 1);
    String dec(String s) {
      try {
        return Uri.decodeComponent(s.replaceAll('+', ' '));
      } catch (_) {
        return s;
      }
    }

    p[dec(k)] = dec(v);
  }
  return p;
}

/// Disc stats {power, accuracy} for a disc/team id (NxDiscs.stats + deterministic fallback).
({double power, double accuracy}) discStatsOf(String id) {
  final String k = id.isEmpty ? 'club0' : id;
  final Map<String, dynamic>? c = OnlineCore.instance.discCatalog[k];
  if (c != null) {
    double n(Object? v) => v is num ? v.toDouble() : 5;
    return (power: n(c['power']), accuracy: n(c['accuracy']));
  }
  final double base = (k.startsWith('leg') || k.startsWith('vip')) ? 8 : ((k.startsWith('club') || k.startsWith('nat')) ? 5 : 6);
  return (power: base, accuracy: base);
}
