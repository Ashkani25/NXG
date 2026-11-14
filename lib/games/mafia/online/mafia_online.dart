/// Online Mafia (6–12 real players). Roles are dealt and kept by the server: every player only
/// receives their own role (`view.private.role`), mafia also get their mates and the team's night
/// picks, the detective gets their check results. Night actions and votes are secret moves.
/// Moves: {a:'night', t} {a:'vote', t} (t null = skip / spare) {a:'ready'} (`_gm_mafia_*`).
///
/// Wire state: day, alive[], shown[] (roles of dead players / everyone at the end), defendants[],
/// voted[], ready[], tally, skips, team (winner), ev[] = {k, s?, r?, ss?, team?, d}.
/// Phases: night (40 s) → day (90 s, talk) → nominate (30 s) → defense (30 s) → final (20 s).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';
import 'package:nexora/online/link.dart';
import 'package:nexora/online/online_core.dart';

import '../core/mafia_models.dart';
import '../ui/mafia_visuals.dart';

MafiaRole? mafiaRoleOf(Object? s) {
  if (s is! String) return null;
  for (final MafiaRole r in MafiaRole.values) {
    if (r.name == s) return r;
  }
  return null;
}

/// One public event as text.
String mafiaEventText(Map<String, dynamic> e, GmView v, bool fa) {
  String n(Object? s) => v.nameOf(gmInt(s, -1));
  String role(Object? r) {
    final MafiaRole? m = mafiaRoleOf(r);
    if (m == null) return '';
    return fa ? ' (${m.labelFa})' : ' (${m.labelEn})';
  }

  final int d = gmInt(e['d'], 1);
  switch ('${e['k'] ?? ''}') {
    case 'night':
      return fa ? 'شب ${gmFaDigits('$d')} فرا رسید.' : 'Night $d falls.';
    case 'day':
      return fa ? 'روز ${gmFaDigits('$d')}: گفتگو کنید.' : 'Day $d: talk it over.';
    case 'vote':
      return fa ? 'رأی‌گیری اول: چه کسی به دفاع برود؟' : 'First vote: who goes on trial?';
    case 'night_kill':
      return fa ? '${n(e['s'])}${role(e['r'])} در شب کشته شد.' : '${n(e['s'])}${role(e['r'])} was killed in the night.';
    case 'sniper':
      return fa ? '${n(e['s'])}${role(e['r'])} با شلیک تک‌تیرانداز از پا درآمد.' : '${n(e['s'])}${role(e['r'])} was taken down by the Sniper.';
    case 'backfire':
      return fa ? '${n(e['s'])}${role(e['r'])} به یک بی‌گناه شلیک کرد و از بازی خارج شد.' : '${n(e['s'])}${role(e['r'])} shot an innocent and is out.';
    case 'vote_out':
      return fa ? '${n(e['s'])}${role(e['r'])} با رأی شهر حذف شد.' : '${n(e['s'])}${role(e['r'])} was voted out.';
    case 'left':
      return fa ? '${n(e['s'])}${role(e['r'])} بازی را ترک کرد.' : '${n(e['s'])}${role(e['r'])} left the game.';
    case 'no_victim':
      return fa ? 'شب بدون قربانی گذشت.' : 'The night passed with no victim.';
    case 'saved':
      return fa ? 'دکتر دیشب جان یک نفر را نجات داد.' : 'The Doctor saved someone last night.';
    case 'no_trial':
      return fa ? 'کسی به دفاع نرفت.' : 'Nobody was put on trial.';
    case 'trial':
      final String who = gmInts(e['ss']).map(v.nameOf).join(fa ? '، ' : ', ');
      return fa ? 'به دفاع رفتند: $who' : 'On trial: $who';
    case 'spared':
      return fa ? 'رأی نهایی کافی نبود؛ کسی حذف نشد.' : 'The final vote fell short; nobody was eliminated.';
    case 'win':
      return e['team'] == 'town'
          ? (fa ? 'شهروندان پیروز شدند!' : 'The Town wins!')
          : (fa ? 'مافیا ایستگاه را تسخیر کرد!' : 'The Mafia has taken the station!');
    default:
      return '';
  }
}

class MafiaOnlineBoard extends StatefulWidget {
  const MafiaOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<MafiaOnlineBoard> createState() => _MafiaOnlineBoardState();
}

class _MafiaOnlineBoardState extends State<MafiaOnlineBoard> {
  final TextEditingController _chat = TextEditingController();
  RoomLink? _link;

  GmMatchController get c => widget.c;

  @override
  void initState() {
    super.initState();
    final RoomLink? l = OnlineCore.instance.link;
    if (l != null && !l.disposed) {
      _link = l;
      l.addListener(_onLink);
    }
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _link?.removeListener(_onLink);
    _chat.dispose();
    super.dispose();
  }

  bool _alive(GmView v, int s) {
    final List<bool> a = gmBools(v.state['alive']);
    return s >= 0 && s < a.length && a[s];
  }

  /// What a tap on seat [s] does right now (null = nothing).
  GmMove? _tapMove(GmView v, int s, MafiaRole? myRole) {
    final int? me = v.mySeat;
    if (me == null || !v.live || !_alive(v, me) || !_alive(v, s)) return null;
    switch (v.phase) {
      case 'night':
        if (myRole == null || myRole == MafiaRole.citizen) return null;
        if (myRole != MafiaRole.doctor && s == me) return null;
        return GmMove('night', <String, dynamic>{'t': s});
      case 'nominate':
        if (s == me) return null;
        return GmMove('vote', <String, dynamic>{'t': s});
      case 'final':
        if (s == me || !gmInts(v.state['defendants']).contains(s)) return null;
        return GmMove('vote', <String, dynamic>{'t': s});
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final bool fa = context.isFa;
    final MafiaRole? myRole = mafiaRoleOf(v.private['role']);
    final bool night = v.phase == 'night';
    return MoonlitBackground(
      night: night,
      animate: true,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 16), children: <Widget>[
        _header(context, v, myRole, fa),
        const SizedBox(height: 10),
        _grid(context, v, myRole),
        const SizedBox(height: 10),
        _actions(context, v, myRole),
        const SizedBox(height: 10),
        _privateInfo(context, v, myRole),
        _log(context, v, fa),
        if (_link != null) _chatBox(context, v),
      ]),
    );
  }

  Widget _header(BuildContext context, GmView v, MafiaRole? myRole, bool fa) {
    final int day = gmInt(v.state['day'], 1);
    String title;
    String sub;
    IconData icon;
    Color col;
    switch (v.phase) {
      case 'night':
        title = fa ? 'شب ${gmFaDigits('$day')}' : 'Night $day';
        sub = myRole == null || myRole == MafiaRole.citizen
            ? context.tx('چشم‌ها بسته… نقش‌های شب در حال انتخاب‌اند.', 'Eyes closed… night roles are choosing.')
            : context.tx('هدفت را انتخاب کن.', 'Choose your target.');
        icon = Icons.nightlight_round;
        col = MafiaStyle.moon;
        break;
      case 'day':
        title = fa ? 'روز ${gmFaDigits('$day')}' : 'Day $day';
        sub = context.tx('گفتگو کنید؛ وقتی همه آماده شدند رأی‌گیری شروع می‌شود.', 'Talk it over; voting starts when everyone is ready.');
        icon = Icons.wb_sunny_rounded;
        col = NxColors.gold;
        break;
      case 'nominate':
        title = context.tx('رأی‌گیری اول', 'First vote');
        sub = context.tx('روی مظنون بزن (یا رأی نده).', 'Tap a suspect (or skip).');
        icon = Icons.how_to_vote_rounded;
        col = NxColors.electricBlue;
        break;
      case 'defense':
        title = context.tx('دفاع', 'Defense');
        sub = context.tx('متهم‌ها از خودشان دفاع می‌کنند.', 'The accused defend themselves.');
        icon = Icons.record_voice_over_rounded;
        col = NxColors.pink;
        break;
      default:
        title = context.tx('رأی نهایی', 'Final vote');
        sub = context.tx('یکی از متهم‌ها را حذف کن یا ببخش.', 'Eliminate one of the accused, or spare.');
        icon = Icons.gavel_rounded;
        col = MafiaStyle.blood;
    }
    if (!v.live) {
      final bool town = v.state['team'] == 'town';
      title = town ? context.tx('پیروزی شهر', 'Town wins') : context.tx('پیروزی مافیا', 'Mafia wins');
      sub = '';
      icon = Icons.emoji_events_rounded;
      col = town ? NxColors.turquoise : MafiaStyle.blood;
    }
    return MafiaPanel(
      accent: col,
      child: Row(children: <Widget>[
        Icon(icon, color: col, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: col)),
            if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: NxColors.textDim, fontSize: 13)),
          ]),
        ),
        if (myRole != null)
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (BuildContext ctx) => Dialog(
                backgroundColor: Colors.transparent,
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  RoleCard(role: myRole, flipped: true, isFa: ctx.isFa, animate: false),
                  const SizedBox(height: 10),
                  Text(ctx.isFa ? myRole.descFa : myRole.descEn, textAlign: TextAlign.center),
                ]),
              ),
            ),
            child: Chip(
              avatar: Icon(MafiaStyle.roleIcon(myRole), color: MafiaStyle.roleColor(myRole), size: 18),
              label: Text(context.isFa ? myRole.labelFa : myRole.labelEn),
            ),
          ),
      ]),
    );
  }

  Widget _grid(BuildContext context, GmView v, MafiaRole? myRole) {
    final List<MafiaRole?> shown = <MafiaRole?>[for (final Object? x in (v.state['shown'] is List ? v.state['shown'] as List<dynamic> : <dynamic>[])) mafiaRoleOf(x)];
    final Set<int> mates = <int>{for (final Map<String, dynamic> m in gmMaps(v.private['mates'])) gmInt(m['seat'])};
    final Map<String, dynamic> teamPick = gmMap(v.private['team_pick']);
    final Set<int> teamTargets = <int>{for (final Object? t in teamPick.values) if (t != null) gmInt(t)};
    final int? myPick = gmIntOrNull(v.private['my_pick']);
    final int? myVote = gmIntOrNull(v.private['my_vote']);
    final List<int> defs = gmInts(v.state['defendants']);
    final List<bool> voted = gmBools(v.state['voted']);
    final List<bool> ready = gmBools(v.state['ready']);
    final Map<String, dynamic> checks = gmMap(v.private['checks']);
    return Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: <Widget>[
      for (int s = 0; s < v.seatCount; s++)
        Builder(builder: (BuildContext context) {
          final bool alive = _alive(v, s);
          final GmMove? mv = _tapMove(v, s, myRole);
          final bool picked = (v.phase == 'night' && myPick == s) || ((v.phase == 'nominate' || v.phase == 'final') && myVote == s);
          final MafiaRole? r = s < shown.length ? shown[s] : null;
          Color? glow;
          if (picked) {
            glow = NxColors.gold;
          } else if (teamTargets.contains(s) && v.phase == 'night') {
            glow = MafiaStyle.blood;
          } else if (defs.contains(s) && (v.phase == 'defense' || v.phase == 'final')) {
            glow = NxColors.pink;
          } else if (s == v.mySeat) {
            glow = NxColors.turquoise;
          }
          final List<String> tags = <String>[
            if (mates.contains(s) && s != v.mySeat) context.tx('هم‌تیمی', 'mate'),
            if (checks.containsKey('$s')) checks['$s'] == true ? context.tx('مافیا!', 'mafia!') : context.tx('بی‌گناه', 'innocent'),
            if (alive && (v.phase == 'nominate' || v.phase == 'final') && s < voted.length && voted[s]) context.tx('رأی داد', 'voted'),
            if (alive && (v.phase == 'day' || v.phase == 'defense') && s < ready.length && ready[s]) context.tx('آماده', 'ready'),
          ];
          return GestureDetector(
            onTap: mv == null || c.busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    c.move(mv);
                  },
            child: SizedBox(
              width: 76,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                CrewAvatar(name: v.nameOf(s), hue: s * 31.0, size: 54, dead: !alive, glow: glow),
                const SizedBox(height: 3),
                Text(v.nameOf(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mates.contains(s) ? MafiaStyle.blood : null)),
                if (r != null)
                  Text(context.isFa ? r.labelFa : r.labelEn, style: TextStyle(fontSize: 10, color: MafiaStyle.roleColor(r))),
                if (tags.isNotEmpty) Text(tags.join(' • '), style: const TextStyle(fontSize: 10, color: NxColors.textDim)),
              ]),
            ),
          );
        }),
    ]);
  }

  Widget _actions(BuildContext context, GmView v, MafiaRole? myRole) {
    final int? me = v.mySeat;
    if (me == null || !v.live) return const SizedBox.shrink();
    if (!_alive(v, me)) {
      return Center(child: Text(context.tx('تو از بازی حذف شده‌ای؛ تماشا کن.', 'You are out — keep watching.'), style: const TextStyle(color: NxColors.textDim)));
    }
    final List<Widget> b = <Widget>[];
    switch (v.phase) {
      case 'night':
        if (myRole == MafiaRole.doctor || myRole == MafiaRole.detective || myRole == MafiaRole.sniper) {
          b.add(GhostButton(label: context.tx('امشب کاری نمی‌کنم', 'Do nothing tonight'), icon: Icons.bedtime_rounded, onTap: c.busy ? null : () => c.move(const GmMove('night', <String, dynamic>{'t': null}))));
        }
        break;
      case 'day':
      case 'defense':
        final List<bool> ready = gmBools(v.state['ready']);
        final bool isReady = me < ready.length && ready[me];
        b.add(GlowButton(
          label: isReady ? context.tx('آماده‌ام ✓', 'Ready ✓') : context.tx('آماده‌ی رأی‌گیری', 'Ready to vote'),
          icon: Icons.check_rounded,
          onTap: isReady || c.busy ? null : () => c.move(const GmMove('ready')),
        ));
        break;
      case 'nominate':
        b.add(GhostButton(label: context.tx('رأی نمی‌دهم', 'Skip'), icon: Icons.block_rounded, onTap: c.busy ? null : () => c.move(const GmMove('vote', <String, dynamic>{'t': null}))));
        break;
      case 'final':
        b.add(GhostButton(label: context.tx('می‌بخشم', 'Spare'), icon: Icons.favorite_rounded, onTap: c.busy ? null : () => c.move(const GmMove('vote', <String, dynamic>{'t': null}))));
        break;
      default:
        break;
    }
    if (b.isEmpty) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, spacing: 10, children: b);
  }

  Widget _privateInfo(BuildContext context, GmView v, MafiaRole? myRole) {
    if (myRole == null) return const SizedBox.shrink();
    final List<String> lines = <String>[];
    if (myRole == MafiaRole.godfather || myRole == MafiaRole.mafia) {
      final List<String> m = <String>[
        for (final Map<String, dynamic> x in gmMaps(v.private['mates']))
          if (gmInt(x['seat']) != v.mySeat) '${v.nameOf(gmInt(x['seat']))} (${context.isFa ? (mafiaRoleOf(x['role'])?.labelFa ?? '') : (mafiaRoleOf(x['role'])?.labelEn ?? '')})',
      ];
      if (m.isNotEmpty) lines.add(context.tx('هم‌تیمی‌ها: ', 'Your mates: ') + m.join(context.isFa ? '، ' : ', '));
      lines.add(context.tx('انتخاب پدرخوانده تعیین‌کننده است.', "The Godfather's pick decides."));
    }
    if (myRole == MafiaRole.doctor && v.private['saved_ok'] == true) {
      lines.add(context.tx('دیشب جان کسی را نجات دادی!', 'You saved someone last night!'));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return MafiaPanel(
      accent: MafiaStyle.roleColor(myRole),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[for (final String l in lines) Text(l)]),
    );
  }

  Widget _log(BuildContext context, GmView v, bool fa) {
    final List<Map<String, dynamic>> ev = gmMaps(v.state['ev']);
    final List<Map<String, dynamic>> lastN = ev.length > 8 ? ev.sublist(ev.length - 8) : ev;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MafiaPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          for (final Map<String, dynamic> e in lastN.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(mafiaEventText(e, v, fa), style: const TextStyle(fontSize: 13)),
            ),
        ]),
      ),
    );
  }

  Widget _chatBox(BuildContext context, GmView v) {
    final RoomLink l = _link!;
    final List<ChatMsg> msgs = l.state.chat;
    final List<ChatMsg> shown = msgs.length > 12 ? msgs.sublist(msgs.length - 12) : msgs;
    final int? me = v.mySeat;
    final bool canTalk = me == null || !v.live || _alive(v, me);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MafiaPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          for (final ChatMsg m in shown)
            Text.rich(TextSpan(children: <InlineSpan>[
              TextSpan(text: '${m.name}: ', style: const TextStyle(fontWeight: FontWeight.w700, color: NxColors.turquoise)),
              TextSpan(text: m.text),
            ])),
          if (canTalk)
            Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _chat,
                  maxLength: 200,
                  decoration: InputDecoration(hintText: context.tx('حرفت را بزن…', 'Say something…'), counterText: '', isDense: true),
                  onSubmitted: (String t) {
                    l.sendChat(t);
                    _chat.clear();
                  },
                ),
              ),
              IconButton(
                onPressed: () {
                  l.sendChat(_chat.text);
                  _chat.clear();
                },
                icon: const Icon(Icons.send_rounded),
              ),
            ])
          else
            Text(context.tx('حذف‌شده‌ها نمی‌توانند حرف بزنند.', 'Eliminated players cannot talk.'), style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        ]),
      ),
    );
  }
}

String? mafiaResultDetail(BuildContext context, GmView v) {
  final String t = '${v.state['team'] ?? v.reason}';
  if (t == 'town') return context.tx('شهروندان پیروز شدند', 'The Town won');
  if (t == 'mafia') return context.tx('مافیا پیروز شد', 'The Mafia won');
  return null;
}
