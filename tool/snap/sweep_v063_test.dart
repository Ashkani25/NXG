// Headless physics sweep (v0.6.3 brief): run before and after a physics change and diff the tables.
//   NO_PROXY=127.0.0.1,localhost NX_SWEEP=/path/out.md flutter test tool/snap/sweep_v063_test.dart
// Only measures; asserts nothing (the contract lives in test/physics_v063_test.dart).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg() => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: const [DiscStats(7, 10), DiscStats(7, 10)]);

Engine _lab(int keep) {
  final e = Engine(_cfg(), rand: math.Random(3).nextDouble);
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

/// rotation angle (rad) between two 3x3 row-major rotation matrices
double _rotAng(List<double> a, List<double> b) {
  var tr = 0.0;
  for (var i = 0; i < 3; i++) {
    for (var k = 0; k < 3; k++) {
      tr += a[k * 3 + i] * b[k * 3 + i];
    }
  }
  return math.acos(((tr - 1) / 2).clamp(-1.0, 1.0));
}

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
    final t0 = _lab(0).tu;
    _log('# Physics sweep (profile ${t0.name}; disc m ${t0.discM}, ball m ${t0.ballM}, ratio ${_f(t0.discM / t0.ballM, 2)})\n');

    // ---------------- 1. launch speed ----------------
    _log('## 1. Disc launch (alone, fired up the pitch, accuracy 10)');
    _log('| power | pull | launch px/s | glide px | time to rest s |');
    _log('|---|---|---|---|---|');
    for (final pw in [7.0, 10.0]) {
      for (final pull in [1.0, .6, .25]) {
        final e = _lab(1), d = e.bodies.first;
        e.cfg.stats = [DiscStats(pw, 10), DiscStats(pw, 10)];
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

    // ---------------- 2. disc strikes the ball ----------------
    _log('## 2. Full-pull disc (power 7) strikes a still ball; offset = ball centre offset across the shot line');
    _log('| offset | disc px/s at contact | disc px/s just after | disc kept % | disc travel after contact px | ball px/s just after | ball/disc ratio | ball path px | ball time to rest s |');
    _log('|---|---|---|---|---|---|---|---|---|');
    for (final off in [0.0, .5]) {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      final m = d.r + b.r;
      _place(b, e.CX - 250 + off * m, e.Fb - 330);
      _place(d, e.CX - 250, e.Fb - 120);
      e.fire(d, 0, -LMAX, LMAX, true);
      var vd = 0.0, cx = 0.0, cy = 0.0;
      var hit = false;
      // tiny steps around the contact so friction between before/after is negligible
      for (var i = 0; i < 6000 && !hit; i++) {
        vd = _spd(d);
        e.update(1 / 2400);
        hit = _spd(b) > 0;
      }
      cx = d.x;
      cy = d.y;
      final vdA = _spd(d), vbA = _spd(b);
      var t = 0.0, pathB = 0.0;
      while (t < 20 && (_spd(b) > 0 || _spd(d) > 0)) {
        final x0 = b.x, y0 = b.y;
        e.update(1 / 60);
        t += 1 / 60;
        if (_spd(b) > 0 || pathB == 0) pathB += _dist(b.x, b.y, x0, y0);
      }
      // ball time to rest measured separately (until the ball alone stops)
      final e2 = _lab(1), d2 = e2.bodies.first, b2 = e2.ball;
      _place(b2, e2.CX - 250 + off * m, e2.Fb - 330);
      _place(d2, e2.CX - 250, e2.Fb - 120);
      e2.fire(d2, 0, -LMAX, LMAX, true);
      var tb = 0.0, started = false;
      for (var i = 0; i < 60 * 20; i++) {
        e2.update(1 / 60);
        if (_spd(b2) > 0) started = true;
        if (started) tb += 1 / 60;
        if (started && _spd(b2) == 0) break;
      }
      final dTravel = _dist(d.x, d.y, cx, cy);
      _log('| ${_f(off * 100)}% | ${_f(vd)} | ${_f(vdA)} | ${_f(vdA / vd * 100, 1)}% | ${_f(dTravel)} | ${_f(vbA)} | ${_f(vbA / vd, 2)} | ${_f(pathB)} | ${_f(tb, 2)} |');
    }
    _log('');

    // ---------------- 3. ball strikes a still disc ----------------
    _log('## 3. Ball (2000 px/s) strikes a still disc head-on');
    {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(d, e.CX, e.CY);
      _place(b, e.CX, e.CY + 260, 0, -2000);
      var vb = 0.0;
      for (var i = 0; i < 6000 && _spd(d) == 0; i++) {
        vb = _spd(b);
        e.update(1 / 2400);
      }
      final x0 = d.x, y0 = d.y, vdA = _spd(d), vbA = b.vy;
      for (var i = 0; i < 60 * 10 && _spd(d) > 0; i++) {
        e.update(1 / 60);
      }
      _log('ball ${_f(vb)} px/s -> disc leaves at ${_f(vdA)} px/s (${_f(vdA / vb * 100, 1)}% of the ball speed), disc travels ${_f(_dist(d.x, d.y, x0, y0))} px; ball after ${_f(vbA)} px/s (+ = back)\n');
    }

    // ---------------- 4. free ball ----------------
    _log('## 4. Free ball roll (straight up the middle, no walls in reach for slow; diagonal with cushions for fast)');
    _log('| start px/s | path px | time to rest s | speed just before the stop px/s |');
    _log('|---|---|---|---|');
    for (final v in [4000.0, 3000.0, 1500.0, 600.0]) {
      final e = _lab(0), b = e.ball;
      _place(b, e.Fl + 120, e.Fb - 120, v * .6, -v * .8);
      var t = 0.0, path = 0.0, last = v;
      while (t < 20 && _spd(b) > 0) {
        final x0 = b.x, y0 = b.y;
        last = _spd(b);
        e.update(1 / 60);
        t += 1 / 60;
        path += _dist(b.x, b.y, x0, y0);
      }
      _log('| ${_f(v)} | ${_f(path)} | ${_f(t, 2)} | ${_f(last, 1)} |');
    }
    _log('');

    // ---------------- 5. cushions ----------------
    _log('## 5. Cushions (1500 px/s into the left wall; angle between path and wall)');
    _log('| angle | body | speed kept | normal kept | along-wall kept | angle out |');
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
        _log('| ${deg.round()}° | ${disc ? 'disc' : 'ball'} | ${_f(sp1 / sp0 * 100, 1)}% | ${_f(kn * 100, 1)}% | ${kt.isNaN ? '-' : '${_f(kt * 100, 1)}%'} | ${deg == 90 ? '90°' : '${_f(aout, 1)}°'} |');
      }
    }
    _log('');

    // ---------------- 6. corners ----------------
    _log('## 6. Corner shots (ball into each of the 4 corners, 10..80° to the side wall, 900 / 1800 / 3500 px/s)');
    var cases = 0, reached = 0, escaped = 0, stuck = 0, back = 0, side = 0, end = 0, diag = 0;
    var tEsc = 0.0;
    for (var corner = 0; corner < 4; corner++) {
      for (var deg = 10; deg <= 80; deg += 10) {
        for (final v in [900.0, 1800.0, 3500.0]) {
          final e = _lab(0), b = e.ball;
          final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
          final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
          final a = deg * math.pi / 180;
          final ux = math.cos(a) * sx, uy = math.sin(a) * sy;
          final tx = cx - sx * b.r, ty = cy - sy * b.r;
          _place(b, tx - ux * 180, ty - uy * 180, ux * v, uy * v);
          var left = false, t = 0.0, dmin = 1e9, tIn = -1.0;
          for (var i = 0; i < 480 * 8; i++) {
            e.update(1 / 480);
            t += 1 / 480;
            final dc = math.max((b.x - cx).abs(), (b.y - cy).abs());
            dmin = math.min(dmin, dc);
            if (dc < b.r * 1.3 && tIn < 0) tIn = t;
            if (tIn >= 0 && dc > b.r * 4) {
              left = true;
              break;
            }
            if (b.vx == 0 && b.vy == 0) break;
          }
          cases++;
          final inPocket = dmin < b.r * 1.3;
          if (inPocket) reached++;
          final jam = ((b.x - b.r - e.Fl).abs() < 3 || (e.Fr - b.x - b.r).abs() < 3) &&
              ((b.y - b.r - e.Ft).abs() < 3 || (e.Fb - b.y - b.r).abs() < 3);
          if (!left && jam) stuck++;
          if (inPocket && left) {
            escaped++;
            tEsc += t - tIn;
            final s = _spd(b), cosBack = s == 0 ? 0 : -(b.vx * ux + b.vy * uy) / s;
            final ax = b.vx.abs(), ay = b.vy.abs();
            if (cosBack > math.cos(25 * math.pi / 180)) {
              back++;
            } else if (ay > ax * 2) {
              side++;
            } else if (ax > ay * 2) {
              end++;
            } else {
              diag++;
            }
          }
        }
      }
    }
    var nudged = 0;
    for (var corner = 0; corner < 4; corner++) {
      final e = _lab(0), b = e.ball;
      final x = corner.isEven ? e.Fl + b.r : e.Fr - b.r, y = corner < 2 ? e.Ft + b.r : e.Fb - b.r;
      _place(b, x, y, corner.isEven ? -30 : 30, corner < 2 ? -30 : 30);
      for (var i = 0; i < 120; i++) {
        e.update(1 / 60);
      }
      if ((b.x - x).abs() > 3 || (b.y - y).abs() > 3) nudged++;
    }
    _log('$cases shots, $reached reached the corner pocket, $escaped left it (> 4 radii), $stuck stuck; mean time in the pocket ${escaped == 0 ? '-' : _f(tEsc / escaped, 3)} s');
    _log('exit direction of the escapes: straight back (within 25° of the reverse path) $back, up/down the side wall $side, along the end wall $end, diagonal $diag');
    _log('ball parked jammed in a corner moved out: $nudged / 4\n');

    // ---------------- 7. visual spin + wobble ----------------
    _log('## 7. Visual ball spin and disc wobble');
    _log('| ball shot at px/s | measured after s | ball px/s then | v/r rad/s | measured spin rad/s | rotation per 60 fps frame |');
    _log('|---|---|---|---|---|---|');
    for (final v in [300.0, 1000.0, 2500.0, 4000.0]) {
      for (final pre in [1, 6, 15]) {
        final e = _lab(0), b = e.ball;
        _place(b, e.CX, e.Fb - 60, 0, -v);
        for (var i = 0; i < pre - 1; i++) {
          e.update(1 / 60);
        }
        final r0 = List<double>.of(b.R), s0 = _spd(b);
        e.update(1 / 60);
        final ang = _rotAng(r0, b.R), s1 = (s0 + _spd(b)) / 2;
        _log('| ${_f(v)} | ${_f(pre / 60, 3)} | ${_f(s1)} | ${_f(s1 / b.r, 1)} | ${_f(ang * 60, 1)} | ${_f(ang * 180 / math.pi, 1)}° |');
      }
    }
    {
      // squash pulse on a disc during a full-power strike, and jitter of a resting disc + ball in light contact
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(b, e.CX - 250, e.Fb - 330);
      _place(d, e.CX - 250, e.Fb - 120);
      e.fire(d, 0, -LMAX, LMAX, true);
      var sqD = 0.0, sqB = 0.0;
      for (var i = 0; i < 120; i++) {
        e.update(1 / 60);
        sqD = math.max(sqD, d.sq);
        sqB = math.max(sqB, b.sq);
      }
      final e2 = _lab(2), a = e2.bodies[0], c = e2.bodies[1], bb = e2.ball;
      _place(a, e2.CX, e2.CY);
      _place(c, e2.CX + a.r + c.r - .6, e2.CY);
      _place(bb, e2.CX, e2.CY - a.r - bb.r + .6);
      final p0 = [a.x, a.y, c.x, c.y, bb.x, bb.y];
      var mx = 0.0;
      for (var i = 0; i < 120; i++) {
        e2.update(1 / 60);
        mx = math.max(mx, math.max(_dist(a.x, a.y, p0[0], p0[1]), math.max(_dist(c.x, c.y, p0[2], p0[3]), _dist(bb.x, bb.y, p0[4], p0[5]))));
      }
      _log('\nsquash pulse on a full-power hit: disc radius +${_f(sqD * 7, 2)}%, ball +${_f(sqB * 8, 2)}% (render scale = 1 + sq x .07 / .08)');
      _log('two discs + ball resting 0.6 px overlapped: max drift over 2 s ${_f(mx, 2)} px, final speeds ${_f(_spd(a), 1)} / ${_f(_spd(c), 1)} / ${_f(_spd(bb), 1)} px/s\n');
    }
  });
}
