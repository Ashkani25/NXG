/// Leaderboard (top 100 by rating, my rank highlighted) + league ladder with season countdown and
/// rewards (port of the Godot app's src/online/ranks.gd), and the Arena ladder (arena.gd).
/// Tables/RPC: leaderboard (view), leagues, season_rewards, profiles (arena ladder);
/// rpc current_season, claim_season_reward, quick_match(p_kind 'arena').
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../online_core.dart';
import '../supabase_client.dart';
import '../ui/oui.dart';

/// One leaderboard row (RN LbItem) — shared by ranks and arena.
class LbRow extends StatelessWidget {
  const LbRow({super.key, required this.r, required this.mine, this.metric, this.metricLabel = ''});
  final Map<String, dynamic> r;
  final bool mine;
  final int? metric;
  final String metricLabel;

  @override
  Widget build(BuildContext context) {
    final int rank = oi(r['rank']);
    final Color? medal = rank >= 1 && rank <= 3 ? <Color>[OC.gold, const Color(0xFFD6E2F0), const Color(0xFFE0954A)][rank - 1] : null;
    return Container(
      height: 58,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: mine ? OC.cyan.withValues(alpha: .12) : OC.rowBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mine ? OC.cyan : OC.line),
      ),
      child: Row(children: <Widget>[
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: medal?.withValues(alpha: .2) ?? Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: medal ?? OC.line),
          ),
          child: Text(context.fn(rank), style: TextStyle(color: medal ?? OC.dim, fontWeight: FontWeight.w900, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        OAvatar(disc: r['avatar'], url: r['avatar_url'], size: 40, ring: medal ?? OC.line),
        const SizedBox(width: 8),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${os(r['username'])}${mine ? context.ot('ranks.you') : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800)),
            Text(context.otf('ranks.level_x_x_wins', <Object>[context.fn(oi(r['level'], 1)), context.fn(oi(r['wins']))]),
                style: const TextStyle(color: OC.dim, fontSize: 10)),
          ]),
        ),
        leagueBadge(r['league'], 28),
        SizedBox(
          width: 60,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Text(context.fn(metric ?? oi(r['rating'])), style: const TextStyle(color: OC.gold, fontWeight: FontWeight.w900, fontSize: 14)),
            Text(metricLabel.isNotEmpty ? metricLabel : context.ot('online_result.rating'), style: const TextStyle(color: OC.dim, fontSize: 9)),
          ]),
        ),
      ]),
    );
  }
}

// ================================================================ ranks
class OnlineRanksPage extends StatefulWidget {
  const OnlineRanksPage({super.key, this.tab = 'top'});
  final String tab;

  @override
  State<OnlineRanksPage> createState() => _OnlineRanksPageState();
}

class _OnlineRanksPageState extends State<OnlineRanksPage> {
  final OnlineCore core = OnlineCore.instance;
  late String tab = widget.tab == 'leagues' ? 'leagues' : 'top';
  List<Map<String, dynamic>> lb = <Map<String, dynamic>>[];
  Map<String, dynamic> lbMe = <String, dynamic>{};
  String lbErr = '';
  bool lbLoaded = false;
  Map<String, dynamic> season = <String, dynamic>{};
  Map<String, int> rewards = <String, int>{};
  bool leaguesLoaded = false;
  bool claimBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await core.ensure();
    if (tab == 'top') {
      await _loadLb();
    } else {
      await _loadLeagues();
    }
  }

  Future<void> _loadLb() async {
    final String u = core.uid;
    final OnlineResult a = await guard(() => Online.client.from('leaderboard').select().order('rank').limit(100));
    OnlineResult b = const OnlineResult.ok();
    if (u.isNotEmpty) b = await guard(() => Online.client.from('leaderboard').select().eq('id', u));
    if (!mounted) return;
    setState(() {
      if (!a.ok) {
        lbErr = a.error;
      } else {
        lbErr = '';
        lb = a.rows;
        lbMe = b.rows.isNotEmpty ? b.rows.first : <String, dynamic>{};
        lbLoaded = true;
      }
    });
  }

  Future<void> _loadLeagues() async {
    await core.loadLeagues();
    final OnlineResult s = await callRpc('current_season');
    final OnlineResult rw = await guard(() => Online.client.from('season_rewards').select());
    await core.refreshProfile();
    if (!mounted) return;
    setState(() {
      if (s.ok) {
        final Object? sd = s.data;
        season = om(sd is List && sd.isNotEmpty ? sd.first : sd);
      }
      rewards = <String, int>{for (final Map<String, dynamic> r in rw.rows) os(r['league']): oi(r['gems'])};
      leaguesLoaded = true;
    });
  }

  String _seasonText(BuildContext context) {
    if (season.isEmpty) return '…';
    final double left = (isoToUnix(season['ends_at']) - nowS()).clamp(0, double.infinity).toDouble();
    final int dd = (left / 86400).floor();
    final int hh = ((left % 86400) / 3600).floor();
    return context.otf('ranks.x_days_x_hours_until', <Object>[context.fn(dd), context.fn(hh)]);
  }

  Future<void> _claim() async {
    if (claimBusy) return;
    setState(() => claimBusy = true);
    final OnlineResult r = await callRpc('claim_season_reward');
    if (!mounted) return;
    setState(() => claimBusy = false);
    if (r.ok) {
      buzz('success');
      otoast(context, context.otf('ranks.x_gems_season_reward', <Object>[context.fn(oi(r.map['gems']))]));
    } else {
      otoast(context, r.error, err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool top = tab == 'top';
    return OPage(
      title: top ? context.ot('hub.leaderboard') : context.ot('ranks.leagues_season'),
      en: top ? 'LEADERBOARD' : 'LEAGUES · SEASON',
      accent: OC.gold,
      onRefresh: _reload,
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: OSegment<String>(
            items: <(String, String)>[('top', context.ot('ranks.top_players')), ('leagues', context.ot('ranks.leagues'))],
            value: tab,
            accent: OC.gold,
            onChanged: (String v) {
              setState(() => tab = v);
              _reload();
            },
          ),
        ),
        Expanded(child: top ? _top(context) : ListenableBuilder(listenable: core, builder: (BuildContext c, _) => _leagues(c))),
      ]),
    );
  }

  Widget _top(BuildContext context) {
    final String me = core.uid;
    if (lbErr.isNotEmpty) return OError(lbErr, onRetry: _loadLb);
    if (!lbLoaded) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: oSkeleton(8, 58));
    if (lb.isEmpty) return OEmpty(icon: Icons.sports_soccer_rounded, title: context.ot('ranks.no_one_is_on_the'));
    final bool inTop = lb.any((Map<String, dynamic> r) => os(r['id']) == os(lbMe['id']));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: <Widget>[
      if (lbMe.isNotEmpty && !inTop) ...<Widget>[LbRow(r: lbMe, mine: true), const SizedBox(height: 6)],
      for (final Map<String, dynamic> r in lb)
        GestureDetector(
          onTap: null,
          child: LbRow(r: r, mine: os(r['id']) == me),
        ),
    ]);
  }

  Widget _leagues(BuildContext context) {
    if (!leaguesLoaded) return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: oSkeleton(4, 64));
    final int rating = oi(core.profile['rating']);
    final List<Map<String, dynamic>> list = List<Map<String, dynamic>>.of(core.leagues)
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) => oi(b['sort']).compareTo(oi(a['sort'])));
    final (Map<String, dynamic>?, Map<String, dynamic>?) cn = leagueFor(rating);
    final Map<String, dynamic>? cur = cn.$1, nxt = cn.$2;
    final List<Widget> out = <Widget>[
      OPanel(
        accent: OC.violet,
        glow: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.event_rounded, size: 44, color: OC.violet),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(season.isNotEmpty ? os(season['name'], context.ot('ranks.current_season')) : context.ot('ranks.current_season'),
                    style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
                OTicker(every: const Duration(seconds: 30), builder: (BuildContext c) => Text(_seasonText(c), style: const TextStyle(color: OC.dim, fontSize: 11))),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text(context.ot('ranks.at_the_end_of_each'), style: const TextStyle(color: OC.dim, fontSize: 11)),
          const SizedBox(height: 8),
          OBtn(claimBusy ? '…' : context.ot('ranks.claim_last_season_s_reward'), small: true, style: OBtnStyle.violet, onTap: claimBusy ? null : _claim),
        ]),
      ),
    ];
    if (core.profile.isNotEmpty && cur != null) {
      final Color cc = leagueColor(cur);
      double frac = 1;
      if (nxt != null) {
        final int span = oi(nxt['min_rating']) - oi(cur['min_rating']);
        frac = (rating - oi(cur['min_rating'])) / (span < 1 ? 1 : span);
      }
      out.add(const SizedBox(height: 10));
      out.add(OPanel(
        accent: cc,
        child: Row(children: <Widget>[
          leagueBadge(cur['id'], 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.otf('ranks.x_league', <Object>[os(cur['name_fa'])]), style: TextStyle(color: cc, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              OBar(frac, color: cc, color2: OC.violet),
              const SizedBox(height: 4),
              Text(
                nxt != null
                    ? context.otf('ranks.x_x_to_x_league', <Object>[context.fn(rating), context.fn(oi(nxt['min_rating'])), os(nxt['name_fa'])])
                    : context.otf('ranks.x_top_league', <Object>[context.fn(rating)]),
                style: const TextStyle(color: OC.dim, fontSize: 11),
              ),
            ]),
          ),
        ]),
      ));
    }
    out.add(oSection(context.ot('ranks.league_ladder')));
    for (final Map<String, dynamic> l in list) {
      final Color col = leagueColor(l);
      final bool on = cur != null && os(cur['id']) == os(l['id']);
      final bool reached = rating >= oi(l['min_rating']);
      out.add(Container(
        height: 68,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: on ? col.withValues(alpha: .12) : OC.rowBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? col : OC.line),
        ),
        child: Row(children: <Widget>[
          Opacity(opacity: reached ? 1 : .4, child: leagueBadge(l['id'], 40)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(os(l['name_fa']), style: TextStyle(color: reached ? col : OC.dim, fontWeight: FontWeight.w800)),
              Text(context.otf('ranks.from_x_rating', <Object>[context.fn(oi(l['min_rating']))]), style: const TextStyle(color: OC.dim, fontSize: 10)),
            ]),
          ),
          if (on) OBadge(context.ot('ranks.your_league'), color: col),
          SizedBox(
            width: 70,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              Text('💎 ${context.fn(rewards[os(l['id'])] ?? 0)}', style: const TextStyle(color: OC.gem, fontWeight: FontWeight.w800, fontSize: 12)),
              Text(context.ot('ranks.season_reward'), style: const TextStyle(color: OC.dim, fontSize: 9)),
            ]),
          ),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: out);
  }
}

// ================================================================ arena
class OnlineArenaPage extends StatefulWidget {
  const OnlineArenaPage({super.key});

  @override
  State<OnlineArenaPage> createState() => _OnlineArenaPageState();
}

class _OnlineArenaPageState extends State<OnlineArenaPage> {
  final OnlineCore core = OnlineCore.instance;
  List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
  bool loaded = false;
  String err = '';
  String busy = '';

  @override
  void initState() {
    super.initState();
    _load();
    core.ensure().then((_) => core.refreshProfile());
  }

  Future<void> _load() async {
    final OnlineResult r = await guard(() => Online.client
        .from('profiles')
        .select('id,username,avatar,avatar_url,level,xp,rating,league,wins,losses,draws,trophies,arena_points')
        .gt('arena_points', 0)
        .order('arena_points', ascending: false)
        .limit(50));
    if (!mounted) return;
    setState(() {
      if (!r.ok) {
        err = r.error;
      } else {
        err = '';
        int k = 0;
        rows = <Map<String, dynamic>>[for (final Map<String, dynamic> x in r.rows) <String, dynamic>{...x, 'rank': ++k}];
        loaded = true;
      }
    });
  }

  Future<void> _find(String m) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = m);
    await core.ensure();
    final (String, String) res = await core.quickMatch(m, 'arena');
    if (!mounted) return;
    setState(() => busy = '');
    if (res.$1.isNotEmpty) {
      otoast(context, res.$1, err: true);
      buzz('heavy');
    } else if (res.$2.isNotEmpty) {
      buzz('medium');
      context.push('/online/lobby/${res.$2}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> out = <Widget>[
      ListenableBuilder(
        listenable: core,
        builder: (BuildContext context, _) {
          final Map<String, dynamic> p = core.profile;
          return OPanel(
            accent: OC.violet,
            glow: true,
            pad: 16,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                const Icon(Icons.workspace_premium_rounded, size: 60, color: OC.violet),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(context.ot('arena.arena_rating'), style: const TextStyle(color: OC.dim, fontSize: 12)),
                    Text(context.fn(oi(p['arena_points'])), style: const TextStyle(color: Color(0xFFE2C8FF), fontSize: 32, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                _tile(context.fn(oi(p['win_streak'])), context.ot('arena.win_streak'), OC.orange),
                const SizedBox(width: 8),
                _tile(context.fn(oi(p['best_streak'])), context.ot('arena.best_x').replaceAll('%s', '').trim(), const Color(0xFFE2C8FF)),
              ]),
              const SizedBox(height: 8),
              Text(context.ot('arena.win_30_and_5_per'), style: const TextStyle(color: OC.dim, fontSize: 11)),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                for (int k = 0; k < 3; k++) ...<Widget>[
                  Expanded(
                    child: OBtn(busy == kModes[k] ? '…' : kModes[k].toUpperCase(),
                        small: true,
                        sub: context.ot('arena.find_opponent'),
                        style: <OBtnStyle>[OBtnStyle.violet, OBtnStyle.primary, OBtnStyle.gold][k],
                        onTap: busy.isNotEmpty ? null : () => _find(kModes[k])),
                  ),
                  if (k < 2) const SizedBox(width: 8),
                ],
              ]),
            ]),
          );
        },
      ),
      oSection(context.ot('arena.arena_ladder')),
    ];
    if (err.isNotEmpty) {
      out.add(OError(err, onRetry: _load));
    } else if (!loaded) {
      out.add(oSkeleton(6, 58));
    } else if (rows.isEmpty) {
      out.add(OEmpty(icon: Icons.workspace_premium_rounded, title: context.ot('arena.no_one_has_an_arena'), sub: context.ot('arena.be_the_first_to_win')));
    } else {
      for (final Map<String, dynamic> r in rows) {
        out.add(LbRow(r: r, mine: os(r['id']) == core.uid, metric: oi(r['arena_points']), metricLabel: context.ot('arena.arena')));
      }
    }
    return OPage(
      title: context.ot('arena.arena'),
      en: 'ARENA LADDER',
      accent: OC.violet,
      onRefresh: _load,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: out),
    );
  }

  Widget _tile(String v, String l, Color c) => Expanded(
        child: Container(
          height: 64,
          decoration: BoxDecoration(color: OC.rowBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: OC.line)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Text(v, style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(color: OC.dim, fontSize: 11)),
          ]),
        ),
      );
}
