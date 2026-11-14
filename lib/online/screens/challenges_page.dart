/// Daily challenges (4 per Tehran day): progress, claim, reset countdown (port of the Godot app's
/// src/online/challenges.gd). Also [loadChallenges] / [claimChallenge] and [ChallengesHomeCard]
/// (RN HomeChallenges) for other areas. RPC get_daily_challenges, claim_challenge(p_def);
/// table challenge_defs; realtime user_challenges (channel uc:<uid>).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../online_core.dart';
import '../supabase_client.dart';
import '../ui/oui.dart';

final Map<String, Map<String, dynamic>> _defsCache = <String, Map<String, dynamic>>{};

/// seconds to the next midnight in Asia/Tehran (UTC+03:30, no DST)
double secondsToTehranMidnight([double? now]) {
  final double t = now ?? nowS();
  const double off = 3.5 * 3600, day = 86400;
  return ((t + off + 0.001) / day).ceil() * day - off - t;
}

/// (ok, list, error)
Future<(bool, List<Map<String, dynamic>>, String)> loadChallenges() async {
  final OnlineResult r = await callRpc('get_daily_challenges');
  if (!r.ok) return (false, <Map<String, dynamic>>[], r.error);
  if (_defsCache.isEmpty) {
    final OnlineResult d = await guard(() => Online.client.from('challenge_defs').select());
    for (final Map<String, dynamic> x in d.rows) {
      _defsCache[os(x['id'])] = x;
    }
  }
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> row in r.rows) {
    final String did = os(row['def_id']);
    final Map<String, dynamic> def = _defsCache[did] ?? <String, dynamic>{'title_fa': did, 'target': 1, 'reward_gems': 0, 'reward_xp': 0};
    out.add(<String, dynamic>{
      ...row,
      ...def,
      'def_id': did,
      'progress': oi(row['progress']),
      'claimed': row['claimed'] == true,
    });
  }
  return (true, out, '');
}

/// (ok, gems, xp, error)
Future<(bool, int, int, String)> claimChallenge(String defId) async {
  final OnlineResult r = await callRpc('claim_challenge', <String, dynamic>{'p_def': defId});
  if (!r.ok) return (false, 0, 0, r.error);
  return (true, oi(r.map['gems']), oi(r.map['xp']), '');
}

class OnlineChallengesPage extends StatefulWidget {
  const OnlineChallengesPage({super.key});

  @override
  State<OnlineChallengesPage> createState() => _OnlineChallengesPageState();
}

class _OnlineChallengesPageState extends State<OnlineChallengesPage> {
  List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
  bool loaded = false;
  String err = '';
  RealtimeChannel? ch;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    final RealtimeChannel? c = ch;
    if (c != null && Online.ready) Online.client.removeChannel(c);
    super.dispose();
  }

  Future<void> _start() async {
    final String u = await OnlineCore.instance.ensure();
    if (!mounted) return;
    if (u.isEmpty) return setState(() => err = context.ot('challenges.sign_in_first'));
    _load();
    final RealtimeChannel c = Online.client.channel('uc:$u');
    c.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_challenges',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: u),
      callback: (_) => _load(),
    );
    c.subscribe();
    ch = c;
  }

  Future<void> _load() async {
    final (bool, List<Map<String, dynamic>>, String) r = await loadChallenges();
    if (!mounted) return;
    setState(() {
      if (r.$1) {
        list = r.$2;
        loaded = true;
        err = '';
      } else {
        err = r.$3;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> out = <Widget>[
      OPanel(
        accent: OC.green,
        child: Row(children: <Widget>[
          const Icon(Icons.event_available_rounded, size: 44, color: OC.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.ot('challenges.today_s_challenges'), style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
              OTicker(
                every: const Duration(seconds: 1),
                builder: (BuildContext c) {
                  final double left = secondsToTehranMidnight();
                  return Text(
                    c.otf('challenges.refreshes_in_x_x_x', <Object>[c.fn((left / 3600).floor()), pad2(c, ((left % 3600) / 60).floor()), pad2(c, (left % 60).floor())]),
                    style: const TextStyle(color: OC.dim, fontSize: 11),
                  );
                },
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
    ];
    if (err.isNotEmpty) {
      out.add(OError(err, onRetry: _load));
    } else if (!loaded) {
      out.add(oSkeleton(4, 96));
    } else if (list.isEmpty) {
      out.add(OEmpty(icon: Icons.sports_soccer_rounded, title: context.ot('challenges.no_challenges_today')));
    } else {
      for (final Map<String, dynamic> c in list) {
        out.add(ChallengeCard(c: c, onClaimed: () => setState(() => c['claimed'] = true)));
      }
    }
    return OPage(
      title: context.ot('challenges.daily_challenges'),
      en: 'DAILY CHALLENGES',
      accent: OC.green,
      onRefresh: _load,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: out),
    );
  }
}

/// RN ChallengeCard.
class ChallengeCard extends StatefulWidget {
  const ChallengeCard({super.key, required this.c, this.compact = false, required this.onClaimed});
  final Map<String, dynamic> c;
  final bool compact;
  final VoidCallback onClaimed;

  @override
  State<ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<ChallengeCard> {
  bool busy = false;

  Future<void> _claim() async {
    setState(() => busy = true);
    final (bool, int, int, String) r = await claimChallenge(os(widget.c['def_id']));
    if (!mounted) return;
    setState(() => busy = false);
    if (r.$1) {
      buzz('success');
      otoast(context, context.otf('challenges.x_gems_x_xp', <Object>[context.fn(r.$2), context.fn(r.$3)]));
      widget.onClaimed();
    } else {
      otoast(context, r.$4, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> c = widget.c;
    final int target = oi(c['target'], 1) < 1 ? 1 : oi(c['target'], 1);
    final int prog = oi(c['progress']);
    final bool done = prog >= target;
    final bool claimed = c['claimed'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: claimed ? .6 : 1,
        child: OPanel(
          accent: done && !claimed ? OC.green : null,
          glow: done && !claimed,
          pad: widget.compact ? 8 : 12,
          child: Row(children: <Widget>[
            Icon(claimed ? Icons.military_tech_rounded : (done ? Icons.star_rounded : Icons.sports_soccer_rounded),
                color: done ? OC.gold : OC.cyan, size: widget.compact ? 32 : 40),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(os(c['title_fa']), maxLines: 2, style: TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: widget.compact ? 12 : 14)),
                const SizedBox(height: 4),
                OBar(prog / target, color: done ? OC.green : OC.cyan, h: 6),
                const SizedBox(height: 4),
                Text(
                  '${context.fn(prog < target ? prog : target)}/${context.fn(target)} · 💎${context.fn(oi(c['reward_gems']))} · ${context.fn(oi(c['reward_xp']))}XP',
                  style: const TextStyle(color: OC.dim, fontSize: 10),
                ),
              ]),
            ),
            SizedBox(
              width: 80,
              child: claimed
                  ? Text(context.ot('challenges.claimed'), textAlign: TextAlign.center, style: const TextStyle(color: OC.green, fontSize: 11))
                  : (done
                      ? OBtn(context.ot('challenges.claim'), small: true, style: OBtnStyle.green, busy: busy, onTap: _claim)
                      : Text(context.ot('challenges.in_progress'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 11))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Home card: today's challenges at a glance (only when signed in) — for other areas' home screens.
class ChallengesHomeCard extends StatefulWidget {
  const ChallengesHomeCard({super.key});

  @override
  State<ChallengesHomeCard> createState() => _ChallengesHomeCardState();
}

class _ChallengesHomeCardState extends State<ChallengesHomeCard> {
  List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
  String _uid = '';

  @override
  void initState() {
    super.initState();
    OnlineCore.instance.addListener(_auth);
    _auth();
  }

  @override
  void dispose() {
    OnlineCore.instance.removeListener(_auth);
    super.dispose();
  }

  void _auth() {
    final String u = OnlineCore.instance.uid;
    if (u == _uid) return;
    _uid = u;
    if (u.isEmpty) {
      if (mounted) setState(() => list = <Map<String, dynamic>>[]);
      return;
    }
    loadChallenges().then(((bool, List<Map<String, dynamic>>, String) r) {
      if (mounted && r.$1) setState(() => list = r.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty || list.isEmpty) return const SizedBox.shrink();
    final int done = list.where((Map<String, dynamic> c) => c['claimed'] == true).length;
    return OPanel(
      accent: OC.green,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          const Icon(Icons.event_available_rounded, color: OC.green, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.ot('challenges.today_s_challenges'), style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800)),
              Text(
                context.otf('challenges.x_x_done_refreshes_in',
                    <Object>[context.fn(done), context.fn(list.length), context.fn((secondsToTehranMidnight() / 3600).floor())]),
                style: const TextStyle(color: OC.dim, fontSize: 10),
              ),
            ]),
          ),
          SizedBox(width: 72, child: OBtn(context.ot('challenges.all'), small: true, style: OBtnStyle.dark, onTap: () => context.push('/online/challenges'))),
        ]),
        const SizedBox(height: 8),
        for (final Map<String, dynamic> c in list.take(4)) ChallengeCard(c: c, compact: true, onClaimed: () => setState(() => c['claimed'] = true)),
      ]),
    );
  }
}
