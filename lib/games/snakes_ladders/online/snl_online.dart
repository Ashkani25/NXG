/// Online Snakes & Ladders (2–4 real players). The server rolls and moves (`{a:'roll'}`),
/// including the bounce off 100, snakes / ladders and the extra roll on a 6.
///
/// Wire state: pos[seat] (0 = launch pad), last = {seat, roll, from, steps[], landed, final, extra}.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';

import '../ui/snl_board.dart';

Color snlSeatColor(int seat) => kSnlSeatColors[seat % kSnlSeatColors.length];

/// Squares a token visits for one server move: from, every step, then the snake/ladder end.
List<int> snlPathOf(Map<String, dynamic> last) {
  final List<int> path = <int>[gmInt(last['from']), ...gmInts(last['steps'])];
  final int fin = gmInt(last['final'], path.last);
  if (fin != path.last) path.add(fin);
  return path;
}

class SnlOnlineBoard extends StatefulWidget {
  const SnlOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<SnlOnlineBoard> createState() => _SnlOnlineBoardState();
}

class _SnlOnlineBoardState extends State<SnlOnlineBoard> with TickerProviderStateMixin {
  late final AnimationController _ambient;
  late final AnimationController _walk;
  StreamSubscription<GmView>? _sub;
  int _animSeat = -1;
  List<int> _animPath = <int>[];
  int _lastVersion = -1;

  GmMatchController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _walk = AnimationController(vsync: this);
    _sub = c.views.listen(_onView);
    final GmView? v = c.view;
    if (v != null) _lastVersion = v.version;
  }

  void _onView(GmView v) {
    if (_lastVersion >= 0 && v.version > _lastVersion) {
      final Map<String, dynamic> last = gmMap(v.state['last']);
      if (last.isNotEmpty) {
        _animSeat = gmInt(last['seat']);
        _animPath = snlPathOf(last);
        _walk.duration = Duration(milliseconds: 220 * _animPath.length + 200);
        _walk.forward(from: 0);
        if (_animPath.length > 1) HapticFeedback.lightImpact();
      }
    }
    _lastVersion = v.version;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ambient.dispose();
    _walk.dispose();
    super.dispose();
  }

  Offset _animPos(int seat) {
    final List<int> p = _animPath;
    if (p.length < 2) return SnlGeom.pos(p.isEmpty ? 0 : p.first, seat);
    final double f = _walk.value * (p.length - 1);
    final int i = f.floor().clamp(0, p.length - 2);
    final double k = f - i;
    return Offset.lerp(SnlGeom.pos(p[i], seat), SnlGeom.pos(p[i + 1], seat), k)!;
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final List<int> pos = gmInts(v.state['pos']);
    final Map<String, dynamic> last = gmMap(v.state['last']);
    return Column(children: <Widget>[
      GmPlayerStrip(
        c: c,
        colorOf: snlSeatColor,
        extra: (int s) => context.tx('خانه ${gmNum(context, s < pos.length ? pos[s] : 0)}', 'square ${s < pos.length ? pos[s] : 0}'),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: AspectRatio(
              aspectRatio: 10 / kSnlBoardRows,
              child: LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
                final double w = bc.maxWidth;
                return Directionality(
                  textDirection: TextDirection.ltr,
                  child: Stack(children: <Widget>[
                    Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: SnlBoardPainter(fancy: true, isFa: context.isFa)))),
                    Positioned(
                      left: 0,
                      top: 0,
                      width: w,
                      height: w,
                      child: AnimatedBuilder(
                        animation: _ambient,
                        builder: (BuildContext context, Widget? _) => CustomPaint(painter: SnlOverlayPainter(t: _ambient.value, fancy: true)),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[_walk, _ambient]),
                        builder: (BuildContext context, Widget? _) => CustomPaint(
                          painter: SnlTokensPainter(
                            pulse: _ambient.value,
                            fancy: true,
                            tokens: <SnlTokenDraw>[
                              for (int s = 0; s < pos.length; s++)
                                if (!v.isOut(s))
                                  SnlTokenDraw(
                                    pos: _walk.isAnimating && s == _animSeat ? _animPos(s) : SnlGeom.pos(pos[s], s),
                                    color: snlSeatColor(s),
                                    active: v.live && s == v.turn,
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              }),
            ),
          ),
        ),
      ),
      _footer(context, v, last),
    ]);
  }

  Widget _footer(BuildContext context, GmView v, Map<String, dynamic> last) {
    String msg;
    if (!v.live) {
      msg = '';
    } else if (v.myTurn) {
      msg = context.tx('نوبت توست — تاس بریز', 'Your turn — roll');
    } else {
      msg = context.tx('نوبت ${v.nameOf(v.turn)}', "${v.nameOf(v.turn)}'s turn");
    }
    if (last.isNotEmpty && v.live) {
      final int landed = gmInt(last['landed']);
      final int fin = gmInt(last['final']);
      final String who = v.nameOf(gmInt(last['seat']));
      if (fin > landed) {
        msg += context.tx(' • $who از نردبان بالا رفت!', ' • $who climbed a ladder!');
      } else if (fin < landed) {
        msg += context.tx(' • مار $who را نیش زد!', ' • a snake bit $who!');
      }
      if (last['extra'] == true) msg += context.tx(' • شش: دوباره', ' • six: again');
    }
    final int? roll = gmIntOrNull(last['roll']);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(children: <Widget>[
          GestureDetector(
            onTap: v.myTurn && !c.busy ? () => c.move(const GmMove('roll')) : null,
            child: SnlDie(value: roll, color: snlSeatColor(v.turn), size: 56),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (v.myTurn)
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
