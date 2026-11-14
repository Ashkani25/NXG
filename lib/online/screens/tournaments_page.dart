/// Tournaments (port of the Godot app's src/online/tournaments.gd): list (registration / running /
/// finished) + create sheet, and the detail view with bracket (single / double elimination) or
/// standings (round robin / swiss / league), register / leave / start, organizer result override,
/// live updates, "your next match" → open_tournament_room → lobby.
/// Tables/RPC: tournaments (+ tournament_entries(count)), standings (view), tournament_matches;
/// rpc create_tournament, join_tournament, leave_tournament, start_tournament, open_tournament_room,
/// set_tournament_result; realtime tours:<status>, tour:<id>.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/settings/app_settings.dart';
import '../online_core.dart';
import '../supabase_client.dart';
import '../ui/oui.dart';

const Map<String, List<String>> kFormatFa = <String, List<String>>{
  'single_elim': <String>['حذفی تک', 'Single elimination'],
  'double_elim': <String>['حذفی دوگانه', 'Double elimination'],
  'round_robin': <String>['دوره‌ای', 'Round robin'],
  'swiss': <String>['سوئیسی', 'Swiss'],
  'league': <String>['لیگ', 'League'],
};
const Map<String, List<String>> _statusFa = <String, List<String>>{
  'registration': <String>['ثبت‌نام', 'Registration'],
  'running': <String>['در جریان', 'Running'],
  'finished': <String>['پایان‌یافته', 'Finished'],
};
const Map<String, Color> _statusCol = <String, Color>{'registration': OC.green, 'running': OC.orange, 'finished': OC.dim};

String _fmt(BuildContext c, String f) => kFormatFa[f] != null ? c.tx(kFormatFa[f]![0], kFormatFa[f]![1]) : f.replaceAll('_', ' ');
String _st(BuildContext c, String s) => c.tx((_statusFa[s] ?? _statusFa['registration']!)[0], (_statusFa[s] ?? _statusFa['registration']!)[1]);

RealtimeChannel _sub(String name, List<(String, String?)> tables, VoidCallback cb) {
  final RealtimeChannel ch = Online.client.channel(name);
  for (final (String, String?) t in tables) {
    final String? f = t.$2;
    if (f == null) {
      ch.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t.$1, callback: (_) => cb());
    } else {
      final List<String> kv = f.split('=');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t.$1,
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: kv[0], value: kv[1]),
        callback: (_) => cb(),
      );
    }
  }
  ch.subscribe();
  return ch;
}

// ================================================================ list
class OnlineTournamentsPage extends StatefulWidget {
  const OnlineTournamentsPage({super.key});

  @override
  State<OnlineTournamentsPage> createState() => _OnlineTournamentsPageState();
}

class _OnlineTournamentsPageState extends State<OnlineTournamentsPage> {
  String tab = 'registration';
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  bool loaded = false;
  String err = '';
  RealtimeChannel? ch;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    OnlineCore.instance.ensure().then((_) {
      if (!mounted) return;
      _load();
      _subList();
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    final RealtimeChannel? c = ch;
    if (c != null && Online.ready) Online.client.removeChannel(c);
    super.dispose();
  }

  void _subList() {
    if (!Online.ready) return;
    final RealtimeChannel? old = ch;
    if (old != null) Online.client.removeChannel(old);
    ch = _sub('tours:$tab', <(String, String?)>[('tournaments', null), ('tournament_entries', null)], () {
      _deb?.cancel();
      _deb = Timer(const Duration(milliseconds: 500), _load);
    });
  }

  Future<void> _load() async {
    final String want = tab;
    final OnlineResult r = await guard(() => Online.client
        .from('tournaments')
        .select('*,entries:tournament_entries(count)')
        .eq('status', want)
        .order('created_at', ascending: false)
        .limit(50));
    if (!mounted || want != tab) return;
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

  void _openCreate() {
    showOSheet<void>(
      context,
      title: context.ot('tournaments.create_tournament'),
      en: 'NEW TOURNAMENT',
      accent: OC.orange,
      builder: (BuildContext sc) => _CreateTournamentSheet(onCreated: (String id) {
        Navigator.of(sc).pop();
        if (id.isNotEmpty) context.push('/online/tournaments/$id');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool reg = tab == 'registration';
    final List<Widget> out = <Widget>[
      OSegment<String>(
        items: <(String, String)>[
          ('registration', context.ot('tournaments.sign_up')),
          ('running', context.ot('challenges.in_progress')),
          ('finished', context.ot('tournaments.finished')),
        ],
        value: tab,
        accent: OC.orange,
        onChanged: (String v) {
          setState(() {
            tab = v;
            loaded = false;
            rows = <Map<String, dynamic>>[];
          });
          _load();
          _subList();
        },
      ),
      const SizedBox(height: 10),
    ];
    if (err.isNotEmpty) {
      out.add(OError(err, onRetry: _load));
    } else if (!loaded) {
      out.add(oSkeleton(4, 92));
    } else if (rows.isEmpty) {
      out.add(OEmpty(
        icon: Icons.emoji_events_rounded,
        title: context.ot('tournaments.no_tournaments_in_this_section'),
        sub: reg ? context.ot('tournaments.create_the_first_tournament_yourself') : '',
        action: reg ? context.ot('tournaments.create_tournament') : '',
        onAction: reg ? _openCreate : null,
      ));
    } else {
      for (final Map<String, dynamic> it in rows) {
        out.add(_row(context, it));
      }
    }
    return OPage(
      title: context.ot('tournaments.tournaments'),
      en: 'TOURNAMENTS',
      accent: OC.orange,
      onRefresh: _load,
      actions: <Widget>[IconButton(icon: const Icon(Icons.add_circle_rounded, color: OC.green), onPressed: _openCreate)],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: out),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> it) {
    final String status = os(it['status']);
    final Color sc = _statusCol[status] ?? OC.green;
    final List<dynamic> en = oa(it['entries']);
    final int cnt = en.isNotEmpty ? oi(om(en.first)['count']) : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => context.push('/online/tournaments/${os(it['id'])}'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: OC.rowBg, borderRadius: BorderRadius.circular(22), border: Border.all(color: sc.withValues(alpha: .55), width: 1.5)),
          child: Row(children: <Widget>[
            Icon(status == 'finished' ? Icons.military_tech_rounded : Icons.emoji_events_rounded, color: OC.gold, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(os(it['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
                  if (os(it['format']).isNotEmpty) OBadge(_fmt(context, os(it['format'])), color: OC.violet),
                  OBadge(os(it['mode']).toUpperCase(), color: OC.sky),
                  OBadge(_st(context, status), color: sc, live: status == 'running'),
                ]),
              ]),
            ),
            SizedBox(
              width: 64,
              child: Column(children: <Widget>[
                Text('${context.fn(cnt)}/${context.fn(oi(it['max_entries']))}', style: const TextStyle(color: OC.text, fontWeight: FontWeight.w900, fontSize: 16)),
                Text('💎 ${context.fn(oi(it['prize_gems']))}', style: const TextStyle(color: OC.gem, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CreateTournamentSheet extends StatefulWidget {
  const _CreateTournamentSheet({required this.onCreated});
  final void Function(String id) onCreated;

  @override
  State<_CreateTournamentSheet> createState() => _CreateTournamentSheetState();
}

class _CreateTournamentSheetState extends State<_CreateTournamentSheet> {
  final TextEditingController _name = TextEditingController();
  String format = 'single_elim';
  String mode = '1v1';
  int max = 8, rounds = 2, gems = 20, minLv = 1;
  bool busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final String nm = _name.text.trim();
    if (nm.length < 3) return otoast(context, context.ot('tournaments.tournament_name_must_be_at'), err: true);
    setState(() => busy = true);
    final bool rr = format == 'league' || format == 'swiss';
    final OnlineResult r = await callRpc('create_tournament', <String, dynamic>{
      'p_name': nm,
      'p_format': format,
      'p_mode': mode,
      'p_max': max,
      'p_rounds': rr ? rounds : null,
      'p_prize_gems': gems,
      'p_starts': null,
      'p_min_level': minLv,
    });
    if (!mounted) return;
    setState(() => busy = false);
    if (r.ok) {
      buzz('success');
      otoast(context, context.ot('tournaments.tournament_created'));
      final Object? d = r.data;
      widget.onCreated(os(om(d is List && d.isNotEmpty ? d.first : d)['id']));
    } else {
      otoast(context, r.error, err: true);
    }
  }

  List<(int, String)> _nums(List<int> v) => <(int, String)>[for (final int x in v) (x, context.fn(x))];

  @override
  Widget build(BuildContext context) {
    final bool rr = format == 'league' || format == 'swiss';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        oCap(context.ot('tournaments.tournament_name')),
        TextField(
          controller: _name,
          maxLength: 40,
          style: const TextStyle(color: OC.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: context.ot('tournaments.galaxy_cup'),
            hintStyle: const TextStyle(color: OC.dim2),
            filled: true,
            fillColor: const Color(0x22FFFFFF),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        oCap(context.ot('tournaments.format')),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final String f in kFormatFa.keys)
            ChoiceChip(
              label: Text(_fmt(context, f)),
              selected: format == f,
              selectedColor: OC.violet.withValues(alpha: .3),
              backgroundColor: const Color(0xB3080C22),
              labelStyle: TextStyle(color: format == f ? Colors.white : OC.dim, fontWeight: FontWeight.w700),
              onSelected: (_) => setState(() {
                format = f;
                if (f == 'swiss' && rounds < 3) rounds = 3;
                if (f == 'league' && rounds > 3) rounds = 2;
              }),
            ),
        ]),
        oCap(context.ot('hub.mode')),
        OSegment<String>(
          items: const <(String, String)>[('1v1', '1v1'), ('2v2', '2v2'), ('3v3', '3v3')],
          value: mode,
          onChanged: (String v) => setState(() => mode = v),
        ),
        oCap(context.ot('tournaments.capacity')),
        OSegment<int>(items: _nums(<int>[4, 8, 16, 32, 64]), value: max, accent: OC.orange, onChanged: (int v) => setState(() => max = v)),
        if (rr) ...<Widget>[
          oCap(format == 'league' ? context.ot('tournaments.number_of_home_and_away') : context.ot('tournaments.number_of_rounds')),
          OSegment<int>(
            items: format == 'league'
                ? <(int, String)>[(1, context.ot('tournaments.one')), (2, context.ot('tournaments.two')), (3, context.ot('tournaments.three'))]
                : _nums(<int>[3, 4, 5, 6]),
            value: rounds,
            accent: OC.violet,
            onChanged: (int v) => setState(() => rounds = v),
          ),
        ],
        oCap(context.ot('tournaments.champion_prize_gems_runner_up')),
        OSegment<int>(items: _nums(<int>[0, 10, 20, 30]), value: gems, accent: OC.sky, onChanged: (int v) => setState(() => gems = v)),
        oCap(context.ot('tournaments.minimum_level')),
        OSegment<int>(items: _nums(<int>[1, 3, 5, 10]), value: minLv, accent: OC.green, onChanged: (int v) => setState(() => minLv = v)),
        const SizedBox(height: 16),
        OBtn(busy ? context.ot('hub.creating') : context.ot('tournaments.create_tournament'), style: OBtnStyle.gold, busy: busy, onTap: _go),
      ]),
    );
  }
}

// ================================================================ detail
class OnlineTournamentDetailPage extends StatefulWidget {
  const OnlineTournamentDetailPage({super.key, required this.id});
  final String id;

  @override
  State<OnlineTournamentDetailPage> createState() => _OnlineTournamentDetailPageState();
}

class _OnlineTournamentDetailPageState extends State<OnlineTournamentDetailPage> {
  final OnlineCore core = OnlineCore.instance;
  Map<String, dynamic> t = <String, dynamic>{};
  List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> matches = <Map<String, dynamic>>[];
  Map<String, String> names = <String, String>{};
  String err = '';
  String dtab = 'board';
  String busy = '';
  final TextEditingController _team = TextEditingController();
  RealtimeChannel? ch;
  Timer? _deb;

  String get tid => widget.id;

  @override
  void initState() {
    super.initState();
    core.ensure().then((_) {
      if (!mounted || !Online.ready) return;
      _load();
      void soon() {
        _deb?.cancel();
        _deb = Timer(const Duration(milliseconds: 300), _load);
      }

      ch = _sub('tour:$tid', <(String, String?)>[
        ('tournaments', 'id=$tid'),
        ('tournament_entries', 'tournament_id=$tid'),
        ('tournament_matches', 'tournament_id=$tid'),
      ], soon);
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _team.dispose();
    final RealtimeChannel? c = ch;
    if (c != null && Online.ready) Online.client.removeChannel(c);
    super.dispose();
  }

  Future<void> _load() async {
    final OnlineResult a = await guard(() => Online.client.from('tournaments').select().eq('id', tid));
    final OnlineResult b = await guard(() => Online.client.from('standings').select().eq('tournament_id', tid).order('pos'));
    final OnlineResult c = await guard(() => Online.client.from('tournament_matches').select().eq('tournament_id', tid).order('round').order('idx'));
    if (!mounted) return;
    setState(() {
      if (!a.ok || !b.ok || !c.ok) {
        err = !a.ok ? a.error : (!b.ok ? b.error : c.error);
        return;
      }
      if (a.rows.isEmpty) {
        err = context.ot('tournaments.tournament_not_found');
        return;
      }
      err = '';
      t = a.rows.first;
      entries = b.rows;
      matches = c.rows;
      names = <String, String>{for (final Map<String, dynamic> e in entries) os(e['id']): os(e['team_name'])};
    });
  }

  Map<String, dynamic> get _mine {
    final String u = core.uid;
    if (u.isEmpty) return <String, dynamic>{};
    for (final Map<String, dynamic> e in entries) {
      if (oa(e['members']).map((dynamic x) => '$x').contains(u)) return e;
    }
    return <String, dynamic>{};
  }

  bool get _elim => os(t['format']) == 'single_elim' || os(t['format']) == 'double_elim';

  Future<void> _run(String k, String fn, Map<String, dynamic> args, [String okMsg = '']) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = k);
    final OnlineResult r = await callRpc(fn, args);
    if (!mounted) return;
    setState(() => busy = '');
    if (r.ok) {
      if (okMsg.isNotEmpty) {
        otoast(context, okMsg);
        buzz('success');
      }
      await _load();
    } else {
      otoast(context, r.error, err: true);
      buzz('heavy');
    }
  }

  Future<void> _openRoom(String tmId) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = 'room');
    final OnlineResult r = await callRpc('open_tournament_room', <String, dynamic>{'p_tm': tmId});
    if (!mounted) return;
    setState(() => busy = '');
    if (r.ok) {
      final String rid = core.enterRoom(r.data);
      if (rid.isNotEmpty) context.push('/online/lobby/$rid');
    } else {
      otoast(context, r.error, err: true);
    }
  }

  String _roundLabel(BuildContext c, int rnd, int total) {
    switch (total - rnd) {
      case 0:
        return c.ot('tournaments.final');
      case 1:
        return c.ot('tournaments.semi_final');
      case 2:
        return c.ot('tournaments.quarter_final');
      case 3:
        return c.ot('tournaments.round_of_16');
      case 4:
        return c.ot('tournaments.round_of_32');
    }
    return c.otf('tournaments.round_x', <Object>[c.fn(rnd)]);
  }

  String _n(BuildContext c, Object? e) => names[os(e)] ?? c.ot('tournaments.sym');

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (t.isEmpty) {
      body = err.isNotEmpty ? OError(err, onRetry: _load) : oSpinner(36);
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: _detail(context));
    }
    return OPage(title: t.isEmpty ? context.ot('hub.tournament') : os(t['name']), en: 'TOURNAMENT', accent: OC.orange, onRefresh: _load, body: body);
  }

  List<Widget> _detail(BuildContext context) {
    final Map<String, dynamic> me = _mine;
    final String myId = os(me['id']);
    final bool isOrg = core.uid.isNotEmpty && os(t['created_by']) == core.uid;
    final String status = os(t['status']);
    final Color sc = _statusCol[status] ?? OC.green;
    Map<String, dynamic> next = <String, dynamic>{};
    if (myId.isNotEmpty) {
      for (final Map<String, dynamic> m in matches) {
        final String s = os(m['status']);
        if ((s == 'ready' || s == 'live') && (os(m['entry_a']) == myId || os(m['entry_b']) == myId)) {
          next = m;
          break;
        }
      }
    }
    final String w = os(t['winner_entry']);
    final List<Widget> out = <Widget>[
      OPanel(
        accent: sc,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
            OBadge(_st(context, status), color: sc, live: status == 'running'),
            OBadge(context.otf('tournaments.x_x_players', <Object>[context.fn(entries.length), context.fn(oi(t['max_entries']))]), color: OC.sky),
            OBadge(context.otf('tournaments.x_champion', <Object>[context.fn(oi(t['prize_gems']))]), color: OC.gem),
            OBadge('${context.fn(oi(t['prize_xp']))} XP', color: OC.cyan),
            OBadge('${_fmt(context, os(t['format']))} · ${os(t['mode']).toUpperCase()}', color: OC.violet),
            if (oi(t['min_level'], 1) > 1) OBadge(context.otf('tournaments.min_level_x', <Object>[context.fn(oi(t['min_level']))]), color: OC.green),
            if (status != 'registration' && oi(t['current_round']) > 0)
              OBadge(context.otf('tournaments.round_x', <Object>[context.fn(oi(t['current_round']))]), color: OC.violet),
          ]),
          if (w.isNotEmpty && names.containsKey(w)) ...<Widget>[
            const SizedBox(height: 8),
            Row(children: <Widget>[
              const Icon(Icons.emoji_events_rounded, color: OC.gold, size: 40),
              const SizedBox(width: 8),
              Expanded(child: Text(context.otf('tournaments.champion_x', <Object>[names[w] ?? '']), style: const TextStyle(color: OC.gold, fontSize: 16, fontWeight: FontWeight.w900))),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 10),
    ];
    if (status == 'registration') {
      if (myId.isNotEmpty) {
        out.add(OBtn(busy == 'leave' ? '…' : context.ot('tournaments.leave_tournament'),
            small: true,
            style: OBtnStyle.dark,
            onTap: () => _run('leave', 'leave_tournament', <String, dynamic>{'p_tid': tid}, context.ot('tournaments.you_left_the_tournament'))));
      } else if (entries.length < oi(t['max_entries'])) {
        if (os(t['mode']) != '1v1') {
          out.add(TextField(
            controller: _team,
            maxLength: 24,
            style: const TextStyle(color: OC.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: context.ot('tournaments.team_name_optional'),
              hintStyle: const TextStyle(color: OC.dim2),
              filled: true,
              fillColor: const Color(0x22FFFFFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ));
          out.add(const SizedBox(height: 8));
        }
        out.add(OBtn(busy == 'join' ? '…' : context.ot('tournaments.sign_up'), style: OBtnStyle.green, onTap: () {
          final String tn = _team.text.trim();
          _run('join', 'join_tournament', <String, dynamic>{'p_tid': tid, 'p_team_name': tn.isNotEmpty ? tn : null, 'p_members': null},
              context.ot('tournaments.you_re_signed_up'));
        }));
      } else {
        out.add(Text(context.ot('tournaments.tournament_is_full'), textAlign: TextAlign.center, style: const TextStyle(color: OC.orange)));
      }
      if (isOrg) {
        out.add(const SizedBox(height: 8));
        out.add(OBtn(
          busy == 'start' ? '…' : context.otf('tournaments.start_tournament_x_players', <Object>[context.fn(entries.length)]),
          style: OBtnStyle.gold,
          onTap: entries.length < 2 ? null : () => _run('start', 'start_tournament', <String, dynamic>{'p_tid': tid}, context.ot('tournaments.tournament_started')),
        ));
      }
    }
    if (next.isNotEmpty) {
      final String nid = os(next['id']);
      out.add(const SizedBox(height: 10));
      out.add(OPanel(
        accent: OC.red,
        glow: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(context.ot('tournaments.your_next_match'), style: const TextStyle(color: OC.red, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 4),
          Text('${_n(context, next['entry_a'])}  vs  ${_n(context, next['entry_b'])}',
              textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          OBtn(busy == 'room' ? '…' : context.ot('tournaments.enter_match'), style: OBtnStyle.red, onTap: () => _openRoom(nid)),
        ]),
      ));
    }
    out.add(const SizedBox(height: 10));
    out.add(OSegment<String>(
      items: <(String, String)>[
        ('board', _elim ? context.ot('tournaments.bracket') : context.ot('tournaments.table')),
        ('entries', context.ot('tournaments.participants')),
      ],
      value: dtab,
      accent: OC.orange,
      onChanged: (String v) => setState(() => dtab = v),
    ));
    out.add(const SizedBox(height: 10));
    if (dtab == 'entries') {
      if (entries.isEmpty) out.add(OEmpty(icon: Icons.sports_soccer_rounded, title: context.ot('tournaments.no_one_has_signed_up')));
      for (final Map<String, dynamic> e in entries) {
        out.add(Container(
          height: 48,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: OC.rowBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: OC.line)),
          child: Row(children: <Widget>[
            SizedBox(width: 36, child: Text(e['seed'] != null ? '#${context.fn(oi(e['seed']))}' : '•', style: const TextStyle(color: OC.dim, fontWeight: FontWeight.w800))),
            Expanded(child: Text(os(e['team_name']), style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800))),
            if (e['eliminated'] == true)
              OBadge(context.ot('tournaments.out'), color: OC.red)
            else if (oi(e['final_rank']) == 1)
              OBadge(context.ot('data.champion'), color: OC.gold),
          ]),
        ));
      }
    } else if (status == 'registration') {
      out.add(OEmpty(icon: Icons.event_rounded, title: context.ot('tournaments.the_bracket_is_created_once'), sub: context.ot('tournaments.the_organizer_starts_the_tournament')));
    } else if (_elim) {
      out.addAll(_bracket(context, myId, isOrg));
    } else {
      out.addAll(_standings(context, myId, isOrg));
    }
    return out;
  }

  // ---------------------------------------------------------------- bracket
  List<Widget> _bracket(BuildContext context, String myId, bool isOrg) {
    final List<(String, String)> sections = os(t['format']) == 'double_elim'
        ? <(String, String)>[
            (context.ot('tournaments.winners_bracket'), 'winners'),
            (context.ot('tournaments.losers_bracket'), 'losers'),
            (context.ot('tournaments.grand_final'), 'final'),
          ]
        : <(String, String)>[('', 'main')];
    final List<Widget> out = <Widget>[];
    for (final (String, String) s in sections) {
      final List<Map<String, dynamic>> ms = matches.where((Map<String, dynamic> m) => os(m['bracket']) == s.$2).toList();
      if (ms.isEmpty) continue;
      final bool labels = os(t['format']) != 'double_elim' || s.$2 == 'winners';
      if (s.$1.isNotEmpty) out.add(Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(s.$1, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800))));
      out.add(_section(context, ms, myId, isOrg, labels));
    }
    return out;
  }

  Widget _section(BuildContext context, List<Map<String, dynamic>> ms, String myId, bool isOrg, bool labels) {
    final Map<int, List<Map<String, dynamic>>> byRound = <int, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> m in ms) {
      byRound.putIfAbsent(oi(m['round']), () => <Map<String, dynamic>>[]).add(m);
    }
    final List<int> keys = byRound.keys.toList()..sort();
    final List<List<Map<String, dynamic>>> rounds = <List<Map<String, dynamic>>>[
      for (final int k in keys) byRound[k]!..sort((Map<String, dynamic> a, Map<String, dynamic> b) => oi(a['idx']).compareTo(oi(b['idx'])))
    ];
    const double bw = 168, bh = 64, gap = 14, cg = 28, labH = 24;
    final int total = rounds.length;
    final int firstN = rounds.first.isEmpty ? 1 : rounds.first.length;
    final double h = (firstN * (bh + gap)) < (bh + gap) ? (bh + gap) : firstN * (bh + gap);
    final List<Widget> kids = <Widget>[];
    final List<(Offset, Offset)> lines = <(Offset, Offset)>[];
    for (int ri = 0; ri < total; ri++) {
      final List<Map<String, dynamic>> col = rounds[ri];
      final double x = ri * (bw + cg);
      kids.add(Positioned(
        left: x,
        top: 0,
        width: bw,
        height: labH,
        child: Text(labels ? _roundLabel(context, ri + 1, total) : context.otf('tournaments.round_x', <Object>[context.fn(ri + 1)]),
            textAlign: TextAlign.center, style: const TextStyle(color: OC.cyan, fontSize: 11, fontWeight: FontWeight.w800)),
      ));
      final double slotH = h / col.length;
      for (int i = 0; i < col.length; i++) {
        final Map<String, dynamic> m = col[i];
        final double top = labH + i * slotH + (slotH - bh) / 2;
        final bool mine = myId.isNotEmpty && (os(m['entry_a']) == myId || os(m['entry_b']) == myId);
        final String stt = os(m['status']);
        Widget box = _matchBox(context, m, mine);
        if (isOrg && (stt == 'ready' || stt == 'live')) box = GestureDetector(onTap: () => _override(m), child: box);
        kids.add(Positioned(left: x, top: top, width: bw, height: bh, child: box));
        if (ri < total - 1) {
          final double cy = top + bh / 2;
          lines.add((Offset(x + bw, cy), Offset(x + bw + cg / 2, cy)));
          final double vy0 = i.isEven ? cy : cy - slotH / 2;
          lines.add((Offset(x + bw + cg / 2, vy0), Offset(x + bw + cg / 2, vy0 + slotH / 2)));
          if (i.isEven) lines.add((Offset(x + bw + cg / 2, cy + slotH / 2), Offset(x + bw + cg, cy + slotH / 2)));
        }
      }
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total * (bw + cg),
          height: h + labH + 8,
          child: CustomPaint(painter: _LinesPainter(lines), child: Stack(children: kids)),
        ),
      ),
    );
  }

  Widget _matchBox(BuildContext context, Map<String, dynamic> m, bool mine) {
    final String stt = os(m['status']);
    final bool live = stt == 'live';
    final bool done = stt == 'done' || stt == 'bye';
    return Opacity(
      opacity: done ? .9 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF20A102C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: live ? OC.red : (mine ? OC.cyan : OC.line)),
        ),
        child: Column(children: <Widget>[
          Expanded(child: _side(context, m, 'entry_a', 'score_a')),
          Container(height: 1, color: OC.line),
          Expanded(child: _side(context, m, 'entry_b', 'score_b')),
        ]),
      ),
    );
  }

  Widget _side(BuildContext context, Map<String, dynamic> m, String ek, String sk) {
    final String e = os(m[ek]);
    final bool win = e.isNotEmpty && os(m['winner_entry']) == e;
    final String stt = os(m['status']);
    final Object? sc = m[sk];
    final String nm = e.isNotEmpty ? (names[e] ?? '…') : (stt == 'bye' ? context.ot('tournaments.bye') : '—');
    return Container(
      color: win ? const Color(0x24FFD257) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: <Widget>[
        SizedBox(
          width: 22,
          child: Text(sc != null ? context.fn(oi(sc)) : (stt == 'bye' && e.isNotEmpty ? '–' : ''),
              textAlign: TextAlign.center, style: TextStyle(color: win ? OC.gold : OC.dim, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(nm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: e.isNotEmpty ? (win ? OC.gold : OC.text) : OC.dim2, fontSize: 12, fontWeight: win ? FontWeight.w900 : FontWeight.w500)),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- standings
  List<Widget> _standings(BuildContext context, String myId, bool isOrg) {
    final List<String> heads = <String>[
      '#',
      context.ot('tournaments.team'),
      context.ot('tournaments.match'),
      context.ot('tournaments.w'),
      context.ot('tournaments.d'),
      context.ot('tournaments.l'),
      context.ot('tournaments.goals'),
      context.ot('online_result.rating'),
    ];
    Widget cell(int k, String v, {bool head = false}) {
      final TextStyle s = TextStyle(
        color: head ? OC.dim : (k == 7 ? OC.gold : OC.text),
        fontSize: 12,
        fontWeight: head || k == 1 || k == 7 ? FontWeight.w800 : FontWeight.w500,
      );
      if (k == 1) return Expanded(child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: s));
      return SizedBox(width: k == 6 ? 44 : (k == 7 ? 40 : 30), child: Text(v, textAlign: TextAlign.center, style: s));
    }

    final List<Widget> out = <Widget>[
      SizedBox(height: 40, child: Row(children: <Widget>[for (int k = 0; k < heads.length; k++) cell(k, heads[k], head: true)])),
      Container(height: 1, color: OC.line),
    ];
    for (final Map<String, dynamic> e in entries) {
      final List<String> vals = <String>[
        context.fn(oi(e['pos'])),
        os(e['team_name']),
        context.fn(oi(e['played'])),
        context.fn(oi(e['wins'])),
        context.fn(oi(e['draws'])),
        context.fn(oi(e['losses'])),
        '${context.fn(oi(e['gf']))}:${context.fn(oi(e['ga']))}',
        context.fn(oi(e['points'])),
      ];
      out.add(Container(
        height: 40,
        decoration: BoxDecoration(color: os(e['id']) == myId ? OC.cyan.withValues(alpha: .1) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(children: <Widget>[for (int k = 0; k < vals.length; k++) cell(k, vals[k])]),
      ));
    }
    final List<Map<String, dynamic>> open = matches.where((Map<String, dynamic> m) => os(m['status']) == 'ready' || os(m['status']) == 'live').toList();
    if (open.isEmpty) return out;
    out.add(oSection(context.ot('tournaments.open_tournaments')));
    for (final Map<String, dynamic> m in open) {
      final bool mine = myId.isNotEmpty && (os(m['entry_a']) == myId || os(m['entry_b']) == myId);
      out.add(InkWell(
        onTap: isOrg ? () => _override(m) : null,
        child: Container(
          height: 48,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: OC.rowBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: mine ? OC.cyan : OC.line)),
          child: Row(children: <Widget>[
            OBadge(context.otf('tournaments.round_x', <Object>[context.fn(oi(m['round']))]), color: OC.violet),
            const SizedBox(width: 8),
            Expanded(child: Text('${_n(context, m['entry_a'])}  vs  ${_n(context, m['entry_b'])}', style: const TextStyle(color: OC.text, fontSize: 12))),
            if (os(m['status']) == 'live') OBadge(context.ot('hub.live'), color: OC.red, live: true),
          ]),
        ),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------- organizer override
  void _override(Map<String, dynamic> m) {
    final List<int> sc = <int>[0, 0];
    final String mid = os(m['id']);
    showDialog<void>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, StateSetter set) => AlertDialog(
          backgroundColor: const Color(0xF50A0F2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: OC.gold)),
          title: Text(context.ot('tournaments.result_entry_by_the_organizer'), textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            for (int side = 0; side < 2; side++)
              Row(children: <Widget>[
                Expanded(child: Text(_n(context, m[side == 0 ? 'entry_a' : 'entry_b']), style: const TextStyle(color: OC.text))),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: OC.text),
                  onPressed: () => set(() => sc[side] = sc[side] > 0 ? sc[side] - 1 : 0),
                ),
                SizedBox(width: 36, child: Text(context.fn(sc[side]), textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 22, fontWeight: FontWeight.w900))),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: OC.text),
                  onPressed: () => set(() => sc[side] = sc[side] < 30 ? sc[side] + 1 : 30),
                ),
              ]),
            const SizedBox(height: 12),
            OBtn(context.ot('tournaments.submit'), style: OBtnStyle.gold, onTap: () {
              Navigator.of(c).pop();
              _run('ovr', 'set_tournament_result', <String, dynamic>{'p_tm': mid, 'p_sa': sc[0], 'p_sb': sc[1]}, context.ot('tournaments.result_saved'));
            }),
            const SizedBox(height: 8),
            OBtn(context.ot('nav.cancel'), small: true, style: OBtnStyle.dark, onTap: () => Navigator.of(c).pop()),
          ]),
        ),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines);
  final List<(Offset, Offset)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0x7378C8FF)
      ..strokeWidth = 2;
    for (final (Offset, Offset) l in lines) {
      canvas.drawLine(l.$1, l.$2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.lines != lines;
}
