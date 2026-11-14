// Pre-match setup panel — port of the Godot build's src/screens/setup.gd (versus row with opponent
// reroll, rule / turn-time segments, loadout row, start) + data.gd build_launch -> MatchCfg.
// Difficulty and mode come from the NEXORA host (GameLaunch); choices persist in LocalStore.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import '../core/data.dart';
import '../core/engine.dart';
import 'df_images.dart';
import 'formation_picker.dart';

/// Everything the player chose before kickoff.
class DfSetup {
  DfSetup({
    required this.rule,
    required this.tt,
    required this.team,
    required this.opp,
    required this.form,
    required this.ball,
    required this.field,
  });

  /// 'g3' | 'g5' | 't3'
  String rule;

  /// turn time seconds (0 = off)
  int tt;
  String team;
  Team opp;
  int form;
  int ball;
  int field;

  static const String _k = 'finger_soccer.';

  static DfSetup load(math.Random rng) {
    String? gs(String k) {
      try {
        return LocalStore.instance.getString(_k + k);
      } catch (_) {
        return null;
      }
    }

    int gi(String k, int d) {
      try {
        return LocalStore.instance.getInt(_k + k) ?? d;
      } catch (_) {
        return d;
      }
    }

    String team = gs('team') ?? 'club0';
    if (teamRemoved(team) || teamById(team).id != team || teamPrice(teamById(team)) != 0) team = 'club0';
    final String rule0 = gs('rule') ?? 'g3';
    final int tt0 = gi('tt', 15);
    return DfSetup(
      rule: const <String>['g3', 'g5', 't3'].contains(rule0) ? rule0 : 'g3',
      tt: const <int>[0, 10, 15, 20].contains(tt0) ? tt0 : 15,
      team: team,
      opp: pickOpp(rng),
      form: gi('form', 0).clamp(0, kForms.length - 1).toInt(),
      ball: ballPrice(gi('ball', 0)) == 0 ? gi('ball', 0).clamp(0, kBallCount - 1).toInt() : 0,
      field: fieldPrice(gi('field', 0)) == 0 ? gi('field', 0).clamp(0, kFields.length - 1).toInt() : 0,
    );
  }

  void save() {
    try {
      final LocalStore s = LocalStore.instance;
      s.setString('${_k}rule', rule);
      s.setInt('${_k}tt', tt);
      s.setString('${_k}team', team);
      s.setInt('${_k}form', form);
      s.setInt('${_k}ball', ball);
      s.setInt('${_k}field', field);
    } catch (_) {}
  }

  /// data.gd build_launch: the MatchCfg for this setup.
  MatchCfg toCfg({required bool ai, required int aiLvl, required int oppForm, int? seed}) {
    final Team me = teamById(team);
    final DiscStatsData a = discStatsFor(me.id);
    final DiscStatsData b = discStatsFor(opp.id);
    return MatchCfg(
      field: field,
      ball: ball,
      forms: <int>[form, ai ? oppForm : form],
      ai: ai,
      aiLvl: aiLvl,
      limit: rule == 'g5' ? 5 : 3,
      matchTime: rule == 't3' ? 180 : 0,
      turnTime: tt.toDouble(),
      vip: <bool>[teamBoosted(me), teamBoosted(opp)],
      first: 0,
      stats: <DiscStats?>[DiscStats(power: a.power, accuracy: a.accuracy), DiscStats(power: b.power, accuracy: b.accuracy)],
      teams: <String>[me.id, opp.id],
      seed: seed,
    );
  }
}

String dfLevelName(BotDifficulty d, DfTx tx) {
  switch (d) {
    case BotDifficulty.easy:
      return tx('آسان', 'Easy');
    case BotDifficulty.normal:
      return tx('معمولی', 'Normal');
    case BotDifficulty.hard:
      return tx('سخت', 'Hard');
  }
}

class DfSetupPanel extends StatefulWidget {
  const DfSetupPanel({super.key, required this.launch, required this.setup, required this.rng, required this.onStart});
  final GameLaunch launch;
  final DfSetup setup;
  final math.Random rng;
  final VoidCallback onStart;

  @override
  State<DfSetupPanel> createState() => _DfSetupPanelState();
}

class _DfSetupPanelState extends State<DfSetupPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  String tx(String fa, String en) => widget.launch.tx(fa, en);

  void _reroll() {
    setState(() => widget.setup.opp = pickOpp(widget.rng));
    _spin.forward(from: 0);
  }

  Future<void> _loadout() async {
    final DfSetup s = widget.setup;
    final DfLoadout v = DfLoadout(form: s.form, team: s.team, ball: s.ball, field: s.field);
    await showDfLoadout(context, value: v, tx: tx, withField: true, onChange: () {
      setState(() {
        s.form = v.form;
        s.team = v.team;
        s.ball = v.ball;
        s.field = v.field;
      });
    });
  }

  Widget _side(String asset, String name, String sub, Color col, VoidCallback? onTap, {bool spin = false}) {
    Widget disc = Container(
      width: 92,
      height: 92,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0B1230),
        border: Border.all(color: col, width: 2.5),
        boxShadow: <BoxShadow>[BoxShadow(color: col.withValues(alpha: 0.45), blurRadius: 18)],
      ),
      child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover, cacheWidth: 192, errorBuilder: _err)),
    );
    if (spin) {
      disc = AnimatedBuilder(
        animation: _spin,
        builder: (BuildContext c, Widget? ch) =>
            Transform.rotate(angle: Curves.easeOutBack.transform(_spin.value) * math.pi * 2, child: ch),
        child: disc,
      );
    }
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          disc,
          const SizedBox(height: 8),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFEAF4FF), fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: col, fontSize: 12)),
        ]),
      ),
    );
  }

  static Widget _err(BuildContext c, Object e, StackTrace? s) => const ColoredBox(color: Color(0xFF0D1A3A));

  Widget _row(String label, Widget w) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(label, style: const TextStyle(color: Color(0xFF8EA3D6), fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(height: 8),
          w,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final DfSetup s = widget.setup;
    final GameLaunch l = widget.launch;
    final bool local = l.mode == GameMode.local;
    final Team me = teamById(s.team);
    const List<String> rules = <String>['g3', 'g5', 't3'];
    const List<int> tts = <int>[0, 10, 15, 20];
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(0, -0.6), radius: 1.3, colors: <Color>[Color(0xFF101A44), Color(0xFF040510)]),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 64, 14, 28),
              children: <Widget>[
                Text(tx('فوتبال انگشتی', 'Finger Soccer'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        shadows: <Shadow>[Shadow(color: Color(0xFF39D5FF), blurRadius: 18)])),
                const SizedBox(height: 4),
                Text(
                  local
                      ? tx('دو نفره روی یک گوشی', 'Two players, one phone')
                      : '${tx('مقابل ربات', 'Versus bot')} · ${tx('سختی', 'Difficulty')}: ${dfLevelName(l.difficulty, tx)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8EA3D6), fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x2639D5FF), width: 1.5),
                    gradient: const LinearGradient(
                        colors: <Color>[Color(0x2E4FE3FF), Color(0xD90B1230), Color(0x2EFF4A5A)]),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
                      _side(DfArt.team(me.id), local ? tx('بازیکن ۱', 'Player 1') : l.playerName, tx('مهره‌ی تو', 'Your disc'),
                          const Color(0xFF39D5FF), _loadout),
                      const Text('VS', style: TextStyle(color: Color(0xFF8EA3D6), fontSize: 26, fontWeight: FontWeight.w900)),
                      _side(DfArt.team(s.opp.id), local ? tx('بازیکن ۲', 'Player 2') : s.opp.name,
                          tx('حریف دیگر', 'Another opponent'), const Color(0xFFFF4A5A), _reroll,
                          spin: true),
                    ]),
                  ),
                ),
                _row(
                    tx('قانون', 'Rule'),
                    DfSegmented(
                      labels: <String>[tx('تا ۳ گل', 'First to 3'), tx('تا ۵ گل', 'First to 5'), tx('۳ دقیقه', '3 minutes')],
                      index: rules.indexOf(s.rule) < 0 ? 0 : rules.indexOf(s.rule),
                      color: const Color(0xFF9B5CFF),
                      onChanged: (int i) => setState(() => s.rule = rules[i]),
                    )),
                _row(
                    tx('زمان نوبت', 'Turn time'),
                    DfSegmented(
                      labels: <String>[tx('خاموش', 'Off'), tx('۱۰ث', '10s'), tx('۱۵ث', '15s'), tx('۲۰ث', '20s')],
                      index: tts.indexOf(s.tt) < 0 ? 2 : tts.indexOf(s.tt),
                      color: const Color(0xFF4DFF8A),
                      onChanged: (int i) => setState(() => s.tt = tts[i]),
                    )),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _loadout,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xC70B1230),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Row(children: <Widget>[
                      SizedBox(width: 46, height: 64, child: DfFormationThumb(formation: s.form, selected: true, discAsset: DfArt.team(s.team))),
                      const SizedBox(width: 10),
                      SizedBox(width: 40, height: 40, child: Image.asset(DfArt.ball(s.ball), cacheWidth: 96, errorBuilder: _err)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(tx('ترکیب، توپ و مهره', 'Formation, ball & disc'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text('${tx(kForms[s.form].nameFa, kForms[s.form].nameEn)} · ${kBallNames[s.ball]} · ${kFields[s.field].name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF8EA3D6), fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.tune_rounded, color: Color(0xFF39D5FF)),
                    ]),
                  ),
                ),
                const SizedBox(height: 22),
                GestureDetector(
                  onTap: () {
                    s.save();
                    widget.onStart();
                  },
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(27),
                      gradient: const LinearGradient(colors: <Color>[Color(0xFF39D5FF), Color(0xFF2A6CFF)]),
                      boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x8039D5FF), blurRadius: 22, offset: Offset(0, 6))],
                    ),
                    child: Text(tx('شروع بازی', 'Start match'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
