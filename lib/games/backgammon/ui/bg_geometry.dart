import 'dart:math';

import 'package:flutter/material.dart';

import '../core/backgammon_rules.dart';

/// One backgammon board layout in its own pixel space (scaled with FittedBox).
/// [BgLayout.classic] matches board_nx_gold.webp (1536x1024, used by the online
/// screen); [BgLayout.kit] matches the kit_v2 board (991x796 px measured with
/// PIL, scaled by 1024/796), whose borne-off trays are the right-hand slots.
class BgLayout {
  const BgLayout({
    required this.w,
    required this.h,
    required this.left,
    required this.right,
    required this.pointW,
    required this.top,
    required this.bottom,
    required this.mid,
    required this.topTip,
    required this.bottomTip,
    required this.d,
    required this.barX,
    required this.barLeft,
    required this.barRight,
    required this.trayX,
    required this.trayLeft,
    required this.trayRight,
    required this.slabW,
    required this.slabH,
    required this.slabStep,
    required this.diceCenter,
  });

  final double w;
  final double h;
  final List<double> left;
  final List<double> right;
  final double pointW;
  final double top;
  final double bottom;
  final double mid;
  final double topTip;
  final double bottomTip;
  final double d;
  final double barX;
  final double barLeft;
  final double barRight;
  final double trayX;
  final double trayLeft;
  final double trayRight;
  final double slabW;
  final double slabH;
  final double slabStep;
  final Offset diceCenter;

  static const BgLayout classic = BgLayout(
    w: 1536,
    h: 1024,
    left: <double>[182, 280.8, 379.6, 478.4, 577.2, 676],
    right: <double>[861, 959.2, 1057.4, 1155.6, 1253.8, 1352],
    pointW: 98,
    top: 48,
    bottom: 952,
    mid: 500,
    topTip: 342,
    bottomTip: 608,
    d: 86,
    barX: 769,
    barLeft: 728,
    barRight: 810,
    trayX: 1478,
    trayLeft: 1424,
    trayRight: 1532,
    slabW: 76,
    slabH: 13,
    slabStep: 15,
    diceCenter: Offset(429, 500),
  );

  static const BgLayout kit = BgLayout(
    w: 1275,
    h: 1024,
    left: <double>[198.8, 267.6, 336.4, 405.2, 474.1, 542.9],
    right: <double>[728.8, 798.2, 867.1, 935.9, 1004.7, 1074.2],
    pointW: 69,
    top: 67,
    bottom: 958,
    mid: 512,
    topTip: 354,
    bottomTip: 669,
    d: 64,
    barX: 637,
    barLeft: 590,
    barRight: 684,
    trayX: 1187,
    trayLeft: 1140,
    trayRight: 1236,
    slabW: 76,
    slabH: 12,
    slabStep: 14,
    diceCenter: Offset(371, 512),
  );

  bool get isKit => identical(this, kit);

  double pointX(int idx) {
    if (idx < 6) return right[5 - idx];
    if (idx < 12) return left[11 - idx];
    if (idx < 18) return left[idx - 12];
    return right[idx - 18];
  }

  bool isTop(int idx) => idx >= 12;

  Offset checkerCenter(int idx, int k, int count) {
    final double step = count <= 5 ? d : (4 * d) / (count - 1);
    final double x = pointX(idx);
    if (isTop(idx)) return Offset(x, top + d / 2 + 2 + k * step);
    return Offset(x, bottom - d / 2 - 2 - k * step);
  }

  Offset barCenter(int p, int k, int count) {
    final double base = d * 0.92;
    final double step = count <= 4 ? base : (3 * base) / (count - 1);
    final double gapY = identical(this, kit) ? d * 0.82 : 70;
    if (p == 0) return Offset(barX, mid + gapY + k * step);
    return Offset(barX, mid - gapY - k * step);
  }

  Offset slabCenter(int p, int k) {
    if (p == 0) return Offset(trayX, bottom - 4 - k * slabStep);
    return Offset(trayX, top + 4 + k * slabStep);
  }

  Rect pointRect(int idx) {
    final double x = pointX(idx);
    if (isTop(idx)) {
      return Rect.fromLTRB(x - pointW / 2, top - 10, x + pointW / 2, mid);
    }
    return Rect.fromLTRB(x - pointW / 2, mid, x + pointW / 2, bottom + 10);
  }

  Rect get barRect => Rect.fromLTRB(barLeft, top, barRight, bottom);

  Rect trayRect(int p) {
    if (p == 0) return Rect.fromLTRB(trayLeft, mid + 40, trayRight, h);
    return Rect.fromLTRB(trayLeft, 0, trayRight, mid - 40);
  }

  /// Returns a point index, [kBgBar], [kBgOff] (tray of [player]) or null.
  int? hitTest(Offset p, int player) {
    if (trayRect(player).contains(p)) return kBgOff;
    if (barRect.contains(p)) return kBgBar;
    for (int i = 0; i < 24; i++) {
      if (pointRect(i).contains(p)) return i;
    }
    return null;
  }

  Path trianglePath(int idx, {double inset = 0}) {
    final double x = pointX(idx);
    final double half = pointW / 2 - 3 - inset;
    final Path path = Path();
    if (isTop(idx)) {
      path.moveTo(x - half, top);
      path.lineTo(x + half, top);
      path.lineTo(x, topTip);
    } else {
      path.moveTo(x - half, bottom);
      path.lineTo(x + half, bottom);
      path.lineTo(x, bottomTip);
    }
    path.close();
    return path;
  }
}

/// Static facade over [BgLayout.classic] (board_nx_gold.webp), kept for the
/// online screen. The offline game uses [BgLayout.kit] directly.
class BgGeom {
  BgGeom._();

  static const BgLayout _c = BgLayout.classic;

  static const double w = 1536;
  static const double h = 1024;
  static const double pointW = 98;
  static const double top = 48;
  static const double bottom = 952;
  static const double mid = 500;
  static const double topTip = 342;
  static const double bottomTip = 608;
  static const double d = 86;
  static const double barX = 769;
  static const double barLeft = 728;
  static const double barRight = 810;
  static const double trayX = 1478;
  static const double trayLeft = 1424;
  static const double trayRight = 1532;
  static const double slabW = 76;
  static const double slabH = 13;
  static const double slabStep = 15;
  static const Offset diceCenter = Offset(429, 500);
  static const Rect barRect = Rect.fromLTRB(barLeft, top, barRight, bottom);

  static double pointX(int idx) => _c.pointX(idx);
  static bool isTop(int idx) => idx >= 12;
  static Offset checkerCenter(int idx, int k, int count) => _c.checkerCenter(idx, k, count);
  static Offset barCenter(int p, int k, int count) {
    final double base = d * 0.92;
    final double step = count <= 4 ? base : (3 * base) / (count - 1);
    if (p == 0) return Offset(barX, mid + 70 + k * step);
    return Offset(barX, mid - 70 - k * step);
  }

  static Offset slabCenter(int p, int k) => _c.slabCenter(p, k);
  static Rect pointRect(int idx) => _c.pointRect(idx);
  static Rect trayRect(int p) => _c.trayRect(p);
  static int? hitTest(Offset p, int player) => _c.hitTest(p, player);
  static Path trianglePath(int idx, {double inset = 0}) => _c.trianglePath(idx, inset: inset);
}

/// Procedural board used only if the board image fails to load.
class BgFallbackBoardPainter extends CustomPainter {
  const BgFallbackBoardPainter({this.layout = BgLayout.classic});

  final BgLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final BgLayout g = layout;
    final bool kit = g.isKit;
    final Rect all = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(all, const Radius.circular(40)),
      Paint()
        ..shader = LinearGradient(
          colors: kit
              ? const <Color>[Color(0xFF1B1550), Color(0xFF070616)]
              : const <Color>[Color(0xFF2A2210), Color(0xFF0D0B05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(all),
    );
    final Paint felt = Paint()..color = const Color(0xFF0E0E14);
    final double lx0 = g.left.first - g.pointW / 2 - 8;
    final double rx1 = g.right.last + g.pointW / 2 + 8;
    canvas.drawRect(Rect.fromLTRB(lx0, g.top - 4, g.barLeft - 2, g.bottom + 4), felt);
    canvas.drawRect(Rect.fromLTRB(g.barRight + 2, g.top - 4, rx1, g.bottom + 4), felt);
    if (kit) {
      canvas.drawRect(Rect.fromLTRB(g.trayLeft, g.top - 4, g.trayRight, g.bottom + 4), felt);
    }
    final Paint a = Paint()..color = kit ? const Color(0xFF22D3EE) : const Color(0xFFE2B33C);
    final Paint b = Paint()..color = kit ? const Color(0xFFC026D3) : const Color(0xFF26262E);
    for (int i = 0; i < 24; i++) {
      canvas.drawPath(g.trianglePath(i), i.isEven ? a : b);
    }
    canvas.drawRect(g.barRect,
        Paint()..color = kit ? const Color(0xFF0C0A26) : const Color(0xFF15120A));
    final Paint frame = Paint()
      ..color = kit ? const Color(0xFF6B8CFF) : const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawRRect(
        RRect.fromRectAndRadius(all.deflate(10), const Radius.circular(36)),
        frame);
  }

  @override
  bool shouldRepaint(covariant BgFallbackBoardPainter oldDelegate) =>
      oldDelegate.layout != layout;
}

/// Glow overlay: legal destinations, movable sources, selection, tray.
class BgHighlightPainter extends CustomPainter {
  BgHighlightPainter({
    required this.state,
    required this.player,
    required this.destinations,
    required this.destOff,
    required this.sources,
    required this.selected,
    required this.pulse,
    required this.fancy,
    this.layout = BgLayout.classic,
  }) : super(repaint: pulse);

  final BgState state;
  final int player;
  final Set<int> destinations;
  final bool destOff;
  final Set<int> sources;
  final int? selected;
  final Animation<double> pulse;
  final bool fancy;
  final BgLayout layout;

  Offset _top(int place) {
    if (place == kBgBar) {
      final int c = state.bar[player];
      return layout.barCenter(player, max(0, c - 1), max(1, c));
    }
    final int c = state.own(player, place);
    return layout.checkerCenter(place, max(0, c - 1), max(1, c));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double t = pulse.value;
    const Color glow = Color(0xFF2EE6D6);
    for (final int idx in destinations) {
      final Path tri = layout.trianglePath(idx, inset: 2);
      canvas.drawPath(
          tri, Paint()..color = glow.withValues(alpha: 0.18 + 0.22 * t));
      final Paint stroke = Paint()
        ..color = const Color(0xFF00C2FF).withValues(alpha: 0.65 + 0.35 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      if (fancy) {
        canvas.drawPath(
            tri,
            Paint()
              ..color = glow.withValues(alpha: 0.5 * t)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 16
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }
      canvas.drawPath(tri, stroke);
      // Landing marker where the checker would arrive.
      final int c = state.own(player, idx);
      final Offset at = layout.checkerCenter(idx, c, c + 1);
      canvas.drawCircle(
          at,
          layout.d / 2 - 6,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.25 + 0.2 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
    if (destOff) {
      final Rect r = layout.trayRect(player).deflate(6);
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(22));
      canvas.drawRRect(
          rr, Paint()..color = glow.withValues(alpha: 0.16 + 0.2 * t));
      canvas.drawRRect(
          rr,
          Paint()
            ..color = const Color(0xFF00C2FF).withValues(alpha: 0.7 + 0.3 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5);
    }
    for (final int s in sources) {
      if (s == selected) continue;
      canvas.drawCircle(
          _top(s),
          layout.d / 2 + 3,
          Paint()
            ..color = const Color(0xFFFFC857).withValues(alpha: 0.35 + 0.45 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
    if (selected != null) {
      final Offset c = _top(selected!);
      if (fancy) {
        canvas.drawCircle(
            c,
            layout.d / 2 + 8,
            Paint()
              ..color = glow.withValues(alpha: 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      }
      canvas.drawCircle(
          c,
          layout.d / 2 + 4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6);
    }
  }

  @override
  bool shouldRepaint(covariant BgHighlightPainter oldDelegate) => true;
}

/// Pip layout (unit square) for die faces.
List<Offset> bgPipLayout(int v) {
  const double a = 0.27;
  const double b = 0.73;
  const double c = 0.5;
  switch (v) {
    case 1:
      return const <Offset>[Offset(c, c)];
    case 2:
      return const <Offset>[Offset(a, a), Offset(b, b)];
    case 3:
      return const <Offset>[Offset(a, a), Offset(c, c), Offset(b, b)];
    case 4:
      return const <Offset>[Offset(a, a), Offset(b, a), Offset(a, b), Offset(b, b)];
    case 5:
      return const <Offset>[
        Offset(a, a),
        Offset(b, a),
        Offset(c, c),
        Offset(a, b),
        Offset(b, b)
      ];
    default:
      return const <Offset>[
        Offset(a, a),
        Offset(b, a),
        Offset(a, c),
        Offset(b, c),
        Offset(a, b),
        Offset(b, b)
      ];
  }
}

/// Ivory die face with carved pips (procedural: the die images only show
/// fixed faces, so they are used for the tumbling animation instead).
class BgDieFacePainter extends CustomPainter {
  const BgDieFacePainter(this.value, {this.used = false});
  final int value;
  final bool used;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.2));
    canvas.drawRRect(
        rr.shift(Offset(0, size.height * 0.06)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: used
                ? const <Color>[Color(0xFF8C8578), Color(0xFF5E584E)]
                : const <Color>[Color(0xFFFFFBEF), Color(0xFFE8DCC0)],
          ).createShader(r));
    canvas.drawRRect(
        rr.deflate(1.5),
        Paint()
          ..color = const Color(0xFFFFC857).withValues(alpha: used ? 0.2 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final double pr = size.width * 0.09;
    for (final Offset o in bgPipLayout(value)) {
      final Offset c = Offset(o.dx * size.width, o.dy * size.height);
      canvas.drawCircle(c, pr, Paint()..color = const Color(0xFF15110B));
      canvas.drawCircle(c.translate(-pr * 0.3, -pr * 0.3), pr * 0.35,
          Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
  }

  @override
  bool shouldRepaint(covariant BgDieFacePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.used != used;
}

/// Procedural checker used only if the checker images fail to load.
class BgCheckerPainter extends CustomPainter {
  const BgCheckerPainter(this.player, {this.kit = false});
  final int player;
  final bool kit;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    final List<Color> cols = player == 0
        ? (kit
            ? const <Color>[Color(0xFF8FF6FF), Color(0xFF0E7490)]
            : const <Color>[Color(0xFFF3D39A), Color(0xFFB98543)])
        : (kit
            ? const <Color>[Color(0xFFFF9BEA), Color(0xFF9D174D)]
            : const <Color>[Color(0xFF7A4429), Color(0xFF2E160B)]);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: cols)
              .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c,
        r * 0.7,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant BgCheckerPainter oldDelegate) =>
      oldDelegate.player != player || oldDelegate.kit != kit;
}
