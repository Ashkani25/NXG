// RoomLink rules (gi dedupe, ephemeral send only while joined, chat dedupe, rtt smoothing,
// host_forfeit fallback) and the pure helpers of the online core.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/online/link.dart';
import 'package:nexora/online/online_core.dart';
import 'package:nexora/online/supabase_client.dart';
import 'package:nexora/online/ui/oui.dart';

class FakeChannel implements RoomChannel {
  final Map<String, void Function(Map<String, dynamic>)> handlers = <String, void Function(Map<String, dynamic>)>{};
  final List<(String, Map<String, dynamic>)> sent = <(String, Map<String, dynamic>)>[];
  void Function(LinkStatus)? status;

  @override
  void onTableChange(String table, String column, String value, void Function() cb) {}
  @override
  void onBroadcast(String event, void Function(Map<String, dynamic> payload) cb) => handlers[event] = cb;
  @override
  void onPresenceSync(void Function(Map<String, Map<String, dynamic>> state) cb) {}
  @override
  void subscribe(void Function(LinkStatus status) cb) => status = cb;
  @override
  Future<void> track(Map<String, dynamic> payload) async {}
  @override
  Future<void> send(String event, Map<String, dynamic> payload) async => sent.add((event, payload));
  @override
  Future<void> close() async {}
}

class FakeIO implements RoomIO {
  final FakeChannel ch = FakeChannel();
  final List<String> rpcs = <String>[];
  bool hasHostForfeit = true;

  @override
  Future<(Map<String, dynamic>?, List<Map<String, dynamic>>)> fetch(String roomId) async => (
        <String, dynamic>{'id': roomId, 'host': 'h', 'mode': '1v1', 'status': 'waiting'},
        <Map<String, dynamic>>[
          <String, dynamic>{'room_id': roomId, 'user_id': 'me', 'role': 'player', 'team': 0, 'slot': 0},
        ],
      );
  @override
  Future<bool> heartbeat(String roomId) async => true;
  @override
  Future<OnlineResult> rpc(String fn, Map<String, dynamic> args) async {
    rpcs.add(fn);
    if (fn == 'host_forfeit' && !hasHostForfeit) {
      return const OnlineResult.fail('خطا', 'PGRST202 Could not find the function public.host_forfeit');
    }
    return const OnlineResult.ok(<String, dynamic>{'outcome': 'forfeit'});
  }

  @override
  RoomChannel open(String topic, String presenceKey) => ch;
}

void main() {
  group('RoomLink', () {
    test('drops own echoes and duplicate gi, forwards the rest', () async {
      final FakeIO io = FakeIO();
      final RoomLink l = RoomLink('r1', 'me', 'Me', io: io, register: false);
      final List<Map<String, dynamic>> got = <Map<String, dynamic>>[];
      final void Function() off = l.onGame((Map<String, dynamic> m, String? from) => got.add(m));
      final void Function(Map<String, dynamic>) g = io.ch.handlers['g']!;
      g(<String, dynamic>{'k': 's', 'from': 'h', 'gi': 1});
      g(<String, dynamic>{'k': 's', 'from': 'h', 'gi': 1});
      g(<String, dynamic>{'k': 's', 'from': 'h', 'gi': 2});
      g(<String, dynamic>{'k': 's', 'from': 'x', 'gi': 1});
      g(<String, dynamic>{'k': 'aim', 'from': 'me', 'gi': 9});
      g(<String, dynamic>{'k': 'res', 'from': 'h'}); // no gi → never a duplicate
      g(<String, dynamic>{'k': 'res', 'from': 'h'});
      await Future<void>.delayed(Duration.zero);
      expect(got.length, 5);
      off();
      l.dispose();
    });

    test('ephemeral kinds are only sent while joined; gi increments', () async {
      final FakeIO io = FakeIO();
      final RoomLink l = RoomLink('r1', 'me', 'Me', io: io, register: false);
      expect(l.sendGame(<String, dynamic>{'k': 's'}), isFalse);
      expect(l.sendGame(<String, dynamic>{'k': 'shot'}), isTrue);
      await l.handleStatus(LinkStatus.subscribed);
      expect(l.state.connected, isTrue);
      expect(l.sendGame(<String, dynamic>{'k': 'aim'}), isTrue);
      final List<Map<String, dynamic>> g = io.ch.sent.where(((String, Map<String, dynamic>) e) => e.$1 == 'g').map(((String, Map<String, dynamic>) e) => e.$2).toList();
      expect(g.length, 2);
      expect(g[0]['gi'], 1);
      expect(g[1]['gi'], 2);
      expect(g[1]['from'], 'me');
      await l.handleStatus(LinkStatus.channelError);
      expect(l.state.connected, isFalse);
      expect(l.state.offlineSince, greaterThan(0));
      l.dispose();
    });

    test('chat dedupe by id, unread counting, rtt smoothing', () {
      int now = 10000;
      final FakeIO io = FakeIO();
      final RoomLink l = RoomLink('r1', 'me', 'Me', io: io, clock: () => now, register: false);
      const ChatMsg c = ChatMsg(id: 'a1', uid: 'x', name: 'X', text: 'سلام', ts: 1);
      l.addChat(c);
      l.addChat(c);
      expect(l.state.chat.length, 1);
      expect(l.state.unread, 1);
      l.handlePong(<String, dynamic>{'to': 'me', 't': now - 100});
      expect(l.state.rtt, 100);
      l.handlePong(<String, dynamic>{'to': 'me', 't': now - 200});
      expect(l.state.rtt, 140);
      l.dispose();
    });

    test('host quit falls back to abandon_match when host_forfeit is missing', () async {
      final FakeIO io = FakeIO()..hasHostForfeit = false;
      final RoomLink l = RoomLink('r1', 'me', 'Me', io: io, register: false);
      await l.hostQuit('m1', <int>[1, 0]);
      expect(io.rpcs.where((String f) => f != 'heartbeat' && f != 'join_room'), <String>['host_forfeit', 'abandon_match']);
      l.dispose();
    });
  });

  group('helpers', () {
    test('auth link params', () {
      final Map<String, String> p = parseAuthParams('nexora://auth#access_token=a.b.c&refresh_token=r1&type=recovery&expires_in=3600');
      expect(p['access_token'], 'a.b.c');
      expect(p['type'], 'recovery');
      final Map<String, String> e = parseAuthParams('nexora://auth#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid');
      expect(e['error_code'], 'otp_expired');
      expect(e['error_description'], 'Email link is invalid');
    });

    test('username / email validation (Godot rules)', () {
      expect(validateUsername('ab'), isNotNull);
      expect(validateUsername('نکسورا_پلیر'), isNull);
      expect(validateUsername('bad<name>'), isNotNull);
      expect(emailOk('a@b.co'), isTrue);
      expect(emailOk('a@b'), isFalse);
    });

    test('errFa maps server errors like Godot err_fa', () {
      expect(errFa('host only'), 'فقط میزبان می‌تونه این کار رو بکنه');
      expect(errFa('match not live'), 'این مسابقه دیگر فعال نیست');
      expect(errFa('Invalid login credentials'), 'ایمیل یا رمز عبور اشتباه است');
      expect(errFa(''), 'خطای ناشناخته؛ دوباره امتحان کن');
    });

    test('rules ↔ settings', () {
      expect(ruleToSettings('t5'), <String, dynamic>{'goals': 3, 'time': 300});
      expect(settingsToRule(<String, dynamic>{'goals': 5, 'time': 0}), 'g5');
      expect(settingsToRule(<String, dynamic>{'goals': 3, 'time': 180}), 't3');
      expect(faNum(12345), '۱۲٬۳۴۵');
      expect(discArtKey('club7'), 'club07');
    });
  });
}
