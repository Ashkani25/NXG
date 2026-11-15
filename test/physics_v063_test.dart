// v0.6.3 physics contract (owner brief 2026-11-15, 'stars' standard solver). Measured values: tool/snap/sweep_v063_test.dart.
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

/// full-pull power-7 disc into a still ball offset [off] radii-sums across the line:
/// (disc speed at contact, disc speed after, ball speed after, disc travel after contact)
(double, double, double, double) _strike(double off) {
  final e = _lab(1), d = e.bodies.first, b = e.ball;
  _place(b, e.CX - 250 + off * (d.r + b.r), e.Fb - 330);
  _place(d, e.CX - 250, e.Fb - 120);
  e.fire(d, 0, -LMAX, LMAX, true);
  var vd = 0.0;
  for (var i = 0; i < 6000 && _spd(b) == 0; i++) {
    vd = _spd(d);
    e.update(1 / 2400);
  }
  final x0 = d.x, y0 = d.y, vdA = _spd(d), vbA = _spd(b);
  for (var i = 0; i < 600 && _spd(d) > 0; i++) {
    e.update(1 / 60);
  }
  return (vd, vdA, vbA, math.sqrt((d.x - x0) * (d.x - x0) + (d.y - y0) * (d.y - y0)));
}

void main() {
  test('discs are 2-3x the ball; no squash pulse on discs', () {
    final r = kTuneStars.discM / kTuneStars.ballM;
    expect(r, inInclusiveRange(2, 3));
    expect(kTuneStars.sqDisc, 0);
  });

  test('shot power unchanged: full pull = 3057 px/s at power 7, 3500 at power 10', () {
    for (final (pw, v) in [(7.0, 3057.0), (10.0, 3500.0)]) {
      final e = _lab(1), d = e.bodies.first;
      e.cfg.stats = [DiscStats(pw, 10), DiscStats(pw, 10)];
      _place(e.ball, e.Fr - 60, e.CY);
      _place(d, e.CX, e.Fb - 80);
      e.fire(d, 0, -LMAX, LMAX, true);
      expect(_spd(d), closeTo(v, 1));
    }
  });

  test('head-on: the disc loses most of its speed and stays near the contact point; the ball flies', () {
    final (vd, vdA, vbA, travel) = _strike(0);
    // ignore: avoid_print
    print('head-on: disc $vd -> $vdA px/s, travels ${travel.round()} px; ball $vbA px/s');
    expect(vdA / vd, lessThan(.2));
    expect(travel, lessThan(120));
    expect(vbA / vd, greaterThan(1.35), reason: 'a full shot still sends the ball off hard');
  });

  test('glancing hit: the disc keeps less than half its speed', () {
    final (vd, vdA, _, travel) = _strike(.5);
    expect(vdA / vd, lessThan(.5));
    expect(travel, lessThan(400));
  });

  test('a ball striking a still disc barely moves it', () {
    final e = _lab(1), d = e.bodies.first, b = e.ball;
    _place(d, e.CX, e.CY);
    _place(b, e.CX, e.CY + 260, 0, -2000);
    var vb = 0.0;
    for (var i = 0; i < 6000 && _spd(d) == 0; i++) {
      vb = _spd(b);
      e.update(1 / 2400);
    }
    expect(_spd(d) / vb, lessThan(.15));
    expect(b.vy, greaterThan(0), reason: 'the ball bounces back off the heavy disc');
  });

  test('corners: never straight back, always slides out along a wall, never stuck', () {
    var back = 0, along = 0, n = 0;
    for (var corner = 0; corner < 4; corner++) {
      for (var deg = 10; deg <= 80; deg += 10) {
        for (final v in [900.0, 1800.0, 3500.0]) {
          final e = _lab(0), b = e.ball;
          final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
          final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
          final a = deg * math.pi / 180, ux = math.cos(a) * sx, uy = math.sin(a) * sy;
          _place(b, cx - sx * b.r - ux * 180, cy - sy * b.r - uy * 180, ux * v, uy * v);
          var tIn = -1.0, t = 0.0, left = false;
          for (var i = 0; i < 480 * 8 && !left; i++) {
            e.update(1 / 480);
            t += 1 / 480;
            final dc = math.max((b.x - cx).abs(), (b.y - cy).abs());
            if (dc < b.r * 1.3 && tIn < 0) tIn = t;
            left = tIn >= 0 && dc > b.r * 4;
          }
          n++;
          expect(left, isTrue, reason: 'corner $corner $deg° $v');
          final s = _spd(b);
          if (-(b.vx * ux + b.vy * uy) / s > math.cos(25 * math.pi / 180)) back++;
          if (b.vx.abs() > b.vy.abs() * 2 || b.vy.abs() > b.vx.abs() * 2) along++;
        }
      }
    }
    expect(back, 0);
    expect(along, n);
  });

  test('visual spin follows v / r, capped and eased (no wagon-wheel)', () {
    final e = _lab(0), b = e.ball;
    _place(b, e.CX, e.Fb - 60, 0, -4000);
    for (var i = 0; i < 20; i++) {
      e.update(1 / 60);
      expect(b.w, lessThanOrEqualTo(kTuneStars.spinCap + 1e-9));
    }
    expect(b.w, closeTo(kTuneStars.spinCap, .5));
    final e2 = _lab(0), b2 = e2.ball;
    _place(b2, e2.CX, e2.CY, 0, -200);
    for (var i = 0; i < 30; i++) {
      e2.update(1 / 60);
    }
    expect(b2.w, closeTo(_spd(b2) / b2.r, 1.5), reason: 'slow ball: true rolling');
  });
}
