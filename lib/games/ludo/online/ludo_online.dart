/// Online Ludo board (2–4 real players). The server rolls (`{a:'roll'}`) and lists the legal
/// tokens; the player taps one of them (`{a:'move', t}`). Captures, extra turns on 6 / capture /
/// reaching home and the three-sixes forfeit all happen server-side (`_gm_ludo_*`).
///
/// Wire state: n, corners[seat], tk[seat][token] (-1 base … 56 home), roll, legal[], six,
/// last = {seat, roll, t, from, to, caps[[seat, token, from]], pass, again, forfeit}.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';

import '../core/ludo_rules.dart';
import '../ui/ludo_board.dart';
import '../ui/ludo_die.dart';

LudoState ludoStateFromWire(Map<String, dynamic> st, int turn) {
  final List<int> corners = gmInts(st['corners']);
  final List<List<int>> tk = <List<int>>[
    for (final Object? row in (st['tk'] is List ? st['tk'] as List<dynamic> : <dynamic>[])) gmInts(row),
  ];
  final int n = corners.length < 2 ? 2 : corners.length;
  return LudoState(
    playerCount: n,
    corners: corners.length == n ? corners : LudoRules.cornersFor(n),
    tokens: tk.length == n ? tk : List<List<int>>.generate(n, (_) => List<int>.filled(kLudoTokens, kLudoBase)),
    turn: turn,
    sixStreak: gmInt(st['six']),
  );
}

Color ludoSeatColor(int seat) => kLudoSeatColors[seat % kLudoSeatColors.length];

class _TokPos {
  const _TokPos(this.seat, this.token, this.pos);
  final int seat;
  final int token;
  final Offset pos;
}

class LudoOnlineBoard extends StatefulWidget {
  const LudoOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<LudoOnlineBoard> createState() => _LudoOnlineBoardState();
}

class _LudoOnlineBoardState extends State<LudoOnlineBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  GmMatchController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  List<int> _movable(GmView v) => v.myTurn && v.phase == 'move' ? gmInts(v.state['legal']) : <int>[];

  /// Token draw list with a small fan-out when several tokens share a cell.
  List<_TokPos> _positions(LudoState s) {
    final List<_TokPos> out = <_TokPos>[];
    final Map<String, int> seen = <String, int>{};
    for (int seat = 0; seat < s.playerCount; seat++) {
      for (int t = 0; t < kLudoTokens; t++) {
        final int p = s.tokens[seat][t];
        Offset o = LudoGeom.cellFor(s, seat, t, p);
        if (p != kLudoBase && p != kLudoHome) {
          final String k = '${o.dx.toStringAsFixed(2)}:${o.dy.toStringAsFixed(2)}';
          final int n = seen[k] ?? 0;
          seen[k] = n + 1;
          if (n > 0) o = o.translate(0.18 * ((n % 2) * 2 - 1), -0.14 * n);
        }
        out.add(_TokPos(seat, t, o));
      }
    }
    return out;
  }

  void _tap(Offset local, double side, GmView v) {
    final List<int> mov = _movable(v);
    if (mov.isEmpty || c.busy) return;
    final int me = v.mySeat!;
    final LudoState s = ludoStateFromWire(v.state, v.turn);
    final Offset cell = local / (side / 15);
    int? best;
    double bestD = 0.9;
    for (final _TokPos tp in _positions(s)) {
      if (tp.seat != me || !mov.contains(tp.token)) continue;
      final double d = (tp.pos - cell).distance;
      if (d < bestD) {
        bestD = d;
        best = tp.token;
      }
    }
    if (best == null && mov.length == 1) best = mov.first;
    if (best != null) {
      HapticFeedback.selectionClick();
      c.move(GmMove('move', <String, dynamic>{'t': best}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final LudoState s = ludoStateFromWire(v.state, v.turn);
    final List<int> mov = _movable(v);
    final List<Color?> cornerColors = List<Color?>.filled(4, null);
    for (int seat = 0; seat < s.playerCount; seat++) {
      cornerColors[s.corners[seat]] = v.isOut(seat) ? null : ludoSeatColor(seat);
    }
    final Map<String, dynamic> last = gmMap(v.state['last']);
    final int? roll = gmIntOrNull(v.state['roll']) ?? gmIntOrNull(last['roll']);
    return Column(children: <Widget>[
      GmPlayerStrip(
        c: c,
        colorOf: ludoSeatColor,
        extra: (int seat) => context.tx('خانه: ${gmNum(context, s.homeCount(seat))}/۴', 'home ${s.homeCount(seat)}/4'),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
                final double side = bc.maxWidth;
                return Directionality(
                  textDirection: TextDirection.ltr,
                  child: GestureDetector(
                    onTapUp: (TapUpDetails d) => _tap(d.localPosition, side, v),
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (BuildContext context, Widget? _) => Stack(children: <Widget>[
                        Positioned.fill(child: CustomPaint(painter: LudoBoardPainter(cornerColors: cornerColors, fancy: true))),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: LudoTokensPainter(
                              tokens: <LudoTokenDraw>[
                                for (final _TokPos tp in _positions(s))
                                  if (!v.isOut(tp.seat))
                                    LudoTokenDraw(
                                      pos: tp.pos,
                                      color: ludoSeatColor(tp.seat),
                                      movable: tp.seat == v.mySeat && mov.contains(tp.token),
                                      scale: s.tokens[tp.seat][tp.token] == kLudoHome ? 0.7 : 1,
                                    ),
                              ],
                              pulse: _pulse.value,
                              fancy: true,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      _footer(context, v, roll, last, mov),
    ]);
  }

  Widget _footer(BuildContext context, GmView v, int? roll, Map<String, dynamic> last, List<int> mov) {
    final Color col = ludoSeatColor(v.turn);
    String msg;
    if (!v.live) {
      msg = '';
    } else if (v.myTurn && v.phase == 'roll') {
      msg = context.tx('نوبت توست — تاس بریز', 'Your turn — roll');
    } else if (mov.isNotEmpty) {
      msg = context.tx('یکی از مهره‌های درخشان را انتخاب کن', 'Tap a glowing token');
    } else {
      msg = context.tx('نوبت ${v.nameOf(v.turn)}', "${v.nameOf(v.turn)}'s turn");
    }
    if (v.live && last.isNotEmpty) {
      final String who = v.nameOf(gmInt(last['seat']));
      if (last['forfeit'] == true) {
        msg += context.tx(' • سه شش پشت‌سرهم: نوبت $who سوخت', ' • three sixes: $who loses the turn');
      } else if (last['pass'] == true) {
        msg += context.tx(' • $who حرکتی نداشت', ' • $who had no move');
      } else if (last['again'] == true) {
        msg += context.tx(' • شش! دوباره', ' • a six! again');
      } else if (last['caps'] is List && (last['caps'] as List<dynamic>).isNotEmpty) {
        msg += context.tx(' • $who مهره زد!', ' • $who captured!');
      }
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(children: <Widget>[
          GestureDetector(
            onTap: v.myTurn && v.phase == 'roll' && !c.busy ? () => c.move(const GmMove('roll')) : null,
            child: LudoDie(value: roll, color: col, size: 58),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (v.myTurn && v.phase == 'roll')
            FilledButton.icon(
              onPressed: c.busy ? null : () => c.move(const GmMove('roll')),
              icon: const Icon(Icons.casino_rounded),
              label: Text(context.tx('تاس', 'Roll')),
            ),
        ]),
      ),
    );
  }
}
