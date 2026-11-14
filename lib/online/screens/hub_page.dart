/// Online hub (port of the Godot app's src/online/hub.gd, the v3 online home):
/// create room + join by code, quick online match (1v1/2v2/3v3), shortcuts (arena, tournaments,
/// leaderboard / leagues, challenges, account), live room list (room_list, realtime `hub:rooms`,
/// 20 s poll) with one-tap Join / Watch. Guests are signed in anonymously on entry.
/// RPC: quick_match, join_room, create_room. Route: /online (?quick=1v1 runs a quick match).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/settings/app_settings.dart';
import '../../games/disc_football/core/data.dart' as df;
import '../online_core.dart';
import '../supabase_client.dart';
import '../ui/oui.dart';
import 'account_page.dart';

class OnlineHubPage extends StatefulWidget {
  const OnlineHubPage({super.key, this.quick = ''});
  final String quick;

  @override
  State<OnlineHubPage> createState() => _OnlineHubPageState();
}

class _OnlineHubPageState extends State<OnlineHubPage> {
  final OnlineCore core = OnlineCore.instance;
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  bool loaded = false;
  bool connected = false;
  String err = '';
  String filter = 'all';
  String busy = '';
  RealtimeChannel? ch;
  Timer? _debounce, _poll;
  bool _quickDone = false;
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _connect();
    WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowRecovery(context));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    final RealtimeChannel? c = ch;
    if (c != null && Online.ready) Online.client.removeChannel(c);
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      err = '';
      connected = false;
    });
    final String id = await core.ensure();
    if (!mounted) return;
    if (id.isEmpty) {
      setState(() => err = context.ot('m3.offline_hint'));
      return;
    }
    setState(() => connected = true);
    _startLive();
  }

  void _startLive() {
    _load();
    if (ch != null) return;
    core.loadDiscs();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    final RealtimeChannel c = Online.client.channel('hub:rooms');
    for (final String t in <String>['rooms', 'room_players']) {
      c.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => _soon());
    }
    c.subscribe();
    ch = c;
    if (widget.quick.isNotEmpty && !_quickDone) {
      _quickDone = true;
      _quick(widget.quick);
    }
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _load);
  }

  Future<void> _load() async {
    final OnlineResult r = await guard(() => Online.client.from('room_list').select().order('created_at', ascending: false).limit(60));
    if (!mounted) return;
    setState(() {
      if (!r.ok) {
        err = r.error;
      } else {
        err = '';
        rows = r.rows;
        loaded = true;
      }
    });
  }

  Future<void> _refresh() async {
    if (!connected) return _connect();
    await _load();
    if (mounted) otoast(context, context.ot('hub.updated'));
  }

  void _enter(Object? room) {
    final String rid = core.enterRoom(room);
    if (rid.isNotEmpty && mounted) context.push('/online/lobby/$rid');
  }

  Future<void> _act(String key, Future<OnlineResult> Function() fn) async {
    if (busy.isNotEmpty) return;
    if (!connected) {
      otoast(context, context.ot('m3.not_connected'), err: true);
      _connect();
      return;
    }
    setState(() => busy = key);
    final OnlineResult r = await fn();
    if (!mounted) {
      if (r.ok) core.enterRoom(r.data);
      return;
    }
    setState(() => busy = '');
    if (r.ok) {
      buzz('medium');
      _enter(r.data);
    } else {
      otoast(context, r.error, err: true);
      buzz('heavy');
    }
  }

  void _quick(String m) =>
      _act('quick$m', () => callRpc('quick_match', <String, dynamic>{'p_mode': m, 'p_kind': 'quick'}));

  void _join(String id, bool spectate) =>
      _act('${spectate ? 'w' : 'j'}$id', () => callRpc('join_room', <String, dynamic>{'p_room': id, 'p_spectate': spectate}));

  void _joinCode() {
    final String c = _code.text.trim().toUpperCase();
    if (c.length != 6) return otoast(context, context.ot('hub.the_room_code_has_6'), err: true);
    _act('code', () => callRpc('join_room', <String, dynamic>{'p_code': c}));
  }

  List<Map<String, dynamic>> get _filtered => filter == 'all' ? rows : rows.where((Map<String, dynamic> x) => os(x['mode']) == filter).toList();

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> data = loaded ? _filtered : <Map<String, dynamic>>[];
    final List<Widget> list = <Widget>[_header(context, data.length)];
    if (err.isNotEmpty) {
      list.add(OError(err, onRetry: connected ? _load : _connect));
    } else if (!loaded) {
      list.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: oSkeleton(4, 68)));
    } else if (data.isEmpty) {
      list.add(OEmpty(
        icon: Icons.sports_soccer_rounded,
        title: context.ot('hub.no_open_rooms_right_now'),
        sub: context.ot('hub.create_a_room_and_invite'),
        action: context.ot('hub.create_room'),
        onAction: _openCreate,
      ));
    } else {
      for (final Map<String, dynamic> it in data) {
        list.add(Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: _row(context, it)));
      }
    }
    list.add(const SizedBox(height: 40));
    return OPage(
      title: context.ot('hub.online'),
      en: 'ONLINE',
      onRefresh: _refresh,
      actions: <Widget>[
        IconButton(icon: const Icon(Icons.manage_accounts_rounded, color: OC.cyan), onPressed: () => context.push('/online/account')),
      ],
      body: RefreshIndicator(onRefresh: _refresh, child: ListView(children: list)),
    );
  }

  Widget _header(BuildContext context, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        ListenableBuilder(listenable: core, builder: (BuildContext context, _) => _profileCard(context)),
        const SizedBox(height: 10),
        OBtn(context.ot('hub.create_room'), onTap: _openCreate),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _code,
              maxLength: 6,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: OC.text, fontWeight: FontWeight.w900, letterSpacing: 4),
              onChanged: (String t) {
                final String clean = t.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                if (clean != t) {
                  _code.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
                }
              },
              onSubmitted: (_) => _joinCode(),
              decoration: InputDecoration(
                counterText: '',
                hintText: context.ot('hub.6_digit_code'),
                hintStyle: const TextStyle(color: OC.dim2, letterSpacing: 0, fontWeight: FontWeight.w600),
                filled: true,
                fillColor: const Color(0x22FFFFFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 96, child: OBtn(busy == 'code' ? '…' : context.ot('hub.join'), style: OBtnStyle.dark, onTap: _joinCode)),
        ]),
        oCap(context.ot('m3.quick_online')),
        Row(children: <Widget>[
          for (final String m in kModes) ...<Widget>[
            Expanded(
              child: OBtn(busy == 'quick$m' ? '…' : m.toUpperCase(),
                  small: true, style: OBtnStyle.violet, sub: modeLabel(context, m), onTap: busy.isNotEmpty ? null : () => _quick(m)),
            ),
            if (m != kModes.last) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          _chip(Icons.workspace_premium_rounded, context.ot('arena.arena'), OC.violet, '/online/arena'),
          _chip(Icons.emoji_events_rounded, context.ot('hub.tournament'), OC.orange, '/online/tournaments'),
          _chip(Icons.leaderboard_rounded, context.ot('hub.leaderboard'), OC.gold, '/online/ranks'),
          _chip(Icons.military_tech_rounded, context.ot('ranks.leagues'), OC.sky, '/online/ranks?tab=leagues'),
          _chip(Icons.event_available_rounded, context.ot('hub.challenges'), OC.green, '/online/challenges'),
        ]),
        const SizedBox(height: 14),
        Row(children: <Widget>[
          Text(context.ot('m3.rooms'), style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
          const Spacer(),
          if (loaded) Text(context.otf('hub.x_rooms', <Object>[context.fn(n)]), style: const TextStyle(color: OC.dim, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        OSegment<String>(
          items: <(String, String)>[('all', context.ot('challenges.all')), ('1v1', '1v1'), ('2v2', '2v2'), ('3v3', '3v3')],
          value: filter,
          onChanged: (String v) => setState(() => filter = v),
        ),
      ]),
    );
  }

  Widget _chip(IconData i, String label, Color c, String route) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xD90A102C), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .45))),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(i, color: c, size: 20),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: OC.text, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _profileCard(BuildContext context) {
    final Map<String, dynamic> p = core.profile;
    if (p.isEmpty) return const SizedBox.shrink();
    final ({int level, int cur, int need, double frac}) lp = lvl(p['xp']);
    return OPanel(
      accent: OC.gold,
      onTap: () => context.push('/online/ranks'),
      child: Row(children: <Widget>[
        OAvatar(disc: os(p['equipped_disc']).isNotEmpty ? p['equipped_disc'] : p['avatar'], url: p['avatar_url'], size: 52, ring: OC.gold),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Flexible(
                child: Text(os(p['username']),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              OBadge(context.otf('hub.level_x', <Object>[context.fn(oi(p['level'], 1))]), color: OC.gold),
            ]),
            const SizedBox(height: 6),
            OBar(lp.frac, color: OC.cyan, color2: OC.violet, h: 6),
            const SizedBox(height: 4),
            Text(context.otf('hub.x_x_xp_rating_x', <Object>[context.fn(lp.cur), context.fn(lp.need), context.fn(oi(p['rating']))]),
                style: const TextStyle(color: OC.dim, fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 8),
        leagueBadge(p['league'], 40),
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> it) {
    final String id = os(it['id']);
    final int players = oi(it['players']);
    final int cap = oi(it['capacity'], 2);
    final bool full = players >= cap;
    final bool playing = os(it['status']) == 'playing';
    final String kind = os(it['kind'], 'casual');
    final List<String> kf = kKindFa[kind] ?? kKindFa['casual']!;
    final bool canJoin = !playing && !full;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: OC.rowBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: OC.line)),
      child: Row(children: <Widget>[
        OAvatar(disc: it['host_avatar'], url: it['host_avatar_url'], size: 40, ring: playing ? OC.red : OC.cyan),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(os(it['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800)),
            Text(
              '${os(it['mode']).toUpperCase()} · ${context.tx(kf[0], kf[1])} · ${os(it['host_name'])}${playing ? ' · ${context.ot('hub.live')}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: playing ? OC.red : OC.dim, fontSize: 11),
            ),
          ]),
        ),
        SizedBox(
          width: 44,
          child: Text('${context.fn(players)}/${context.fn(cap)}',
              textAlign: TextAlign.center, style: TextStyle(color: full ? OC.orange : OC.text, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          width: 84,
          child: canJoin
              ? OBtn(busy == 'j$id' ? '…' : context.ot('hub.join'), small: true, onTap: busy.isNotEmpty ? null : () => _join(id, false))
              : OBtn(busy == 'w$id' ? '…' : context.ot('hub.watch'),
                  small: true, style: OBtnStyle.dark, onTap: busy.isNotEmpty ? null : () => _join(id, true)),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- create room sheet
  void _openCreate() {
    if (!connected) {
      otoast(context, context.ot('m3.not_connected'), err: true);
      _connect();
      return;
    }
    showOSheet<void>(
      context,
      title: context.ot('hub.create_room'),
      en: 'CREATE ROOM',
      accent: OC.green,
      builder: (BuildContext sc) => _CreateRoomSheet(onCreated: (Object? room) {
        Navigator.of(sc).pop();
        buzz('medium');
        _enter(room);
      }),
    );
  }
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet({required this.onCreated});
  final void Function(Object? room) onCreated;

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final TextEditingController _name = TextEditingController();
  String mode = '1v1';
  bool priv = false, ranked = true, voice = true;
  String rule = 'g3';
  int turn = 15;
  int field = 0;
  bool busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (busy) return;
    setState(() => busy = true);
    final String nm = _name.text.trim();
    final Map<String, dynamic> settings = ruleToSettings(rule)
      ..['field'] = field
      ..['turn'] = turn
      ..['ball'] = 0;
    final OnlineResult r = await callRpc('create_room', <String, dynamic>{
      'p_mode': mode,
      'p_name': nm.isNotEmpty ? nm : null,
      'p_private': priv,
      'p_ranked': ranked,
      'p_voice': voice,
      'p_settings': settings,
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (r.ok) {
      widget.onCreated(r.data);
    } else {
      otoast(context, r.error, err: true);
      buzz('heavy');
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          oCap(context.ot('hub.room_name')),
          TextField(
            controller: _name,
            maxLength: 40,
            style: const TextStyle(color: OC.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: context.ot('hub.e_g_galactic_final'),
              hintStyle: const TextStyle(color: OC.dim2),
              filled: true,
              fillColor: const Color(0x22FFFFFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          oCap(context.ot('hub.mode')),
          OSegment<String>(
            items: <(String, String)>[for (final String m in kModes) (m, modeLabel(context, m))],
            value: mode,
            onChanged: (String v) => setState(() => mode = v),
          ),
          oCap(context.ot('hub.rule')),
          OSegment<String>(
            items: <(String, String)>[for (final List<String> r in kRules) (r[0], context.tx(r[1], r[2]))],
            value: rule,
            accent: OC.violet,
            onChanged: (String v) => setState(() => rule = v),
          ),
          oCap(context.ot('hub.turn_time')),
          OSegment<int>(
            items: <(int, String)>[for (final List<Object> t in kTurns) (t[0] as int, context.tx('${t[1]}', '${t[2]}'))],
            value: turn,
            accent: OC.green,
            onChanged: (int v) => setState(() => turn = v),
          ),
          oCap(context.ot('hub.field')),
          FieldPicker(value: field, onChanged: (int i) => setState(() => field = i)),
          const SizedBox(height: 8),
          _opt(context.ot('hub.private'), context.ot('hub.join_only_with_the_room'), priv, (bool v) => setState(() => priv = v)),
          _opt(context.ot('hub.ranked'), context.ot('hub.affects_rating_and_league'), ranked, (bool v) => setState(() => ranked = v)),
          _opt(context.ot('hub.voice_chat'), context.ot('hub.players_can_talk_to_each'), voice, (bool v) => setState(() => voice = v)),
          const SizedBox(height: 14),
          OBtn(busy ? context.ot('hub.creating') : context.ot('hub.create_room'), style: OBtnStyle.green, busy: busy, onTap: _go),
        ]),
      );

  Widget _opt(String t, String s, bool v, ValueChanged<bool> f) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: v,
        onChanged: f,
        activeColor: OC.green,
        title: Text(t, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 14)),
        subtitle: Text(s, style: const TextStyle(color: OC.dim, fontSize: 11)),
      );
}

/// Horizontal field thumbnails (RN FieldPicker) — shared with the lobby settings.
class FieldPicker extends StatelessWidget {
  const FieldPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: df.kFields.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (BuildContext context, int k) {
            final bool on = k == value;
            final df.Field f = df.kFields[k];
            return GestureDetector(
              onTap: () {
                buzz('light');
                onChanged(k);
              },
              child: Container(
                width: 78,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: on ? OC.cyan.withValues(alpha: .12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: on ? OC.cyan : OC.line),
                ),
                child: Column(children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/games/disc_football/fields/${f.id}.webp',
                        fit: BoxFit.cover,
                        cacheWidth: 120,
                        errorBuilder: (_, __, ___) => Container(color: const Color(0xFF14532D)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? OC.text : OC.dim, fontSize: 10)),
                ]),
              ),
            );
          },
        ),
      );
}
