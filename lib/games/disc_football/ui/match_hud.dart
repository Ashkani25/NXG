// In-match HUD — port of the Godot build's src/game/match_hud.gd (MatchHud): beveled glass slab with
// two team wings (disc avatar, name, turn chip), a raised metallic score plate with the clock pill,
// a glowing turn-time strip under the active wing, a beveled round pause button and a small loadout
// (formation) button under it. Code drawn, no raster art. Reused by the online match.
//
//   DfMatchHud(data: DfHudData(...), names: [a, b], human: [true, false], teamImg: [img0, img1],
//              onPause: ..., onLoadout: ..., pauseRight: false, leftReserve: 0, rightReserve: 56, tx: launch.tx)
// Geometry is LTR (team 0 wing on the left); [leftReserve]/[rightReserve] keep a corner free (the host's
// exit button), the pause button sits on the [pauseRight] side.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class DfHudData {
  const DfHudData({
    required this.s0,
    required this.s1,
    required this.turn,
    required this.clock,
    required this.sudden,
    required this.frac,
    required this.bar,
    required this.active,
  });
  final int s0;
  final int s1;
  final int turn;
  final String clock;
  final bool sudden;

  /// Turn time left 0..1.
  final double frac;
  final bool bar;

  /// false while the ball moves / goal pause: wings dim slightly.
  final bool active;

  bool same(DfHudData o) =>
      o.s0 == s0 &&
      o.s1 == s1 &&
      o.turn == turn &&
      o.clock == clock &&
      o.sudden == sudden &&
      (o.frac - frac).abs() < 0.004 &&
      o.bar == bar &&
      o.active == active;
}

const List<Color> _team = <Color>[Color(0xFF39D5FF), Color(0xFFFF4A5A)];
const List<Color> _team2 = <Color>[Color(0xFF3B6BFF), Color(0xFFFF8A3A)];
const Color _slab = Color(0xFF070B1F);
const Color _slab2 = Color(0xFF111A3E);
const Color _steel = Color(0xFFC9D6FF);
const Color _gold = Color(0xFFFFD257);

class _Geom {
  _Geom(Size size, bool pauseRight, double leftReserve, double rightReserve) {
    w = size.width;
    h = size.height;
    final double pd = h * 0.66;
    pb = Rect.fromLTWH(pauseRight ? w - pd : 0, (h * 0.86 - pd) * 0.5, pd, pd);
    final double ls = pd * 0.78;
    lb = Rect.fromLTWH(pb.left + (pd - ls) * 0.5, pb.bottom + h * 0.12, ls, ls);
    final double x0 = pauseRight ? leftReserve : pd + h * 0.14;
    final double x1 = pauseRight ? w - pd - h * 0.14 : w - rightReserve;
    final double bw = x1 - x0;
    final double pw = (bw * 0.27).clamp(h * 1.6, h * 2.6).toDouble();
    final double cx = x0 + bw * 0.5;
    plate = Rect.fromLTWH(cx - pw * 0.5, 0, pw, h * 0.86);
    final double wy = h * 0.10;
    final double wh = h * 0.66;
    sk = wh * 0.32;
    wing = <Rect>[
      Rect.fromLTWH(x0, wy, plate.left - x0 + sk * 0.6, wh),
      Rect.fromLTWH(plate.right - sk * 0.6, wy, x1 - (plate.right - sk * 0.6), wh),
    ];
    avr = wh * 0.40;
    av = <Offset>[
      Offset(wing[0].left + avr + wh * 0.16, wy + wh * 0.5),
      Offset(wing[1].right - avr - wh * 0.16, wy + wh * 0.5),
    ];
    score = Rect.fromLTWH(plate.left, plate.top + h * 0.02, pw, h * 0.52);
    clock = Rect.fromLTWH(plate.left + pw * 0.2, h * 0.56, pw * 0.6, h * 0.22);
    for (int i = 0; i < 2; i++) {
      double nx0, nw;
      if (i == 0) {
        nx0 = av[0].dx + avr + h * 0.10;
        nw = plate.left - nx0 - h * 0.06;
      } else {
        nw = (av[1].dx - avr - h * 0.10) - (plate.right + h * 0.06);
        nx0 = plate.right + h * 0.06;
      }
      nw = math.max(10.0, nw);
      name.add(Rect.fromLTWH(nx0, wy + wh * 0.06, nw, wh * 0.5));
      final double cw = math.min(nw, h * 1.25);
      chip.add(Rect.fromLTWH(i == 0 ? nx0 : nx0 + nw - cw, wy + wh * 0.50, cw, wh * 0.27));
    }
  }
  late final double w, h, sk, avr;
  late final Rect pb, lb, plate, score, clock;
  late final List<Rect> wing;
  late final List<Offset> av;
  final List<Rect> name = <Rect>[];
  final List<Rect> chip = <Rect>[];
}

class DfMatchHud extends StatefulWidget {
  const DfMatchHud({
    super.key,
    required this.data,
    required this.names,
    required this.human,
    required this.teamImg,
    required this.tx,
    this.onPause,
    this.onLoadout,
    this.pauseRight = false,
    this.leftReserve = 0,
    this.rightReserve = 0,
  });
  final DfHudData data;
  final List<String> names;
  final List<bool> human;
  final List<ui.Image?> teamImg;
  final String Function(String fa, String en) tx;
  final VoidCallback? onPause;
  final VoidCallback? onLoadout;
  final bool pauseRight;
  final double leftReserve;
  final double rightReserve;

  @override
  State<DfMatchHud> createState() => _DfMatchHudState();
}

class _DfMatchHudState extends State<DfMatchHud> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  bool _pDown = false;
  bool _lDown = false;

  @override
  void didUpdateWidget(covariant DfMatchHud old) {
    super.didUpdateWidget(old);
    if (old.data.s0 != widget.data.s0 || old.data.s1 != widget.data.s1) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _clock.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final Size size = Size(c.maxWidth, c.maxHeight);
      if (size.width <= 0 || size.height <= 0 || !size.width.isFinite) return const SizedBox.shrink();
      final _Geom g = _Geom(size, widget.pauseRight, widget.leftReserve, widget.rightReserve);
      final DfHudData d = widget.data;
      final double h = g.h;
      final List<Widget> kids = <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _HudPainter(g, d, widget.teamImg, _clock, _pDown, _lDown, widget.onLoadout != null),
          ),
        ),
        Positioned.fromRect(
          rect: g.score,
          child: AnimatedBuilder(
            animation: _pop,
            builder: (BuildContext context, Widget? child) {
              final double p = 1 - _pop.value;
              final double k = _pop.isAnimating ? 1.0 + 0.28 * math.sin(p * math.pi) * p : 1.0;
              return Transform.scale(scale: k, child: child);
            },
            child: Center(
              child: Text(
                '${d.s0}   ${d.s1}',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: h * 0.36,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  shadows: const <Shadow>[
                    Shadow(color: Color(0xE6000514), blurRadius: 6),
                    Shadow(color: Color(0x8C000000), offset: Offset(0, 2), blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: g.clock,
          child: Center(
            child: Text(
              d.clock,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: d.sudden ? _gold : const Color(0xFFC7DBFF),
                fontSize: h * 0.15,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
        ),
      ];
      for (int i = 0; i < 2; i++) {
        final bool on = i == d.turn;
        kids.add(Positioned.fromRect(
          rect: g.name[i],
          child: Align(
            alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              widget.names[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: TextStyle(
                color: on ? Colors.white : const Color(0xFF9EB3E0),
                fontSize: h * 0.19,
                fontWeight: FontWeight.w700,
                height: 1.1,
                shadows: const <Shadow>[Shadow(color: Color(0x99000000), offset: Offset(0, 1.5), blurRadius: 2)],
              ),
            ),
          ),
        ));
        if (on) {
          kids.add(Positioned.fromRect(
            rect: g.chip[i],
            child: Center(
              child: Text(
                widget.human[i] ? widget.tx('نوبت توئه', 'Your turn') : widget.tx('نوبت حریف', "Opponent's turn"),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(color: Colors.white, fontSize: h * 0.13, fontWeight: FontWeight.w700, height: 1.0),
              ),
            ),
          ));
        }
      }
      kids.add(Positioned.fromRect(
        rect: g.pb,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pDown = true),
          onTapCancel: () => setState(() => _pDown = false),
          onTapUp: (_) => setState(() => _pDown = false),
          onTap: widget.onPause,
        ),
      ));
      if (widget.onLoadout != null) {
        kids.add(Positioned.fromRect(
          rect: g.lb,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _lDown = true),
            onTapCancel: () => setState(() => _lDown = false),
            onTapUp: (_) => setState(() => _lDown = false),
            onTap: widget.onLoadout,
          ),
        ));
      }
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(clipBehavior: Clip.none, children: kids),
      );
    });
  }
}

Color _shade(Color c, double k, [double a = -1]) => Color.fromRGBO(
      (c.r * k).clamp(0.0, 1.0) * 255 ~/ 1,
      (c.g * k).clamp(0.0, 1.0) * 255 ~/ 1,
      (c.b * k).clamp(0.0, 1.0) * 255 ~/ 1,
      a < 0 ? c.a : a,
    );

Color _a(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0).toDouble());

class _HudPainter extends CustomPainter {
  _HudPainter(this.g, this.d, this.tex, this.clock, this.pDown, this.lDown, this.loadout) : super(repaint: clock);
  final _Geom g;
  final DfHudData d;
  final List<ui.Image?> tex;
  final AnimationController clock;
  final bool pDown;
  final bool lDown;
  final bool loadout;

  List<Offset> _wingPts(int i, Rect r, [double inset = 0]) {
    final double s = g.sk;
    final Offset a = r.topLeft + Offset(inset, inset);
    final Offset b = r.bottomRight - Offset(inset, inset);
    if (i == 0) {
      return <Offset>[
        Offset(a.dx + s * 0.25, a.dy),
        Offset(b.dx, a.dy),
        Offset(b.dx - s, b.dy),
        Offset(a.dx, b.dy),
        Offset(a.dx, a.dy + s * 0.25),
      ];
    }
    return <Offset>[
      Offset(a.dx, a.dy),
      Offset(b.dx - s * 0.25, a.dy),
      Offset(b.dx, a.dy + s * 0.25),
      Offset(b.dx, b.dy),
      Offset(a.dx + s, b.dy),
    ];
  }

  List<Offset> _platePts(Rect r, [double inset = 0]) {
    final double k = r.height * 0.30;
    final Offset a = r.topLeft + Offset(inset, inset);
    final Offset b = r.bottomRight - Offset(inset, inset);
    return <Offset>[Offset(a.dx, a.dy), Offset(b.dx, a.dy), Offset(b.dx - k, b.dy), Offset(a.dx + k, b.dy)];
  }

  Path _path(List<Offset> pts, [Offset o = Offset.zero]) =>
      Path()..addPolygon(<Offset>[for (final Offset p in pts) p + o], true);

  void _grad(Canvas c, List<Offset> pts, Color top, Color bot) {
    double y0 = double.infinity, y1 = -double.infinity;
    for (final Offset p in pts) {
      y0 = math.min(y0, p.dy);
      y1 = math.max(y1, p.dy);
    }
    if (y1 - y0 < 1) y1 = y0 + 1;
    c.drawPath(_path(pts), Paint()..shader = ui.Gradient.linear(Offset(0, y0), Offset(0, y1), <Color>[top, bot]));
  }

  @override
  void paint(Canvas c, Size size) {
    final double h = g.h;
    final double time = (clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;
    final double pulse = 0.5 + 0.5 * math.sin(time * 3.0);
    // soft drop shadow under the whole slab
    for (int k = 0; k < 3; k++) {
      final Offset o = Offset(0, h * (0.05 + 0.03 * k));
      for (int i = 0; i < 2; i++) {
        c.drawPath(_path(_wingPts(i, g.wing[i]), o), Paint()..color = Color.fromRGBO(0, 0, 0, 0.16 - 0.04 * k));
      }
      c.drawPath(_path(_platePts(g.plate), o), Paint()..color = Color.fromRGBO(0, 0, 0, 0.18 - 0.05 * k));
    }
    for (int i = 0; i < 2; i++) {
      final bool on = i == d.turn;
      final Color tc = _team[i];
      final Rect r = g.wing[i];
      final List<Offset> outer = _wingPts(i, r);
      if (on) {
        for (int gi = 0; gi < 4; gi++) {
          final double a = (0.16 - gi * 0.035) * (0.75 + 0.25 * pulse) * (d.active ? 1.0 : 0.6);
          c.drawPath(
              _path(outer),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeWidth = (3.0 + gi * 5.0) * h / 171
                ..color = _a(tc, a));
        }
      }
      _grad(c, outer, on ? _shade(tc, 0.9, 0.85) : const Color.fromRGBO(107, 128, 184, 0.55),
          on ? _shade(tc, 0.35, 0.85) : const Color.fromRGBO(26, 31, 56, 0.75));
      final List<Offset> face = _wingPts(i, r, h * 0.035);
      final Color top = Color.lerp(_slab2, tc, on ? 0.28 : 0.06)!;
      final Color bot = Color.lerp(_slab, tc, on ? 0.10 : 0.0)!;
      _grad(c, face, _a(top, 0.96), _a(bot, 0.96));
      final double cy = r.top + r.height * 0.46;
      _grad(c, <Offset>[for (final Offset p in face) Offset(p.dx, math.min(p.dy, cy))],
          Color.fromRGBO(255, 255, 255, on ? 0.13 : 0.07), const Color.fromRGBO(255, 255, 255, 0));
      final Paint ln = Paint()
        ..isAntiAlias = true
        ..strokeWidth = 1.6;
      c.drawLine(face[0], face[1], ln..color = Color.fromRGBO(255, 255, 255, on ? 0.35 : 0.18));
      c.drawLine(i == 0 ? face[2] : face[3], i == 0 ? face[3] : face[4], ln
        ..strokeWidth = 2.0
        ..color = const Color.fromRGBO(0, 0, 0, 0.45));
      if (on && d.bar) {
        final double bh = h * 0.06;
        final double y = r.bottom - bh - h * 0.05;
        final double x0 = i == 0 ? (g.av[0].dx + g.avr + h * 0.10) : (r.left + g.sk + h * 0.02);
        final double x1 = i == 0 ? (r.right - g.sk - h * 0.02) : (g.av[1].dx - g.avr - h * 0.10);
        final double fullw = math.max(0.0, x1 - x0);
        c.drawRect(Rect.fromLTWH(x0, y, fullw, bh), Paint()..color = const Color.fromRGBO(0, 0, 0, 0.45));
        final double w = fullw * d.frac.clamp(0.0, 1.0);
        final double fx = i == 0 ? x0 : x1 - w;
        Color c0 = _team[i];
        Color c1 = _team2[i];
        if (d.frac < 0.33) {
          c0 = Color.lerp(_gold, const Color(0xFFFF3B3B), 1.0 - d.frac / 0.33)!;
          c1 = c0;
        }
        if (w > 0.5) {
          c.drawRect(
              Rect.fromLTWH(fx, y, w, bh),
              Paint()
                ..shader = ui.Gradient.linear(Offset(fx, 0), Offset(fx + w, 0), i == 0 ? <Color>[c0, c1] : <Color>[c1, c0]));
          c.drawLine(Offset(fx, y + 0.5), Offset(fx + w, y + 0.5), Paint()
            ..strokeWidth = 1
            ..color = const Color.fromRGBO(255, 255, 255, 0.5));
          c.drawCircle(Offset(i == 0 ? fx + w : fx, y + bh * 0.5), bh * 1.2, Paint()..color = _a(c0, 0.35));
        }
      }
      // disc avatar: recessed socket + team rim + disc + gloss
      final Offset av = g.av[i];
      final double avr = g.avr;
      c.drawCircle(av + Offset(0, h * 0.02), avr + h * 0.045, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.45));
      c.drawCircle(av, avr + h * 0.04, Paint()..color = on ? _shade(tc, 1.0, 0.95) : const Color.fromRGBO(89, 107, 153, 0.9));
      c.drawCircle(av, avr + h * 0.015, Paint()..color = const Color(0xFF050816));
      final ui.Image? img = tex[i];
      if (img != null) {
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: av, radius: avr)));
        final Paint ip = Paint()..filterQuality = FilterQuality.medium;
        if (!on) ip.colorFilter = const ColorFilter.mode(Color.fromRGBO(191, 191, 204, 1), BlendMode.modulate);
        c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromCircle(center: av, radius: avr), ip);
        c.restore();
      }
      c.drawArc(
          Rect.fromCircle(center: av + Offset(-avr * 0.08, -avr * 0.1), radius: avr * 0.82),
          200 * math.pi / 180,
          65 * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.5, h * 0.018)
            ..color = const Color.fromRGBO(255, 255, 255, 0.35));
      if (on) {
        c.drawCircle(av, avr + h * 0.04, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.03
          ..color = _a(tc, 0.35 + 0.35 * pulse));
        final Rect cr = g.chip[i];
        final RRect rr = RRect.fromRectAndRadius(cr, Radius.circular(cr.height * 0.5));
        c.drawRRect(
            rr.inflate(h * 0.03),
            Paint()
              ..color = _a(tc, 0.35 + 0.25 * pulse)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.04));
        c.drawRRect(rr, Paint()..color = _a(tc, 0.85));
        c.drawLine(Offset(cr.left + cr.height * 0.5, cr.top + 0.5), Offset(cr.right - cr.height * 0.5, cr.top + 0.5), Paint()
          ..strokeWidth = 1
          ..color = const Color.fromRGBO(255, 255, 255, 0.45));
      }
    }
    // raised score plate: metallic bevel rim + deep glass face
    final List<Offset> pp = _platePts(g.plate);
    _grad(c, pp, _steel, const Color(0xFF2A3360));
    final List<Offset> pf = _platePts(g.plate, h * 0.04);
    _grad(c, pf, const Color(0xFF1A2558), const Color(0xFF050816));
    final double cy2 = g.plate.top + g.plate.height * 0.42;
    _grad(c, <Offset>[for (final Offset p in pf) Offset(p.dx, math.min(p.dy, cy2))], const Color.fromRGBO(255, 255, 255, 0.14),
        const Color.fromRGBO(255, 255, 255, 0));
    c.drawLine(pf[0], pf[1], Paint()
      ..strokeWidth = 1.6
      ..color = const Color.fromRGBO(255, 255, 255, 0.5));
    final Color ac = _team[d.turn == 1 ? 1 : 0];
    c.drawLine(pf[3] + Offset(h * 0.1, -1), pf[2] + Offset(-h * 0.1, -1), Paint()
      ..strokeWidth = h * 0.03
      ..strokeCap = StrokeCap.round
      ..color = _a(ac, 0.55 + 0.3 * pulse));
    final Offset mid = Offset(g.plate.center.dx, g.plate.top + h * 0.28);
    final Paint dot = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.7);
    c.drawCircle(mid + Offset(0, -h * 0.05), h * 0.022, dot);
    c.drawCircle(mid + Offset(0, h * 0.05), h * 0.022, dot);
    // clock pill
    final RRect pill = RRect.fromRectAndRadius(g.clock, Radius.circular(g.clock.height * 0.5));
    c.drawRRect(pill, Paint()..color = d.sudden ? const Color.fromRGBO(89, 64, 0, 0.7) : const Color.fromRGBO(0, 0, 0, 0.5));
    c.drawRRect(pill, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = d.sudden ? const Color.fromRGBO(255, 209, 87, 0.8) : const Color.fromRGBO(255, 255, 255, 0.14));
    _btn(c, g.pb, pDown, false);
    if (loadout) _btn(c, g.lb, lDown, true);
  }

  void _btn(Canvas c, Rect rect, bool down, bool sliders) {
    final double r = math.min(rect.width, rect.height) * 0.5;
    final Offset ctr = rect.center + (down ? Offset(0, r * 0.06) : Offset.zero);
    c.drawCircle(ctr + Offset(0, r * 0.12), r, Paint()..color = const Color.fromRGBO(0, 0, 0, 0.4));
    c.drawCircle(
        ctr,
        r,
        Paint()
          ..shader = ui.Gradient.linear(ctr + Offset(-r, -r) * 0.7, ctr + Offset(r, r) * 0.7,
              const <Color>[Color(0xFF9FB4FF), Color(0xFF1A2250)]));
    c.drawCircle(ctr, r * 0.86, Paint()..color = const Color(0xFF0B1233));
    c.drawArc(Rect.fromCircle(center: ctr, radius: r * 0.86), math.pi * 1.05, math.pi * 0.7, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..color = const Color.fromRGBO(255, 255, 255, 0.22));
    final Color col = down ? const Color(0xFF39D5FF) : const Color.fromRGBO(235, 245, 255, 1);
    if (sliders) {
      final Paint lp = Paint()
        ..strokeWidth = math.max(2.0, r * 0.08)
        ..strokeCap = StrokeCap.round
        ..color = col;
      const List<double> kx = <double>[-0.2, 0.22, -0.02];
      for (int i = 0; i < 3; i++) {
        final double y = ctr.dy + (i - 1) * r * 0.36;
        c.drawLine(Offset(ctr.dx - r * 0.46, y), Offset(ctr.dx + r * 0.46, y), lp);
        c.drawCircle(Offset(ctr.dx + kx[i] * r, y), r * 0.11, Paint()..color = col);
      }
      return;
    }
    final double bw = r * 0.17;
    final double bh = r * 0.78;
    for (final double sx in const <double>[-1.0, 1.0]) {
      c.drawRect(Rect.fromLTWH(ctr.dx + sx * r * 0.2 - bw * 0.5, ctr.dy - bh * 0.5, bw, bh), Paint()..color = col);
    }
  }

  @override
  bool shouldRepaint(covariant _HudPainter old) => true;
}
