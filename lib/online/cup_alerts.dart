// Cups: app-wide tournament layer (v0.7.0).
//  * in-app alerts for tournament notifications (10-minute reminder, check-in, draw done, "your match is ready",
//    prizes): the server writes rows into public.notifications; this listens to the signed-in user's inserts over
//    realtime and shows a card with sound + vibration (foreground) or a device notification (background).
//  * AUTO-MOVE: listens to the user's cup_matches rows (p1 = me / p2 = me) anywhere in the app. When a pairing
//    becomes ready (after the draw at the scheduled time) both checked-in players are moved into the match at the same
//    moment: the app opens 'cupmatch:<cup>:<match>' which calls cup_enter and joins the cup room. A notification tap
//    deep-links the same way.
//  * the 10-minute check-in alarm is (re)scheduled for every upcoming cup the user is in on start / sign-in.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../net/auth.dart';
import '../net/supabase.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'cup_logic.dart';
import 'cups.dart';
import 'cup_reminders.dart';

/// Pure decision for the app-wide listener: should a cup_matches change move this user into the match now?
bool cupShouldAutoEnter({required Map<String, dynamic> row, required String? uid, required Set<String> entered, required bool inCupRoom}) {
  if (uid == null || inCupRoom) return false;
  final st = '${row['status'] ?? ''}', id = '${row['id'] ?? ''}';
  if (id.isEmpty || entered.contains(id)) return false;
  if (st != 'ready' && st != 'live') return false;
  return row['p1'] == uid || row['p2'] == uid;
}

class CupAlerts {
  CupAlerts._();
  static final i = CupAlerts._();

  /// Opens the online area with an entry ('cup:<id>' / 'cupmatch:<cup>:<match>'); wired by main.dart to the shell.
  void Function(String entry)? open;
  RealtimeChannel? _ch;
  String? _uid;
  bool _showing = false;
  final Set<String> _entered = {};

  Future<void> init() async {
    await CupReminderService.i.init((entry) => open?.call(entry));
    Auth.i.addListener(_sync);
    _sync();
  }

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  void _sync() {
    final u = Auth.i.uid;
    if (u == _uid) return;
    if (_ch != null) {
      sb.removeChannel(_ch!);
      _ch = null;
    }
    _uid = u;
    if (u == null || !supaReady) return;
    _ch = sb
        .channel('cupalerts:$u')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u),
            callback: (p) => handle(p.newRecord))
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'cup_matches',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'p1', value: u),
            callback: (p) => onMatch(p.newRecord))
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'cup_matches',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'p2', value: u),
            callback: (p) => onMatch(p.newRecord))
        .subscribe();
    unawaited(syncReminders());
    unawaited(_catchUp());
  }

  /// Schedule the 10-minute check-in alarm for every upcoming cup this user is registered in (main or waitlist).
  Future<void> syncReminders() async {
    final u = Auth.i.uid;
    if (u == null || !supaReady) return;
    try {
      final rows = recs(await sb.from('cup_players').select('status, cups!inner(id, name, starts_at, status)').eq('user_id', u).inFilter('status', ['main', 'wait']));
      for (final r in rows) {
        final c = r.rec('cups');
        final at = DateTime.tryParse(c.s('starts_at'))?.toUtc();
        if (at == null) continue;
        await CupReminderService.i.sync(cupId: c.s('id'), name: c.s('name'), startsAt: at, eligible: c.s('status') == 'registration');
      }
    } catch (e) {
      debugPrint('NX cup reminders: $e');
    }
  }

  /// On start / sign-in: a pairing that is already ready (e.g. the app was reopened from the notification).
  Future<void> _catchUp() async {
    final u = Auth.i.uid;
    if (u == null || !supaReady) return;
    try {
      final rows = recs(await sb.from('cup_matches').select('id, cup_id, p1, p2, status').or('p1.eq.$u,p2.eq.$u').inFilter('status', ['ready', 'live']).limit(1));
      for (final r in rows) {
        onMatch(r.m);
      }
    } catch (_) {}
  }

  /// cup_matches changed for me: when it becomes ready, move me into it (the opponent's app does the same).
  void onMatch(Map<String, dynamic> row) {
    if (!cupShouldAutoEnter(row: row, uid: Auth.i.uid, entered: _entered, inCupRoom: CupUi.inCupRoom)) return;
    final id = '${row['id']}', cup = '${row['cup_id'] ?? ''}';
    _entered.add(id);
    final entry = 'cupmatch:$cup:$id';
    if (!_foreground) {
      unawaited(CupReminderService.i.showNow(id, 'مسابقه‌ی تورنمنت آماده است ⚽', 'بزن تا مستقیم وارد مسابقه شوی', entry));
      return;
    }
    // the open cup page enters by itself (same RPC); elsewhere in the app we take the player there now
    if (CupUi.openCup == cup) return;
    sfx(Snd.whistle);
    buzz('heavy');
    toast('مسابقه‌ات آماده است · ورود خودکار', 'ok');
    open?.call(entry);
  }

  /// Big card for what needs the player now; a toast for the rest.
  static const urgent = {'cup_ready', 'cup_soon', 'cup_match_soon', 'cup_draw', 'cup_promoted', 'cup_approved'};

  void handle(Map<String, dynamic> n) {
    final kind = '${n['kind'] ?? ''}';
    if (!kind.startsWith('cup_')) return;
    final data = n['data'] is Map ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
    final cup = '${data['cup'] ?? ''}', match = '${data['match'] ?? ''}';
    final title = '${n['title'] ?? ''}', body = n['body']?.toString();
    if (kind == 'cup_approved' || kind == 'cup_promoted') unawaited(syncReminders());
    final entry = kind == 'cup_ready' && match.isNotEmpty ? 'cupmatch:$cup:$match' : 'cup:$cup';
    if (!_foreground) {
      if (urgent.contains(kind) && cup.isNotEmpty) unawaited(CupReminderService.i.showNow('${n['id'] ?? kind}', title, body, entry));
      return;
    }
    // the cup page / cup room already on screen handles it itself
    if (CupUi.inCupRoom || (cup.isNotEmpty && CupUi.openCup == cup)) return;
    final ctx = navKey.currentContext;
    if (!urgent.contains(kind) || ctx == null || _showing || cup.isEmpty) {
      toast(title, kind == 'cup_out' || kind == 'cup_cancel' || kind == 'cup_rejected' ? 'err' : 'ok');
      return;
    }
    sfx(kind == 'cup_ready' ? Snd.whistle : Snd.ready);
    buzz('heavy');
    _showing = true;
    showCard(ctx, accent: kind == 'cup_ready' ? C.red : C.orange, child: (cc) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Pop(child: Icon(kind == 'cup_ready' ? Icons.sports_soccer_rounded : kind == 'cup_draw' ? Icons.casino_rounded : Icons.alarm_rounded, size: 40, color: kind == 'cup_ready' ? C.red : C.orange)),
            const SizedBox(height: 8),
            tTitle(title, size: 17, align: TextAlign.center),
            if (body != null && body.isNotEmpty) ...[const SizedBox(height: 6), T(body, size: 12, color: C.dim, align: TextAlign.center)],
            if (kind == 'cup_soon') ...[const SizedBox(height: 6), T('اعلام حضور تا ${faDigits('$kCupCheckinMinutes')} دقیقه‌ی دیگر بسته می‌شود', size: 11, color: C.orange, align: TextAlign.center)],
            const SizedBox(height: 14),
            Btn(kind == 'cup_ready' ? 'ورود به مسابقه' : kind == 'cup_soon' ? 'اعلام حضور' : 'رفتن به تورنمنت', colors: kind == 'cup_ready' ? G.red : G.gold, onTap: () {
              Navigator.pop(cc);
              open?.call(entry);
            }),
            const SizedBox(height: 8),
            Btn('بعداً', small: true, colors: G.dark, onTap: () => Navigator.pop(cc)),
          ]),
        )).whenComplete(() => _showing = false);
  }
}
