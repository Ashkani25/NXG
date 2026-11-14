// Painters of DiscMatchView: draw functions ported 1:1 from match_view.gd (_draw_bg, _draw_field,
// _draw_outline, _draw_shadows, _draw_glows, _draw_turn_ring, _draw_discs, _draw_trail, _draw_ball,
// _draw_goals, _draw_lights, _draw_aim, _draw_parts, _draw_flash).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../core/engine.dart';
import 'df_images.dart';
import 'disc_match_view.dart';

const List<Color> _teamGlow = <Color>[Color(0xFF3BB6FF), Color(0xFFFF5B6B)];
const Color _arwTail = Color(0xFFF4BC5C);
const Color _arwMid = Color(0xFFEC9450);
const Color _arwTip = Color(0xFFD4524E);
const double _aimMaxK = 4.0;
const double _aimMinK = 0.35;

Color _rgba(double r, double g, double b, double a) => Color.fromRGBO(
    (r.clamp(0.0, 1.0) * 255).round(), (g.clamp(0.0, 1.0) * 255).round(), (b.clamp(0.0, 1.0) * 255).round(), a.clamp(0.0, 1.0).toDouble());
double _r(Color c) => c.r;
double _g(Color c) => c.g;
double _b(Color c) => c.b;
Color _darkened(Color c, double k) => _rgba(_r(c) * (1 - k), _g(c) * (1 - k), _b(c) * (1 - k), c.a);
Color _lightened(Color c, double k) =>
    _rgba(_r(c) + (1 - _r(c)) * k, _g(c) + (1 - _g(c)) * k, _b(c) + (1 - _b(c)) * k, c.a);
Color _withA(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0).toDouble());

/// Static backdrop: dark fill + blurred, darkened stadium art (match_view.gd _draw_bg).
class DfBackdropPainter extends CustomPainter {
  DfBackdropPainter(this.m, {super.repaint});
  final DfRender m;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF02040C));
    final ui.Image? img = m.fieldImg;
    if (img == null) return;
    final double fw = m.e.f.w, fh = m.e.f.h;
    final double k = math.max(size.width / fw, size.height / fh) * 1.05;
    final Rect dst = Rect.fromLTWH((size.width - fw * k) / 2, (size.height - fh * k) / 2, fw * k, fh * k);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.low
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.clamp),
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color.fromRGBO(2, 4, 14, 0.62));
  }

  @override
  bool shouldRepaint(covariant DfBackdropPainter old) => old.m != m;
}

/// Everything in world space + the screen flash.
class DfWorldPainter extends CustomPainter {
  DfWorldPainter(this.m, {super.repaint});
  final DfRender m;

  Engine get e => m.e;
  double get lf => m.flipped ? -1.0 : 1.0;

  final Paint _img = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    if (m.pos.length != e.bodies.length) return;
    final double z = m.s * (1.0 + m.zoom);
    final Offset pP = Offset(m.ox, m.oy) + Offset(e.cx, e.cy) * (m.s - z) + m.shk;
    canvas.save();
    if (m.flipped) {
      canvas.translate(m.W, m.H);
      canvas.rotate(math.pi);
    }
    canvas.translate(pP.dx, pP.dy);
    canvas.scale(z, z);
    _field(canvas);
    _outline(canvas);
    final DfSprites? sp = m.sp;
    if (sp != null) _shadows(canvas, sp);
    if (m.fancy && sp != null) _glows(canvas, sp);
    _turnRing(canvas, sp);
    _discs(canvas, sp);
    _trail(canvas);
    _ball(canvas, sp);
    _goals(canvas);
    if (sp != null) _lights(canvas, sp);
    _aim(canvas);
    _parts(canvas, sp);
    _fx(canvas, sp);
    canvas.restore();
    if (e.flash > 0) canvas.drawRect(Offset.zero & size, Paint()..color = _rgba(1, 1, 1, e.flash * 0.28));
  }

  // ---------------------------------------------------------------- static
  void _field(Canvas c) {
    final ui.Image? img = m.fieldImg;
    if (img == null) {
      c.drawRect(Rect.fromLTRB(e.fl, e.ft, e.fr, e.fb), Paint()..color = const Color(0xFF1F6B32));
      return;
    }
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromLTWH(0, 0, e.f.w, e.f.h), _img);
  }

  void _outline(Canvas c) {
    final Rect r = Rect.fromLTRB(e.fl, e.ft, e.fr, e.fb);
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    if (m.fancy) {
      c.drawRect(r, p
        ..strokeWidth = 9
        ..color = const Color.fromRGBO(120, 220, 255, 0.12));
    }
    c.drawRect(r, p
      ..strokeWidth = 3
      ..color = const Color.fromRGBO(120, 220, 255, 0.35));
    p
      ..color = const Color.fromRGBO(255, 255, 255, 0.55)
      ..strokeWidth = 3;
    const double rad = 34.0;
    final List<List<double>> cs = <List<double>>[
      <double>[e.fl, e.ft, 0],
      <double>[e.fr, e.ft, 90],
      <double>[e.fr, e.fb, 180],
      <double>[e.fl, e.fb, 270],
    ];
    for (final List<double> k in cs) {
      c.drawArc(Rect.fromCircle(center: Offset(k[0], k[1]), radius: rad), k[2] * math.pi / 180, math.pi / 2, false, p);
    }
  }

  // ---------------------------------------------------------------- sprites
  void _sprite(Canvas c, ui.Image img, Rect dst, Color col, {bool add = false}) {
    _img
      ..colorFilter = ColorFilter.mode(col, BlendMode.modulate)
      ..blendMode = add ? BlendMode.plus : BlendMode.srcOver;
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _img);
    _img
      ..colorFilter = null
      ..blendMode = BlendMode.srcOver;
  }

  void _shadow(Canvas c, DfSprites sp, double x, double y, double r, double a) {
    final double rr = r * 1.3;
    _sprite(c, sp.shadow, Rect.fromLTWH(x + lf * r * 0.14 - rr, y + lf * r * 0.26 - rr, 2 * rr, 2 * rr), _rgba(1, 1, 1, a));
  }

  void _shadows(Canvas c, DfSprites sp) {
    for (int i = 0; i < e.bodies.length; i++) {
      final Body b = e.bodies[i];
      final Offset p = m.pos[i];
      if (b == e.ball) {
        _shadow(c, sp, p.dx, p.dy, b.r * (1 + b.sq * 0.08), 0.6);
        final double rb = b.r * 0.95;
        _sprite(c, sp.shadow, Rect.fromLTWH(p.dx - rb, p.dy + lf * b.r * 0.35 - rb * 0.7, 2 * rb, 1.4 * rb), _rgba(1, 1, 1, 0.55));
      } else {
        final double r = b.r * (1 + b.sq * 0.07);
        _shadow(c, sp, p.dx, p.dy, r, 0.5);
        final double rc = r * 1.12;
        final double th = math.max(3.0, r * 0.13);
        _sprite(c, sp.shadow, Rect.fromLTWH(p.dx - rc, p.dy + lf * th * 1.6 - rc, 2 * rc, 2 * rc), _rgba(1, 1, 1, 0.7));
      }
    }
  }

  void _strip(Canvas c, List<Pt> pts, Offset head, double width, Color col) {
    final int n = pts.length + 1;
    if (n < 2) return;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    Offset prev = Offset(pts[0].x, pts[0].y);
    for (int i = 1; i < n; i++) {
      final Offset q = i == n - 1 ? head : Offset(pts[i].x, pts[i].y);
      final double k = (i + 1) / n;
      p
        ..strokeWidth = math.max(0.6, width * k)
        ..color = _withA(col, col.a * k);
      c.drawLine(prev, q, p);
      prev = q;
    }
  }

  void _glows(Canvas c, DfSprites sp) {
    for (int i = 0; i < e.bodies.length; i++) {
      final Body b = e.bodies[i];
      if (b == e.ball || b.team > 1) continue;
      if (b.tr.length > 1) _strip(c, b.tr, m.pos[i], b.r * 0.85, _withA(_teamGlow[b.team], 0.16));
    }
    final Body bl = e.ball;
    final double spd = math.sqrt(bl.vx * bl.vx + bl.vy * bl.vy);
    if (spd > 300) {
      final Offset bp = m.ballPos();
      final double a = ((spd - 300) / 1800.0).clamp(0.0, 1.0) * 0.35;
      final double r2 = bl.r * 3.2;
      final Color cc = m.trailCols[0];
      _sprite(c, sp.dot, Rect.fromLTWH(bp.dx - r2, bp.dy - r2, 2 * r2, 2 * r2), _rgba(_r(cc) * 1.4, _g(cc) * 1.4, _b(cc) * 1.4, a), add: true);
    }
  }

  void _turnRing(Canvas c, DfSprites? sp) {
    if (e.phase != Phase.aim) return;
    final int tm = e.turn;
    final Color tc = m.ringColor(tm);
    final double pulse = 0.5 + 0.5 * math.sin(m.t * 3.2);
    final Body? sel = e.drag?.b;
    final Paint st = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (int i = 0; i < e.bodies.length; i++) {
      final Body b = e.bodies[i];
      if (b == e.ball || b.team != tm) continue;
      final Offset p = m.pos[i];
      final bool on = b == sel;
      final double k = on ? 1.0 : 0.55;
      final double rr = b.r * (1 + b.sq * 0.07);
      if (sp != null) {
        final double hr = rr * (1.55 + 0.06 * pulse);
        _sprite(c, sp.dot, Rect.fromLTWH(p.dx - hr, p.dy - hr, 2 * hr, 2 * hr), _withA(tc, (0.30 + 0.12 * pulse) * k));
      }
      c.drawCircle(p, rr + 8, st
        ..strokeWidth = 12
        ..color = _withA(tc, (0.28 + 0.14 * pulse) * k));
      c.drawCircle(p, rr + 4, st
        ..strokeWidth = 5
        ..color = _withA(tc, (0.80 + 0.20 * pulse) * k));
      if (on) {
        c.drawCircle(p, rr + 4, st
          ..strokeWidth = 1.6
          ..color = _rgba(1, 1, 1, 0.35 + 0.2 * pulse));
      }
    }
  }

  void _discs(Canvas c, DfSprites? sp) {
    final Paint fill = Paint()..isAntiAlias = true;
    final Paint st = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (int i = 0; i < e.bodies.length; i++) {
      final Body b = e.bodies[i];
      if (b == e.ball || b.team > 1) continue;
      final Offset p = m.pos[i];
      final double r = b.r * (1 + b.sq * 0.07);
      final bool dark = e.phase == Phase.aim && b.team != e.turn;
      final double th = math.max(3.0, r * 0.13);
      final Offset down = Offset(0, th * lf);
      final Color tg = _teamGlow[b.team];
      final Color side = Color.lerp(_darkened(tg, 0.62), const Color.fromRGBO(5, 10, 26, 1), 0.4)!;
      c.drawCircle(p + down, r, fill..color = _darkened(side, 0.35));
      c.drawCircle(p + down * 0.5, r, fill..color = side);
      final double lipA = lf > 0 ? 0.12 : math.pi + 0.12;
      c.drawArc(Rect.fromCircle(center: p + down * 0.5, radius: r - 0.5), lipA, math.pi - 0.24, false, st
        ..strokeWidth = 1.2
        ..color = _withA(_lightened(side, 0.35), 0.55));
      final ui.Image? tex = m.teamImg[b.team];
      if (tex != null) {
        final double iw = tex.width.toDouble(), ih = tex.height.toDouble();
        final double k = 2 * r / iw;
        final double ca = math.cos(b.ang) * k, sa = math.sin(b.ang) * k;
        final double tx = p.dx - (ca * iw / 2 - sa * ih / 2);
        final double ty = p.dy - (sa * iw / 2 + ca * ih / 2);
        final Float64List mx = Float64List.fromList(<double>[ca, sa, 0, 0, -sa, ca, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
        final Paint ip = Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.medium
          ..shader = ImageShader(tex, TileMode.clamp, TileMode.clamp, mx, filterQuality: FilterQuality.medium);
        if (dark) ip.colorFilter = const ColorFilter.mode(Color.fromRGBO(204, 204, 209, 1), BlendMode.modulate);
        c.drawCircle(p, r * 0.985, ip);
      } else {
        c.drawCircle(p, r, fill..color = b.team == 1 ? const Color(0xFF3A0D16) : const Color(0xFF0D1A3A));
      }
      if (sp != null) {
        final Rect gr = Rect.fromLTWH(p.dx - r, p.dy - r, 2 * r, 2 * r);
        if (m.flipped) {
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(math.pi);
          c.translate(-p.dx, -p.dy);
          _sprite(c, sp.gloss, gr, const Color(0xFFFFFFFF));
          c.restore();
        } else {
          _sprite(c, sp.gloss, gr, const Color(0xFFFFFFFF));
        }
      }
      final double a0 = lf > 0 ? math.pi * 1.05 : math.pi * 0.05;
      c.drawArc(Rect.fromCircle(center: p, radius: r - 1.2), a0, math.pi * 0.6, false, st
        ..strokeWidth = 2.2
        ..color = _rgba(1, 1, 1, 0.55));
      c.drawCircle(p, r - 0.6, st
        ..strokeWidth = 1.0
        ..color = _rgba(1, 1, 1, 0.16));
    }
  }

  void _trail(Canvas c) {
    final List<TrailPt> tr = e.trail;
    final int n0 = tr.length;
    if (n0 < 2) return;
    final double bw = e.ball.r;
    final Offset head = m.ballPos();
    final double hk = m.fancy ? 1.5 : 1.0;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..blendMode = m.fancy ? BlendMode.plus : BlendMode.srcOver;
    const List<List<double>> layers = <List<double>>[
      <double>[2.2, 0.16, 0],
      <double>[1.1, 0.42, 1],
      <double>[0.42, 0.95, 2],
    ];
    final int n = n0 + 1;
    for (final List<double> layer in layers) {
      final Color cc = m.trailCols[layer[2].toInt()];
      Offset prev = Offset(tr[0].x, tr[0].y);
      for (int i = 1; i < n; i++) {
        final Offset q = i < n0 ? Offset(tr[i].x, tr[i].y) : head;
        final double a = i < n0 ? tr[i].a : tr[n0 - 1].a;
        final double k = i < n0 ? i / n0 : 1.0;
        final double w = math.max(0.6, bw * layer[0] * k * a);
        final double al = math.min(1.0, layer[1] * a * (0.35 + 0.65 * k));
        p
          ..strokeWidth = w
          ..color = _rgba(_r(cc) * hk, _g(cc) * hk, _b(cc) * hk, al);
        c.drawLine(prev, q, p);
        prev = q;
      }
    }
  }

  // ball: textured sphere mesh (polar grid) mapped through the engine's rotation matrix
  static const int _rings = 7;
  static const int _segs = 18;
  static List<double>? _gx;
  static List<double>? _gy;
  static List<int>? _gi;

  static void _buildGrid() {
    final List<double> xs = <double>[0];
    final List<double> ys = <double>[0];
    for (int ri = 1; ri <= _rings; ri++) {
      final double rr = ri / _rings;
      for (int si = 0; si < _segs; si++) {
        final double a = si / _segs * math.pi * 2;
        xs.add(math.cos(a) * rr);
        ys.add(math.sin(a) * rr);
      }
    }
    final List<int> idx = <int>[];
    for (int si = 0; si < _segs; si++) {
      idx
        ..add(0)
        ..add(1 + si)
        ..add(1 + (si + 1) % _segs);
    }
    for (int ri = 1; ri < _rings; ri++) {
      final int a0 = 1 + (ri - 1) * _segs;
      final int b0 = 1 + ri * _segs;
      for (int si = 0; si < _segs; si++) {
        final int s1 = (si + 1) % _segs;
        idx
          ..add(a0 + si)
          ..add(b0 + si)
          ..add(b0 + s1)
          ..add(a0 + si)
          ..add(b0 + s1)
          ..add(a0 + s1);
      }
    }
    _gx = xs;
    _gy = ys;
    _gi = idx;
  }

  void _ball(Canvas c, DfSprites? sp) {
    final Body b = e.ball;
    final Offset p = m.ballPos();
    final double r = b.r * (1 + b.sq * 0.08);
    final ui.Image? img = m.ballImg;
    if (img == null) {
      c.drawCircle(p, r, Paint()..color = const Color(0xFFFFFFFF));
    } else {
      if (_gx == null) _buildGrid();
      final List<double> gx = _gx!, gy = _gy!;
      final List<double> R = b.R;
      final double iw = img.width.toDouble(), ih = img.height.toDouble();
      final List<Offset> ps = <Offset>[];
      final List<Offset> uvs = <Offset>[];
      for (int i = 0; i < gx.length; i++) {
        final double x = gx[i], y = gy[i];
        final double zz = math.sqrt(math.max(0.0, 1 - x * x - y * y));
        // q = (dot(c0, n), dot(c1, n), dot(c2, n)) with c0=(R0,R3,R6), c1=(R1,R4,R7), c2=(R2,R5,R8)
        double qx = R[0] * x + R[3] * y + R[6] * zz;
        final double qy = R[1] * x + R[4] * y + R[7] * zz;
        final double qz = R[2] * x + R[5] * y + R[8] * zz;
        if (qz < 0) qx = -qx;
        ps.add(Offset(p.dx + x * r, p.dy + y * r));
        uvs.add(Offset((qx * 0.93 * 0.5 + 0.5) * iw, (qy * 0.93 * 0.5 + 0.5) * ih));
      }
      final ui.Vertices v = ui.Vertices(ui.VertexMode.triangles, ps, textureCoordinates: uvs, indices: _gi);
      final Paint bp = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium
        ..shader = ImageShader(img, TileMode.clamp, TileMode.clamp, Matrix4Identity.list, filterQuality: FilterQuality.medium);
      c.drawVertices(v, BlendMode.modulate, bp);
      v.dispose();
    }
    if (sp != null) {
      final Rect lr = Rect.fromLTWH(p.dx - r, p.dy - r, 2 * r, 2 * r);
      if (m.flipped) {
        c.save();
        c.translate(p.dx, p.dy);
        c.rotate(math.pi);
        c.translate(-p.dx, -p.dy);
      }
      final Rect src = Rect.fromLTWH(0, 0, sp.ballMul.width.toDouble(), sp.ballMul.height.toDouble());
      c.drawImageRect(sp.ballMul, src, lr, Paint()
        ..blendMode = BlendMode.multiply
        ..filterQuality = FilterQuality.medium);
      c.drawImageRect(sp.ballAdd, src, lr, Paint()
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.medium
        ..color = _rgba(1, 1, 1, m.fancy ? 1.0 : 0.75));
      if (m.flipped) c.restore();
    }
  }

  void _goals(Canvas c) {
    final ui.Image? img = m.goalImg;
    if (img == null) return;
    final double gw = e.gg.w, gh = e.gg.h, gx = e.gg.x;
    final Rect src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    for (int i = 0; i < 2; i++) {
      final Goal g = e.goals[i];
      final double sx = math.sin(m.t * 40) * 6 * e.shake[i];
      final Rect dst = Rect.fromLTWH(gx + sx, g.y - gh, gw, gh);
      if (g.d < 0) {
        c.drawImageRect(img, src, dst, _img);
      } else {
        c.save();
        c.translate(0, 2 * g.y);
        c.scale(1, -1);
        c.drawImageRect(img, src, dst, _img);
        c.restore();
      }
    }
  }

  void _lights(Canvas c, DfSprites sp) {
    for (int i = 0; i < 2; i++) {
      final double rp = e.ripple[i];
      if (rp <= 0) continue;
      final Goal g = e.goals[i];
      final double cy = g.y + g.d * e.depth * 0.45;
      final double rr = 90.0 + (1.0 - rp) * 120.0;
      final double k = m.fancy ? 1.6 : 1.0;
      _sprite(c, sp.dot, Rect.fromCenter(center: Offset(e.rippleX[i], cy), width: 2 * rr * 1.4, height: 2 * rr * 0.7),
          _rgba(1.0 * k, 0.86 * k, 0.4 * k, rp * 0.55),
          add: true);
    }
  }

  // ---------------------------------------------------------------- aim arrow (user design, code drawn)
  static double _rayRoom(Offset p, Offset u, Rect r) {
    double tmax = 1e9;
    if (u.dx > 1e-4) {
      tmax = math.min(tmax, (r.right - p.dx) / u.dx);
    } else if (u.dx < -1e-4) {
      tmax = math.min(tmax, (r.left - p.dx) / u.dx);
    }
    if (u.dy > 1e-4) {
      tmax = math.min(tmax, (r.bottom - p.dy) / u.dy);
    } else if (u.dy < -1e-4) {
      tmax = math.min(tmax, (r.top - p.dy) / u.dy);
    }
    return math.max(0.0, tmax);
  }

  static List<Offset> _fillet(List<Offset> pts, List<double> radii, [int seg = 5]) {
    final List<Offset> o = <Offset>[];
    final int n = pts.length;
    for (int i = 0; i < n; i++) {
      final Offset p = pts[i];
      final double rad = radii[i];
      if (rad <= 0.01) {
        o.add(p);
        continue;
      }
      final Offset a = pts[(i - 1 + n) % n];
      final Offset b = pts[(i + 1) % n];
      final double la = (a - p).distance;
      final double lb = (b - p).distance;
      if (la < 0.01 || lb < 0.01) {
        o.add(p);
        continue;
      }
      final double t = math.min(rad, math.min(la, lb) * 0.45);
      final Offset p1 = p + (a - p) / la * t;
      final Offset p2 = p + (b - p) / lb * t;
      for (int k = 0; k <= seg; k++) {
        final double u = k / seg;
        o.add(Offset.lerp(Offset.lerp(p1, p, u)!, Offset.lerp(p, p2, u)!, u)!);
      }
    }
    return o;
  }

  void _aim(Canvas c) {
    final AimInfo? a = e.aimInfo();
    if (a == null || a.p <= 0) {
      m.aimOn = false;
      return;
    }
    if (!m.aimOn) {
      m.aimUx = a.ux;
      m.aimUy = a.uy;
      m.aimP = a.p;
      m.aimOn = true;
    } else {
      m.aimUx += (a.ux - m.aimUx) * 0.55;
      m.aimUy += (a.uy - m.aimUy) * 0.55;
      m.aimP += (a.p - m.aimP) * 0.6;
    }
    double ul = math.sqrt(m.aimUx * m.aimUx + m.aimUy * m.aimUy);
    if (ul == 0) ul = 1.0;
    final Offset u = Offset(m.aimUx / ul, m.aimUy / ul);
    final double pw = m.aimP.clamp(0.0, 1.0).toDouble();
    final Body b = a.b;
    final int bi = e.bodies.indexOf(b);
    final Offset p = bi >= 0 && bi < m.pos.length ? m.pos[bi] : Offset(b.x, b.y);
    final double r = b.r;
    final double d0 = r + 4.0;
    final double want = r * (_aimMinK + (_aimMaxK - _aimMinK) * pw);
    final double room = _rayRoom(p, u, m.visRect(10.0 / math.max(0.01, m.s))) - d0;
    final double tt = math.min(want, room).clamp(math.min(16.0, want), want).toDouble();
    final double sc = room < want ? (tt / want).clamp(0.55, 1.0).toDouble() : 1.0;
    final double hw = r * (0.62 + 0.3 * pw) * sc;
    final double hl = math.min(hw * 1.08, tt * 0.62);
    final double sw = hw * 0.64;
    final double al = 0.55 + 0.45 * pw;
    final double rest = math.max(0.0, tt - hl);
    final double k = rest / 1155.0;
    double x = d0;
    final List<List<double>> segs = <List<double>>[];
    if (rest > sw * 3.2) {
      segs.add(<double>[x, x + 205 * k]);
      x += 360 * k;
      segs.add(<double>[x, x + 310 * k]);
      x += 485 * k;
      segs.add(<double>[x, x + 310 * k]);
      x += 310 * k;
    } else {
      segs.add(<double>[x, x + rest]);
      x += rest;
    }
    final double xn = x;
    final double xt = xn + hl;
    final double hs = sw * 0.5;
    final double ang = math.atan2(u.dy, u.dx);
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(ang);
    final Shader grad = ui.Gradient.linear(Offset(d0, 0), Offset(math.max(d0 + 1, xt), 0), <Color>[
      _withA(const Color(0xFFEE9A52), al),
      _withA(_arwTail, al),
      _withA(_arwMid, al),
      _withA(_arwTip, al),
    ], const <double>[0, 0.3, 0.62, 1]);
    for (int pass = 0; pass < 2; pass++) {
      final bool shadow = pass == 0;
      Offset off = Offset.zero;
      if (shadow) {
        final double ca = math.cos(-ang), sa = math.sin(-ang);
        off = Offset(3.0 * ca - 4.0 * sa, 3.0 * sa + 4.0 * ca) * (m.flipped ? -1.0 : 1.0);
      }
      final Paint pp = Paint()..isAntiAlias = true;
      if (shadow) {
        pp.color = _rgba(0, 0, 0, al * 0.28);
      } else {
        pp.shader = grad;
      }
      for (int si = 0; si < segs.length - 1; si++) {
        final List<double> sg = segs[si];
        final double rr = math.min(sw * 0.22, (sg[1] - sg[0]) * 0.3);
        final List<Offset> q = <Offset>[
          Offset(sg[0], -hs) + off,
          Offset(sg[1], -hs) + off,
          Offset(sg[1], hs) + off,
          Offset(sg[0], hs) + off,
        ];
        c.drawPath(Path()..addPolygon(_fillet(q, <double>[rr, rr, rr, rr]), true), pp);
      }
      final double sx = segs[segs.length - 1][0];
      final double hh = hw * 0.5;
      final List<Offset> body = <Offset>[
        Offset(sx, -hs) + off,
        Offset(xn, -hs) + off,
        Offset(xn, -hh) + off,
        Offset(xt, 0) + off,
        Offset(xn, hh) + off,
        Offset(xn, hs) + off,
        Offset(sx, hs) + off,
      ];
      final double br = sw * 0.12;
      c.drawPath(
          Path()..addPolygon(_fillet(body, <double>[br, br * 0.6, hw * 0.08, hw * 0.07, hw * 0.08, br * 0.6, br]), true), pp);
    }
    c.drawLine(
        Offset(segs[segs.length - 1][0] + 4, -hs * 0.55),
        Offset(xn - 2, -hs * 0.55),
        Paint()
          ..isAntiAlias = true
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.5, sw * 0.12)
          ..color = _rgba(1, 1, 1, 0.16 * al));
    c.restore();
    final double prev = e.cfg.stats != null ? Engine.aimPreview(e.statsOf(b.team).accuracy) : 1.0;
    final int steps = math.max(2, ((3 + pw * 4) * prev).round());
    final Paint dp = Paint()..isAntiAlias = true;
    for (int kk = 1; kk <= steps; kk++) {
      final double d = xt + 8 + kk * 12;
      if (d > room + d0 || d > xt + r * 0.7) break;
      final double f = 1.0 - kk / (steps + 1);
      c.drawCircle(p + u * d, 2.0 + 2.0 * f, dp..color = _withA(_arwTip, 0.55 * f * al));
    }
  }

  void _parts(Canvas c, DfSprites? sp) {
    if (e.parts.isEmpty) return;
    final double hk = m.fancy ? 1.6 : 1.0;
    final Paint cp = Paint()..isAntiAlias = true;
    for (final Particle q in e.parts) {
      final double k = math.max(0.0, q.l / q.m);
      final double rr = q.r * (q.k == 3 ? 1.3 : 0.6 + k * 0.8);
      final double a = math.min(1.0, k * 1.2);
      final Color qc = Color(q.c);
      final Color col = _rgba(_r(qc) * hk, _g(qc) * hk, _b(qc) * hk, a);
      if (m.fancy && sp != null) {
        final double big = rr * 2.6;
        _sprite(c, sp.dot, Rect.fromLTWH(q.x - big, q.y - big, 2 * big, 2 * big), col, add: true);
      } else {
        c.drawCircle(Offset(q.x, q.y), rr, cp..color = col);
      }
    }
  }

  void _fx(Canvas c, DfSprites? sp) {
    if (m.fx.isEmpty) return;
    final Paint cp = Paint()..isAntiAlias = true;
    for (final DfFx f in m.fx) {
      final double u = f.l / f.life;
      if (f.k == 0) {
        // spark: bright white -> cyan -> blue, fading
        final Color col = u < 0.4
            ? Color.lerp(const Color(0xFFFFFFFF), const Color(0xCC99E6FF), u / 0.4)!
            : Color.lerp(const Color(0xCC99E6FF), const Color(0x004D99FF), (u - 0.4) / 0.6)!;
        if (sp != null) {
          final double rr = f.size / 2;
          _sprite(c, sp.dot, Rect.fromLTWH(f.x - rr, f.y - rr, 2 * rr, 2 * rr), col, add: true);
        } else {
          c.drawCircle(Offset(f.x, f.y), f.size / 4, cp..color = col);
        }
      } else {
        final double a = u < 0.8 ? 1.0 : (1 - (u - 0.8) / 0.2);
        c.save();
        c.translate(f.x, f.y);
        c.rotate(f.rot);
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: 6 * f.size, height: 12 * f.size), cp..color = _withA(f.color, a));
        c.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant DfWorldPainter old) => true;
}

/// Identity 4x4 matrix storage for ImageShader.
class Matrix4Identity {
  Matrix4Identity._();
  static final Float64List list = Float64List.fromList(<double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
}
