// Headless physics sweep, v0.6.4 physics world ('stars'). Only measures; the contract lives in
// test/physics_natural_test.dart.
//   NO_PROXY=127.0.0.1,localhost NX_SWEEP=/path/out.md flutter test tool/snap/sweep_v064_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg([double pw = 7]) => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: [DiscStats(pw, 10), DiscStats(pw, 10)]);

Engine _lab(int keep, [double pw = 7]) {
  final e = Engine(_cfg(pw), rand: math.Random(3).nextDouble);
  final discs = e.bodies.where((b) => !identical(b, e.ball)).take(keep).toList();
  e.bodies
    ..clear()
    ..addAll(discs)
    ..add(e.ball);
  for (final b in e.bodies) {
    b.vx = b.vy = 0;
  }
  return e;
}

void _place(Body b, double x, double y, [double vx = 0, double vy = 0]) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);
double _dist(double ax, double ay, double bx, double by) => math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
final _out = StringBuffer();
void _log(String s) {
  // ignore: avoid_print
  print(s);
  _out.writeln(s);
}

String _f(double v, [int d = 0]) => v.toStringAsFixed(d);

void main() {
  tearDownAll(() {
    final p = Platform.environment['NX_SWEEP'];
    if (p != null) File(p).writeAsStringSync(_out.toString());
  });

  test('sweep', () {
    final e0 = _lab(0);
    _log('# Physics sweep v0.6.4 (pitch ${_f(e0.Fr - e0.Fl, 1)} x ${_f(e0.Fb - e0.Ft, 1)}, disc r ${kPhys.discR}, ball r ${kPhys.ballR}, '
        'goal mouth ${_f(e0.goals[0].x2 - e0.goals[0].x1)} x depth ${_f(e0.DEPTH)})\n');

    _log('## 1. Disc launch (alone, straight up the pitch from the bottom rail)');
    _log('| power | pull | launch px/s | path px | time to rest s |');
    _log('|---|---|---|---|---|');
    for (final pw in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]) {
      for (final pull in [.25, .6, 1.0]) {
        final e = _lab(1, pw), d = e.bodies.first;
        _place(e.ball, e.Fr - 60, e.CY);
        _place(d, e.CX - 200, e.Fb - 80);
        e.fire(d, 0, -LMAX * pull, LMAX * pull, true);
        final v0 = _spd(d);
        var t = 0.0, path = 0.0;
        while (t < 20 && _spd(d) > 0) {
          final x0 = d.x, y0 = d.y;
          e.update(1 / 60);
          t += 1 / 60;
          path += _dist(d.x, d.y, x0, y0);
        }
        _log('| ${pw.round()} | ${(pull * 100).round()}% | ${_f(v0)} | ${_f(path)} | ${_f(t, 2)} |');
      }
    }
    _log('');

    _log('## 2. Full-pull disc (power 7) strikes a still ball; offset = ball offset across the line (x sum of radii)');
    _log('| offset | disc px/s at contact | disc after | disc kept % | ball after | ball/disc | ball path px | ball time s |');
    _log('|---|---|---|---|---|---|---|---|');
    for (final off in [0.0, .5]) {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      final m = d.r + b.r;
      _place(b, e.CX - 250 + off * m, e.Fb - 330);
      _place(d, e.CX - 250, e.Fb - 120);
      e.fire(d, 0, -LMAX, LMAX, true);
      var vd = 0.0;
      for (var i = 0; i < 6000 && _spd(b) == 0; i++) {
        vd = _spd(d);
        e.update(1 / 2400);
      }
      final vdA = _spd(d), vbA = _spd(b);
      var t = 0.0, path = 0.0;
      while (t < 20 && _spd(b) > 0) {
        final x0 = b.x, y0 = b.y;
        e.update(1 / 60);
        t += 1 / 60;
        path += _dist(b.x, b.y, x0, y0);
      }
      _log('| ${_f(off * 100)}% | ${_f(vd)} | ${_f(vdA)} | ${_f(vdA / vd * 100, 1)}% | ${_f(vbA)} | ${_f(vbA / vd, 2)} | ${_f(path)} | ${_f(t, 2)} |');
    }
    _log('');

    _log('## 3. Disc-disc head-on (1500 px/s into a still disc, equal attributes)');
    {
      final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
      _place(e.ball, e.Fr - 60, e.Ft + 60);
      _place(c, e.CX, e.CY);
      _place(a, e.CX, e.CY + 250, 0, -1500);
      var va = 0.0;
      for (var i = 0; i < 6000 && _spd(c) == 0; i++) {
        va = _spd(a);
        e.update(1 / 2400);
      }
      final pBefore = va / a.im, pAfter = (a.vy / a.im + c.vy / c.im).abs();
      _log('striker ${_f(va)} -> ${_f(_spd(a))} px/s, struck leaves at ${_f(_spd(c))} px/s (${_f(_spd(c) / va * 100, 1)}%), momentum kept ${_f(pAfter / pBefore * 100, 2)}%\n');
    }

    _log('## 4. Ball (2000 px/s) strikes a still disc head-on');
    {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(d, e.CX, e.CY);
      _place(b, e.CX, e.CY + 260, 0, -2000);
      var vb = 0.0;
      for (var i = 0; i < 6000 && _spd(d) == 0; i++) {
        vb = _spd(b);
        e.update(1 / 2400);
      }
      _log('ball ${_f(vb)} px/s -> disc ${_f(_spd(d))} px/s (${_f(_spd(d) / vb * 100, 1)}%), ball after ${_f(b.vy)} px/s (+ = back)\n');
    }

    _log('## 5. Free ball roll (diagonal from the bottom-left)');
    _log('| start px/s | path px | time to rest s |');
    _log('|---|---|---|');
    for (final v in [4000.0, 3000.0, 1500.0, 600.0]) {
      final e = _lab(0), b = e.ball;
      _place(b, e.Fl + 120, e.Fb - 120, v * .6, -v * .8);
      var t = 0.0, path = 0.0;
      while (t < 20 && _spd(b) > 0) {
        final x0 = b.x, y0 = b.y;
        e.update(1 / 60);
        t += 1 / 60;
        path += _dist(b.x, b.y, x0, y0);
      }
      _log('| ${_f(v)} | ${_f(path)} | ${_f(t, 2)} |');
    }
    _log('');

    _log('## 6. Rails (1500 px/s into the left rail; angle between path and rail). Ball pf 1.0, disc power 7 (pf 1.13)');
    _log('| angle | body | speed kept | normal kept | along-rail kept | angle out |');
    _log('|---|---|---|---|---|---|');
    for (final deg in [15.0, 45.0, 90.0]) {
      for (final disc in [false, true]) {
        final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
        if (disc) _place(e.ball, e.Fr - 60, e.Fb - 60);
        final a = deg * math.pi / 180;
        final vx = -1500 * math.sin(a), vy = 1500 * math.cos(a);
        _place(b, e.Fl + b.r + 12, e.CY - 200, vx, vy);
        var pre = (vx, vy);
        for (var i = 0; i < 6000; i++) {
          final before = (b.vx, b.vy);
          e.update(1 / 6000);
          if (before.$1 < 0 && b.vx >= 0) {
            pre = before;
            break;
          }
        }
        final sp0 = math.sqrt(pre.$1 * pre.$1 + pre.$2 * pre.$2), sp1 = _spd(b);
        final kn = b.vx / -pre.$1, kt = deg == 90 ? double.nan : b.vy / pre.$2;
        final aout = math.atan2(b.vx.abs(), b.vy.abs()) * 180 / math.pi;
        _log('| ${deg.round()}° | ${disc ? 'disc' : 'ball'} | ${_f(sp1 / sp0 * 100, 1)}% | ${_f(kn * 100, 1)}% | ${kt.isNaN ? '-' : '${_f(kt * 100, 1)}%'} | ${deg == 90 ? '${_f(aout, 1)}°' : '${_f(aout, 1)}°'} |');
      }
    }
    _log('');

    _log('## 7. Corners: ball / disc aimed at the corner vertex, 10..80° to the side rail (5° steps), 800 / 1600 / 3000 px/s, all 4 corners');
    _log('pocket = touching the corner (centre within r + 30 px of both rails); left = cleared the corner (> r + 250 px from the rail it is further from); stuck = at rest touching the corner arc');
    for (final disc in [false, true]) {
      var cases = 0, left = 0, restPocket = 0, restOut = 0, restNear = 0, back = 0, side = 0, end = 0, diag = 0;
      var tSum = 0.0, tMax = 0.0;
      for (var corner = 0; corner < 4; corner++) {
        for (var deg = 10; deg <= 80; deg += 5) {
          for (final v in [800.0, 1600.0, 3000.0]) {
            final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
            if (disc) _place(e.ball, e.CX, e.CY);
            final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
            final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
            final a = deg * math.pi / 180, ux = math.sin(a) * sx, uy = math.cos(a) * sy; // deg = angle to the side rail
            _place(b, cx - ux * 300, cy - uy * 300, ux * v, uy * v);
            var t = 0.0, tIn = -1.0, out = false;
            for (var i = 0; i < 480 * 6; i++) {
              e.update(1 / 480);
              t += 1 / 480;
              final gx = (b.x - cx).abs() - b.r, gy = (b.y - cy).abs() - b.r;
              if (tIn < 0 && gx < 30 && gy < 30) tIn = t;
              if (tIn >= 0 && math.max(gx, gy) > 250) {
                out = true;
                break;
              }
              if (b.vx == 0 && b.vy == 0) break;
            }
            if (tIn < 0) continue; // never reached the corner (ran out of speed on the way)
            cases++;
            final gx = (b.x - cx).abs() - b.r, gy = (b.y - cy).abs() - b.r;
            if (out) {
              left++;
              tSum += t - tIn;
              tMax = math.max(tMax, t - tIn);
              final s = _spd(b), cosBack = -(b.vx * ux + b.vy * uy) / s;
              if (cosBack > math.cos(20 * math.pi / 180)) {
                back++;
              } else if (b.vy.abs() > b.vx.abs() * 2) {
                side++;
              } else if (b.vx.abs() > b.vy.abs() * 2) {
                end++;
              } else {
                diag++;
              }
            } else if (math.sqrt(math.pow(b.x - (cx - sx * kPhys.cornerR), 2) + math.pow(b.y - (cy - sy * kPhys.cornerR), 2)) > kPhys.cornerR - b.r - 1 &&
                (b.x - (cx - sx * kPhys.cornerR)) * sx > 0 && (b.y - (cy - sy * kPhys.cornerR)) * sy > 0) {
              restPocket++;
            } else {
              restOut++;
              if (gx < kPhys.bankZone && gy < kPhys.bankZone) restNear++;
            }
          }
        }
      }
      _log('${disc ? 'disc' : 'ball'}: $cases shots reached the corner: $left left the corner, $restOut came to rest without clearing 250 px (not touching the corner; $restNear of them inside the corner bank zone), $restPocket stuck touching the corner; '
          'time pocket->clear mean ${left == 0 ? '-' : _f(tSum / left * 1000)} ms, max ${_f(tMax * 1000)} ms; exit directions: within 20° of straight back $back, '
          'along the side rail $side, along the end rail $end, diagonal $diag');
    }
    _log('');

    _log('## 8. Rest: two discs + ball touching (0.2 px overlap), 2 s');
    {
      final e = _lab(2), a = e.bodies[0], c = e.bodies[1], bb = e.ball;
      _place(a, e.CX, e.CY);
      _place(c, e.CX + a.r + c.r - .2, e.CY);
      _place(bb, e.CX, e.CY - a.r - bb.r + .2);
      final p0 = [a.x, a.y, c.x, c.y, bb.x, bb.y];
      var mx = 0.0;
      for (var i = 0; i < 120; i++) {
        e.update(1 / 60);
        mx = math.max(mx, math.max(_dist(a.x, a.y, p0[0], p0[1]), math.max(_dist(c.x, c.y, p0[2], p0[3]), _dist(bb.x, bb.y, p0[4], p0[5]))));
      }
      _log('max drift ${_f(mx, 6)} px\n');
    }
  });
}
