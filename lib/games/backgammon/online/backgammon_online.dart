/// Online backgammon board. The server rolls the dice and validates the whole play
/// (`_gm_backgammon_move`); this widget builds the play locally with [BgTurnTracker]
/// (same legality: bar first, use both dice, larger-die rule, bearing off) and sends it on confirm.
///
/// Wire state (`view.state`): b = 28 ints (b[0..23] points, + seat 0 / − seat 1, b[24..25] bar,
/// b[26..27] borne off), dice = rolled dice while phase = 'move', last = {seat, dice, moves, pass}.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';

import '../core/backgammon_rules.dart';
import '../ui/bg_geometry.dart';
import '../ui/bg_widgets.dart';

/// Server board array -> rules state.
BgState bgStateFromWire(List<int> b, int turn) {
  final List<int> w = List<int>.from(b);
  while (w.length < 28) {
    w.add(0);
  }
  return BgState(points: w.sublist(0, 24), bar: <int>[w[24], w[25]], off: <int>[w[26], w[27]], turn: turn);
}

/// A play as the server expects it: [[from, to, die], …]
List<List<int>> bgPlayToWire(List<BgMove> moves) => <List<int>>[for (final BgMove m in moves) <int>[m.from, m.to, m.die]];

class BackgammonOnlineBoard extends StatefulWidget {
  const BackgammonOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<BackgammonOnlineBoard> createState() => _BackgammonOnlineBoardState();
}

class _BackgammonOnlineBoardState extends State<BackgammonOnlineBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  BgTurnTracker? _tracker;
  int _trackerVersion = -1;
  int? _selected;

  GmMatchController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  BgState _serverState(GmView v) => bgStateFromWire(gmInts(v.state['b']), v.turn);

  /// (Re)builds the local tracker when it is my move on a new server version.
  BgTurnTracker? _syncTracker(GmView v) {
    final int? me = v.mySeat;
    if (!v.myTurn || v.phase != 'move' || me == null) {
      _tracker = null;
      _trackerVersion = -1;
      return null;
    }
    if (_tracker == null || _trackerVersion != v.version) {
      _tracker = BgTurnTracker(_serverState(v), me, gmInts(v.state['dice']));
      _trackerVersion = v.version;
      _selected = null;
    }
    return _tracker;
  }

  void _haptic() => HapticFeedback.selectionClick();

  void _onTap(Offset p, GmView v) {
    final BgTurnTracker? t = _tracker;
    if (t == null || c.busy || t.complete) return;
    final int? place = BgGeom.hitTest(p, t.player);
    final List<BgMove> legal = t.legalMoves();
    if (place == null) {
      setState(() => _selected = null);
      return;
    }
    final int? sel = _selected;
    if (sel != null) {
      final List<BgMove> to = legal.where((BgMove m) => m.from == sel && m.to == place).toList()
        ..sort((BgMove a, BgMove b) => a.die.compareTo(b.die));
      if (to.isNotEmpty) {
        t.play(to.first);
        _haptic();
        setState(() => _selected = null);
        return;
      }
    }
    if (legal.any((BgMove m) => m.from == place)) {
      setState(() => _selected = place);
    } else {
      setState(() => _selected = null);
    }
  }

  Future<void> _confirm() async {
    final BgTurnTracker? t = _tracker;
    if (t == null || !t.complete) return;
    await c.move(GmMove('play', <String, dynamic>{'moves': bgPlayToWire(t.played)}));
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final BgTurnTracker? t = _syncTracker(v);
    final BgState shown = t?.state ?? _serverState(v);
    return Column(children: <Widget>[
      GmPlayerStrip(
        c: c,
        colorOf: (int s) => s == 0 ? const Color(0xFFF6D9A4) : const Color(0xFF8A4E2E),
        extra: (int s) => context.tx('بیرون: ${gmNum(context, shown.off[s])} • پیپ ${gmNum(context, shown.pip(s))}',
            'off ${shown.off[s]} • pips ${shown.pip(s)}'),
      ),
      Expanded(child: _board(context, v, shown, t)),
      _status(context, v, t),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 10), child: _controls(context, v, t)),
    ]);
  }

  Widget _board(BuildContext context, GmView v, BgState s, BgTurnTracker? t) {
    final Set<int> dests = <int>{};
    final Set<int> sources = <int>{};
    bool destOff = false;
    if (t != null && !t.complete) {
      for (final BgMove m in t.legalMoves()) {
        sources.add(m.from);
        if (m.from == _selected) {
          if (m.to == kBgOff) {
            destOff = true;
          } else {
            dests.add(m.to);
          }
        }
      }
    }
    final List<Widget> layers = <Widget>[
      Positioned.fill(
        child: Image.asset(
          AppAssets.gamesBackgammonBoardNxGold,
          fit: BoxFit.fill,
          cacheWidth: 1536,
          errorBuilder: (BuildContext c, Object e, StackTrace? st) => const CustomPaint(painter: BgFallbackBoardPainter()),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: BgHighlightPainter(
              state: s,
              player: t?.player ?? (v.mySeat ?? 0),
              destinations: dests,
              destOff: destOff,
              sources: sources,
              selected: _selected,
              pulse: _pulse,
              fancy: true,
            ),
          ),
        ),
      ),
    ];
    // borne-off slabs
    for (int p = 0; p < 2; p++) {
      final List<Color> cols = p == 0
          ? const <Color>[Color(0xFFF6D9A4), Color(0xFFC08A48)]
          : const <Color>[Color(0xFF8A4E2E), Color(0xFF3A1C0D)];
      for (int k = 0; k < s.off[p]; k++) {
        final Offset o = BgGeom.slabCenter(p, k);
        layers.add(Positioned(
          left: o.dx - BgGeom.slabW / 2,
          top: o.dy - BgGeom.slabH / 2,
          width: BgGeom.slabW,
          height: BgGeom.slabH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(colors: cols, begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
          ),
        ));
      }
    }
    Widget checker(Offset o, int p) => Positioned(
          left: o.dx - BgGeom.d / 2,
          top: o.dy - BgGeom.d / 2,
          width: BgGeom.d,
          height: BgGeom.d,
          child: IgnorePointer(child: BgChecker(player: p)),
        );
    for (int i = 0; i < 24; i++) {
      for (int p = 0; p < 2; p++) {
        final int n = s.own(p, i);
        for (int k = 0; k < n; k++) {
          layers.add(checker(BgGeom.checkerCenter(i, k, n), p));
        }
      }
    }
    for (int p = 0; p < 2; p++) {
      for (int k = 0; k < s.bar[p]; k++) {
        layers.add(checker(BgGeom.barCenter(p, k, s.bar[p]), p));
      }
    }
    // dice
    final List<int> dice = v.phase == 'move' ? gmInts(v.state['dice']) : gmInts(gmMap(v.state['last'])['dice']);
    if (dice.isNotEmpty) {
      final List<int> pool = t?.pool ?? BgRules.expandDice(dice);
      final List<bool> used = t?.used ?? List<bool>.filled(pool.length, v.phase != 'move');
      const double size = 84;
      final double gap = pool.length > 2 ? 10 : 24;
      final double total = pool.length * size + (pool.length - 1) * gap;
      for (int i = 0; i < pool.length; i++) {
        layers.add(Positioned(
          left: BgGeom.diceCenter.dx - total / 2 + i * (size + gap),
          top: BgGeom.diceCenter.dy - size / 2,
          width: size,
          height: size,
          child: IgnorePointer(child: BgDie(value: pool[i], size: size, used: i < used.length && used[i])),
        ));
      }
    }
    Widget board = SizedBox(
      width: BgGeom.w,
      height: BgGeom.h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (TapUpDetails d) => _onTap(d.localPosition, v),
        child: Stack(clipBehavior: Clip.none, children: layers),
      ),
    );
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
      final bool portrait = bc.maxHeight > bc.maxWidth * 1.05;
      if (portrait) board = RotatedBox(quarterTurns: 1, child: board);
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: FittedBox(fit: BoxFit.contain, child: board)),
      );
    });
  }

  Widget _status(BuildContext context, GmView v, BgTurnTracker? t) {
    String text;
    final Map<String, dynamic> last = gmMap(v.state['last']);
    if (!v.live) {
      text = '';
    } else if (v.myTurn && v.phase == 'roll') {
      text = context.tx('نوبت توست: تاس بریز', 'Your turn: roll the dice');
    } else if (t != null) {
      text = t.complete
          ? context.tx('حرکت کامل شد؛ تأیید کن', 'Play complete — confirm it')
          : context.tx('${gmNum(context, t.needed)} حرکت دیگر', '${t.needed} more move(s)');
    } else {
      text = context.tx('نوبت ${v.nameOf(v.turn)}', "${v.nameOf(v.turn)}'s turn");
    }
    if (last['pass'] == true && v.live) {
      text += context.tx(' • ${v.nameOf(gmInt(last['seat']))} حرکتی نداشت', ' • ${v.nameOf(gmInt(last['seat']))} had no move');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _controls(BuildContext context, GmView v, BgTurnTracker? t) {
    if (!v.live || !v.isPlayer) return const SizedBox(height: 44);
    if (v.myTurn && v.phase == 'roll') {
      return BgButton(
        label: context.tx('ریختن تاس', 'Roll'),
        icon: Icons.casino_rounded,
        primary: true,
        onTap: c.busy ? null : () => c.move(const GmMove('roll')),
      );
    }
    if (t == null) return const SizedBox(height: 44);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
      BgButton(
        label: context.tx('برگرداندن', 'Undo'),
        icon: Icons.undo_rounded,
        onTap: t.canUndo && !c.busy
            ? () => setState(() {
                  t.undo();
                  _selected = null;
                })
            : null,
      ),
      const SizedBox(width: 12),
      BgButton(
        label: context.tx('تأیید', 'Confirm'),
        icon: Icons.check_rounded,
        primary: true,
        color: NxColors.success,
        onTap: t.complete && !c.busy ? _confirm : null,
      ),
    ]);
  }
}

String? backgammonResultDetail(BuildContext context, GmView v) {
  switch (v.reason) {
    case 'gammon':
      return context.tx('مارس! (۲ امتیاز)', 'Gammon! (2 points)');
    case 'backgammon':
      return context.tx('مارس ترکی! (۳ امتیاز)', 'Backgammon! (3 points)');
    case 'resign':
      return context.tx('با تسلیم یا خروج یک بازیکن', 'By resignation or a player leaving');
    default:
      return null;
  }
}
