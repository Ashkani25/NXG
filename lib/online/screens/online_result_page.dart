/// Online result: score, XP / coins / rating / arena points actually granted by the backend
/// (profile diff before → after), level-up, back to lobby / leave room (port of the Godot app's
/// src/online/online_result.gd). Route /online/result/:roomId with the [OnlineOutcome] as `extra`.
library;


import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/widgets/nx_widgets.dart';
import '../link.dart';
import '../models.dart';
import '../online_core.dart';
import '../ui/oui.dart';

class OnlineResultPage extends StatefulWidget {
  const OnlineResultPage({super.key, required this.roomId, required this.outcome});
  final String roomId;
  final OnlineOutcome? outcome;

  @override
  State<OnlineResultPage> createState() => _OnlineResultPageState();
}

class _OnlineResultPageState extends State<OnlineResultPage> with SingleTickerProviderStateMixin {
  final OnlineCore core = OnlineCore.instance;
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();
  late final Map<String, dynamic> before = Map<String, dynamic>.from(core.beforeProfile);
  Map<String, dynamic> after = <String, dynamic>{};
  bool loading = false;

  OnlineOutcome? get o => widget.outcome;
  String get out {
    final OnlineOutcome? x = o;
    if (x == null || x.myTeam == null || x.winner == -1) return 'draw';
    return x.winner == x.myTeam ? 'victory' : 'defeat';
  }

  @override
  void initState() {
    super.initState();
    final OnlineOutcome? x = o;
    if (x != null && x.matchId.isNotEmpty) core.skipMatch = x.matchId;
    core.linkForRoom(widget.roomId);
    if (x != null && x.myTeam != null && x.reported) {
      loading = true;
      _loadAfter(0);
    }
    if (out == 'victory') buzz('success');
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  /// the backend has granted rewards by now; poll the profile a couple of times in case realtime is late
  Future<void> _loadAfter(int n) async {
    final Map<String, dynamic>? p = await core.refreshProfile();
    if (!mounted) return;
    if (p != null && (before.isEmpty || oi(p['xp']) != oi(before['xp']) || n >= 2)) {
      setState(() {
        after = p;
        loading = false;
      });
    } else if (n < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) _loadAfter(n + 1);
    } else {
      setState(() {
        after = p ?? <String, dynamic>{};
        loading = false;
      });
    }
  }

  void _toLobby() {
    final RoomLink? l = core.link;
    if (l != null && !l.disposed) {
      l.refresh();
      context.pushReplacement('/online/lobby/${l.id}?skip=${core.skipMatch}');
    } else {
      context.go('/online');
    }
  }

  @override
  Widget build(BuildContext context) {
    final OnlineOutcome? x = o;
    final Color col = out == 'victory' ? OC.gold : (out == 'defeat' ? OC.red : OC.cyan);
    final String title = out == 'victory' ? context.tx('پیروزی!', 'VICTORY!') : (out == 'defeat' ? context.tx('شکست', 'DEFEAT') : context.tx('مساوی', 'DRAW'));
    final List<Widget> kids = <Widget>[
      SizedBox(
        height: 200,
        child: Stack(alignment: Alignment.center, children: <Widget>[
          RotationTransition(
            turns: _ring,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: <Color>[col.withValues(alpha: 0), col.withValues(alpha: .55), col.withValues(alpha: 0)]),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: .4, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (BuildContext context, double s, Widget? c) => Transform.scale(scale: s, child: c),
            child: Text(title,
                style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: col, blurRadius: 26)])),
          ),
        ]),
      ),
    ];
    if (x != null) {
      kids.add(OPanel(
        accent: col,
        glow: true,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: <Widget>[
            _side(x.teams.isNotEmpty ? x.teams[0] : '', x.names.isNotEmpty ? x.names[0] : '', OC.cyan),
            Column(children: <Widget>[
              Text('${x.score.$1} : ${x.score.$2}',
                  style: TextStyle(color: OC.text, fontSize: 38, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: col, blurRadius: 12)])),
              Text(x.ranked ? 'RANKED' : 'FRIENDLY', style: const TextStyle(color: OC.dim, fontSize: 9, letterSpacing: 2)),
            ]),
            _side(x.teams.length > 1 ? x.teams[1] : '', x.names.length > 1 ? x.names[1] : '', OC.red),
          ]),
        ),
      ));
      kids.add(const SizedBox(height: 10));
      if (x.myTeam == null) {
        kids.add(Text(context.ot('online_result.you_were_a_spectator_in'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim)));
      } else if (!x.reported) {
        kids.add(OPanel(accent: OC.orange, child: Text(context.ot('online_result.the_result_wasn_t_saved'), textAlign: TextAlign.center, style: const TextStyle(color: OC.orange))));
      } else if (loading) {
        kids.add(Column(children: <Widget>[oSpinner(), Text(context.ot('online_result.collecting_rewards'), style: const TextStyle(color: OC.dim, fontSize: 11))]));
      } else {
        kids.addAll(_rewards(context, x));
      }
      if (x.myTeam != null) {
        kids.add(const SizedBox(height: 12));
        kids.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          OracleAvatar(pose: out == 'victory' ? 'cheer' : (out == 'defeat' ? 'calm' : 'happy'), size: 84),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xEB0E1840),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OC.cyan.withValues(alpha: .4)),
              ),
              child: Text(
                out == 'victory'
                    ? context.tx('عالی بازی کردی! همین فرم را نگه دار.', 'Great game! Keep that form.')
                    : (out == 'defeat'
                        ? context.tx('این بار نشد؛ زاویه‌ها را با حوصله‌تر بگیر و دوباره امتحان کن.', 'Not this time — take your angles calmly and try again.')
                        : context.tx('مساوی سخت! بازی بعدی مال توست.', 'A hard-fought draw! The next one is yours.')),
                style: const TextStyle(color: OC.text, fontSize: 12),
              ),
            ),
          ),
        ]));
      }
    }
    kids.add(const SizedBox(height: 16));
    kids.add(OBtn(context.ot('online_result.back_to_lobby'), style: out == 'victory' ? OBtnStyle.gold : OBtnStyle.primary, onTap: _toLobby));
    kids.add(const SizedBox(height: 8));
    kids.add(OBtn(context.ot('online_result.leave_room'), small: true, style: OBtnStyle.dark, onTap: () async {
      await core.leaveRoom();
      if (mounted) context.go('/online');
    }));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool did, Object? _) {
        if (!did) _toLobby();
      },
      child: OPage(title: title, en: 'RESULT', accent: col, onBack: _toLobby, body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: kids)),
    );
  }

  Widget _side(String team, String name, Color c) => Expanded(
        child: Column(children: <Widget>[
          OAvatar(disc: team, size: 54, ring: c),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      );

  List<Widget> _rewards(BuildContext context, OnlineOutcome x) {
    if (after.isEmpty) return const <Widget>[];
    final bool hasB = before.isNotEmpty;
    final int dXp = hasB ? oi(after['xp']) - oi(before['xp']) : 0;
    final int dCoins = hasB ? oi(after['coins']) - oi(before['coins']) : 0;
    final int dRating = hasB ? oi(after['rating']) - oi(before['rating']) : (x.ratingDelta ?? 0);
    final int dArena = hasB ? oi(after['arena_points']) - oi(before['arena_points']) : 0;
    final int lvUp = hasB && oi(after['level']) > oi(before['level']) ? oi(after['level']) : 0;
    final ({int level, int cur, int need, double frac}) lp = lvl(after['xp']);
    return <Widget>[
      Row(children: <Widget>[
        _rw(Icons.star_rounded, dXp, OC.cyan, 150, 'XP'),
        _rw(Icons.monetization_on_rounded, dCoins, OC.gold, 300, ''),
        _rw(Icons.emoji_events_rounded, dRating, dRating >= 0 ? OC.green : OC.red, 450, context.ot('online_result.rating')),
        if (dArena != 0) _rw(Icons.workspace_premium_rounded, dArena, OC.violet, 600, context.ot('arena.arena')),
      ]),
      const SizedBox(height: 8),
      OPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text(context.otf('hub.level_x', <Object>[context.fn(lp.level)]), style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800))),
            Text('${context.fn(lp.cur)} / ${context.fn(lp.need)} XP', style: const TextStyle(color: OC.dim, fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          OBar(lp.frac, color: OC.cyan, color2: OC.violet),
        ]),
      ),
      if (lvUp > 0) ...<Widget>[
        const SizedBox(height: 8),
        OPanel(
          accent: OC.violet,
          glow: true,
          child: Row(children: <Widget>[
            const Icon(Icons.workspace_premium_rounded, color: OC.gold, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(context.otf('online_result.level_x', <Object>[context.fn(lvUp)]), style: const TextStyle(color: Color(0xFFD6B8FF), fontSize: 18, fontWeight: FontWeight.w900)),
                Text(context.ot('online_result.you_reached_a_new_level'), style: const TextStyle(color: OC.dim, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      ],
    ];
  }

  Widget _rw(IconData i, int v, Color c, int delayMs, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: Duration(milliseconds: 600 + delayMs),
            builder: (BuildContext context, double k, _) {
              final double t = ((k * (600 + delayMs) - delayMs) / 600).clamp(0.0, 1.0);
              final int n = (v * t).round();
              return Opacity(
                opacity: t,
                child: OPanel(
                  accent: c,
                  pad: 8,
                  child: Column(children: <Widget>[
                    Icon(i, color: c, size: 32),
                    Text('${n >= 0 ? '+' : ''}${context.fn(n)}', style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w900)),
                    if (label.isNotEmpty) Text(label, style: const TextStyle(color: OC.dim, fontSize: 10)),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}
