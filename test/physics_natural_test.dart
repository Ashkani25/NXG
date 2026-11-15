// v0.6.4 physics contract ('stars' profile, unified physics world in lib/game/physics/).
// Measured tables: tool/snap/sweep_v064_test.dart, PHYSICS_NOTES.md.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg({double pw = 7, List<DiscStats>? st, bool ai = false, int field = 0}) => MatchCfg(
    field: field, ball: 0, forms: [0, 0], ai: ai, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: st ?? [DiscStats(pw, 10), DiscStats(pw, 10)]);

/// engine with only [keep] discs + the ball, everything still
Engine _lab(int keep, {double pw = 7, List<DiscStats>? st}) {
  final e = Engine(_cfg(pw: pw, st: st), rand: math.Random(3).nextDouble);
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
bool _still(Engine e) => e.bodies.every((b) => b.vx == 0 && b.vy == 0);

/// run until everything rests (or [maxS] seconds); returns the time taken
double _settle(Engine e, {double dt = 1 / 60, double maxS = 20}) {
  var t = 0.0;
  while (t < maxS && !_still(e)) {
    e.update(dt);
    t += dt;
  }
  return t;
}

/// a lone disc fired straight up from the bottom rail: (launch speed, path length, time to rest)
(double, double, double) _shot(double pw, double pull) {
  final e = _lab(1, pw: pw), d = e.bodies.first;
  _place(e.ball, e.Fr - 60, e.CY);
  _place(d, e.CX - 200, e.Fb - 80);
  e.fire(d, 0, -LMAX * pull, LMAX * pull, true);
  final v0 = _spd(d);
  var t = 0.0, path = 0.0;
  while (t < 20 && _spd(d) > 0) {
    final x0 = d.x, y0 = d.y;
    e.update(1 / 60);
    t += 1 / 60;
    path += math.sqrt((d.x - x0) * (d.x - x0) + (d.y - y0) * (d.y - y0));
  }
  return (v0, path, t);
}

/// fire [b] into the left rail at [deg] to the rail with speed [v]; returns (velocity just before, just after)
((double, double), (double, double)) _rail(Engine e, Body b, double deg, double v) {
  final a = deg * math.pi / 180;
  final vx = -v * math.sin(a), vy = v * math.cos(a);
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
  return (pre, (b.vx, b.vy));
}

void main() {
  group('geometry', () {
    test('stars is the default profile and runs the physics world', () {
      final e = Engine(MatchCfg(field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0));
      expect(e.cfg.profile, 'stars');
      expect(e.stars, isTrue);
      expect(e.world, isNotNull);
    });

    test('rails are the pitch art\'s own lines; ball 12% bigger; wider/deeper goals with post circles', () {
      for (var fi = 0; fi < kFields.length; fi++) {
        final e = Engine(_cfg(field: fi)), a = kFields[fi];
        expect(e.Fl, closeTo(a.L * e.artK + e.artOx, 1e-9));
        expect(e.Fr, closeTo(a.R * e.artK + e.artOx, 1e-9));
        expect(e.Ft, closeTo(a.T * e.artK + e.artOy, 1e-9));
        expect(e.Fb, closeTo(a.B * e.artK + e.artOy, 1e-9));
        expect(e.Fb - e.Ft, closeTo(kPlayField.B - kPlayField.T, 1e-9), reason: 'pitch length unchanged');
      }
      final e = Engine(_cfg());
      expect(e.ball.r, closeTo(21.6 * 1.12, .01));
      expect(e.bodies.first.r, 49);
      expect(e.goals[0].x2 - e.goals[0].x1, 272);
      expect(e.DEPTH, 74);
      final posts = e.boundary!.posts;
      expect(posts.length, 4);
      expect(posts.every((p) => p.rad == kPhys.postR), isTrue);
      expect(posts.map((p) => p.x).toSet(), {e.goals[0].x1, e.goals[0].x2});
    });
  });

  group('shots', () {
    test('weak / medium / strong: monotonic, bounded, all come to rest', () {
      final w = _shot(7, .25), m = _shot(7, .6), s = _shot(7, 1);
      // ignore: avoid_print
      print('power 7: weak ${w.$1.round()} px/s ${w.$2.round()} px ${w.$3.toStringAsFixed(2)} s | medium ${m.$1.round()} ${m.$2.round()} ${m.$3.toStringAsFixed(2)} | strong ${s.$1.round()} ${s.$2.round()} ${s.$3.toStringAsFixed(2)}');
      expect(w.$2, inInclusiveRange(100, 260));
      expect(m.$2, inInclusiveRange(450, 750));
      expect(s.$2, inInclusiveRange(1100, 1700));
      expect(w.$3, lessThan(1.2));
      expect(s.$3, lessThan(2.2));
      expect(m.$2, greaterThan(w.$2 * 2));
      expect(s.$2, greaterThan(m.$2 * 1.6));
      expect(s.$1, lessThanOrEqualTo(kPhys.vCap));
    });

    test('pull curve: smooth, monotonic, no spikes', () {
      var prev = 0.0, prevD = 0.0;
      for (var i = 0; i <= 100; i++) {
        final v = shotCurve(i / 100);
        expect(v, greaterThanOrEqualTo(prev));
        if (i > 1) expect(v - prev, lessThan(prevD + .002), reason: 'no jump at ${i / 100}');
        prevD = v - prev;
        prev = v;
      }
      expect(shotCurve(1), 1);
    });

    test('every power 1..10: launch 0.70..1.30 x base, glide monotonic and clearly distinct', () {
      var prevV = 0.0, prevD = 0.0;
      for (var pw = 1; pw <= 10; pw++) {
        final (v, d, _) = _shot(pw.toDouble(), .6);
        expect(v / (kPhys.shotBase * shotCurve(.6)), closeTo(.70 + .60 * (pw - 1) / 9, 1e-9));
        if (pw > 1) {
          expect(v, greaterThan(prevV * 1.03), reason: 'power $pw launch');
          expect(d - prevD, greaterThan(25), reason: 'power $pw glide');
        }
        prevV = v;
        prevD = d;
      }
    });

    test('identical shots are bit-identical (determinism)', () {
      List<double> run() {
        final e = Engine(_cfg(), rand: math.Random(9).nextDouble);
        e.fire(e.bodies[2], 30, -LMAX, math.sqrt(30 * 30 + LMAX * LMAX), true);
        _settle(e);
        return [for (final b in e.bodies) ...[b.x, b.y]];
      }

      expect(run(), run());
    });

    test('30 / 60 / 120 fps give bit-identical outcomes', () {
      List<double> run(double fps) {
        final e = Engine(_cfg(), rand: math.Random(9).nextDouble);
        e.fire(e.bodies[2], 30, -LMAX, math.sqrt(30 * 30 + LMAX * LMAX), true);
        _settle(e, dt: 1 / fps);
        return [for (final b in e.bodies) ...[b.x, b.y]];
      }

      final a = run(30), b = run(60), c = run(120);
      expect(b, a);
      expect(c, a);
    });
  });

  group('collisions', () {
    test('disc-disc head-on: momentum kept, struck disc takes (1 + e) / 2', () {
      final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
      _place(e.ball, e.Fr - 60, e.Ft + 60);
      _place(c, e.CX, e.CY);
      _place(a, e.CX, e.CY + 250, 0, -1500);
      var va = 0.0;
      for (var i = 0; i < 6000 && c.vy == 0; i++) {
        va = -a.vy;
        e.update(1 / 2400);
      }
      final pBefore = va / a.im, pAfter = -(a.vy / a.im + c.vy / c.im);
      expect(pAfter / pBefore, closeTo(1, .02));
      expect(-c.vy / va, closeTo((1 + kPhys.eDiscDisc) / 2, .03));
      expect(c.vx.abs() + a.vx.abs(), lessThan(1e-6), reason: 'centred hit: pure normal impulse');
    });

    test('angled disc-disc: struck disc leaves along the line of centres, momentum vector kept', () {
      final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
      _place(e.ball, e.Fr - 60, e.Ft + 60);
      final off = (a.r + c.r) * .5;
      _place(c, e.CX + off, e.CY);
      _place(a, e.CX, e.CY + 300, 0, -1500);
      double px = 0, py = 0;
      for (var i = 0; i < 6000 && c.vy == 0; i++) {
        px = a.vx / a.im;
        py = a.vy / a.im;
        e.update(1 / 4800);
      }
      final qx = a.vx / a.im + c.vx / c.im, qy = a.vy / a.im + c.vy / c.im;
      expect(math.sqrt((qx - px) * (qx - px) + (qy - py) * (qy - py)) / math.sqrt(px * px + py * py), lessThan(.03));
      final nx = c.x - a.x, ny = c.y - a.y, nl = math.sqrt(nx * nx + ny * ny);
      final cosA = (c.vx * nx + c.vy * ny) / (nl * _spd(c));
      expect(cosA, greaterThan(.99), reason: 'struck disc follows the normal (small contact friction only)');
      expect(a.vx, lessThan(0), reason: 'striker deflects to the other side');
    });

    test('disc strikes the ball: ball flies ~1.4x, disc follows at about half speed (mass ratio 3:1)', () {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(b, e.CX - 250, e.Fb - 330);
      _place(d, e.CX - 250, e.Fb - 120);
      e.fire(d, 0, -LMAX, LMAX, true);
      var vd = 0.0;
      for (var i = 0; i < 6000 && _spd(b) == 0; i++) {
        vd = _spd(d);
        e.update(1 / 2400);
      }
      expect(_spd(b) / vd, inInclusiveRange(1.3, 1.5));
      expect(_spd(d) / vd, inInclusiveRange(.4, .65));
      expect(b.pf, d.pf, reason: 'ball carries the striker\'s power factor');
    });

    test('ball strikes a still disc: bounces back, the heavier disc moves off slower', () {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(d, e.CX, e.CY);
      _place(b, e.CX, e.CY + 260, 0, -2000);
      var vb = 0.0;
      for (var i = 0; i < 6000 && _spd(d) == 0; i++) {
        vb = _spd(b);
        e.update(1 / 2400);
      }
      expect(b.vy, greaterThan(0));
      expect(_spd(d) / vb, inInclusiveRange(.4, .55));
    });

    test('mass attribute: a heavy disc is pushed less than a light one by the same hit', () {
      double push(double mass) {
        final e = _lab(2, st: [DiscStats(7, 10, mass: mass), DiscStats(7, 10, mass: mass)]);
        final a = e.bodies[0], c = e.bodies[1];
        _place(e.ball, e.Fr - 60, e.Ft + 60);
        _place(c, e.CX, e.CY);
        _place(a, e.CX, e.CY + 250);
        c.im = 1 / kPhys.massOf(mass); // the struck disc's own mass
        a.im = 1 / kPhys.massOf(5.5);
        a.vy = -1500;
        for (var i = 0; i < 6000 && c.vy == 0; i++) {
          e.update(1 / 2400);
        }
        return -c.vy;
      }

      expect(push(10), lessThan(push(1) * .85));
    });

    test('multi-collision: a 5-body cluster break settles cleanly, no overlap, no jitter, then stays still', () {
      final e = _lab(4), B = e.bodies;
      _place(B[1], e.CX, e.CY);
      _place(B[2], e.CX - 49.5, e.CY - 86);
      _place(B[3], e.CX + 49.5, e.CY - 86);
      _place(e.ball, e.CX, e.CY - 160);
      _place(B[0], e.CX + 10, e.Fb - 120, 0, -3400);
      final t = _settle(e);
      expect(t, lessThan(6));
      for (var i = 0; i < B.length; i++) {
        for (var k = i + 1; k < B.length; k++) {
          final d = math.sqrt(math.pow(B[i].x - B[k].x, 2) + math.pow(B[i].y - B[k].y, 2));
          expect(d, greaterThan(B[i].r + B[k].r - kPhys.slop - 1e-6));
        }
      }
      final snap = [for (final b in B) ...[b.x, b.y]];
      for (var i = 0; i < 180; i++) {
        e.update(1 / 60);
        for (final b in B) {
          expect(b.px, b.x, reason: 'renderer interpolates nothing while asleep');
        }
      }
      expect([for (final b in B) ...[b.x, b.y]], snap, reason: 'exactly still for 3 s');
    });

    test('resting contacts never drift (touching discs + ball, 3 s)', () {
      final e = _lab(2), a = e.bodies[0], c = e.bodies[1], bb = e.ball;
      _place(a, e.CX, e.CY);
      _place(c, e.CX + a.r + c.r - .2, e.CY);
      _place(bb, e.CX, e.CY - a.r - bb.r + .2);
      final p0 = [a.x, a.y, c.x, c.y, bb.x, bb.y];
      for (var i = 0; i < 180; i++) {
        e.update(1 / 60);
      }
      expect([a.x, a.y, c.x, c.y, bb.x, bb.y], p0);
    });

    test('no tunnelling at the speed cap: ball vs a disc, every rail and the posts', () {
      final e = _lab(1), d = e.bodies.first, b = e.ball;
      _place(d, e.CX, e.CY);
      _place(b, e.CX, e.Fb - 40, 0, -kPhys.vCap);
      for (var i = 0; i < 240; i++) {
        e.update(1 / 30); // coarse frames: the fixed step + CCD still catch it
        expect(b.y, greaterThan(d.y), reason: 'ball never passes through the disc');
        if (b.vy >= 0) break;
      }
      for (var k = 0; k < 64; k++) {
        final e2 = _lab(0), o = e2.ball, a = k * 2 * math.pi / 64;
        _place(o, e2.CX, e2.CY, math.cos(a) * kPhys.vCap, math.sin(a) * kPhys.vCap);
        for (var i = 0; i < 400; i++) {
          e2.update(1 / 30);
          final inGoal = o.x > e2.goals[0].x1 && o.x < e2.goals[0].x2;
          expect(o.x, inInclusiveRange(e2.Fl + o.r - 1e-6, e2.Fr - o.r + 1e-6));
          if (!inGoal) expect(o.y, inInclusiveRange(e2.Ft + o.r - 1e-6, e2.Fb - o.r + 1e-6));
          expect(o.y, inInclusiveRange(e2.Ft - e2.DEPTH + o.r - 1e-6, e2.Fb + e2.DEPTH - o.r + 1e-6));
        }
      }
    });
  });

  group('rails, posts, corners', () {
    test('direct rail hit: rebound = e + boost, below the incoming speed, power raises it', () {
      double ratio(double pf) {
        final e = _lab(0), b = e.ball;
        b.pf = pf;
        final (pre, post) = _rail(e, b, 90, 1500);
        return post.$1 / -pre.$1;
      }

      final lo = ratio(.7), mid = ratio(1), hi = ratio(1.3);
      // ignore: avoid_print
      print('direct rail rebound: pf .7 ${lo.toStringAsFixed(3)}, 1.0 ${mid.toStringAsFixed(3)}, 1.3 ${hi.toStringAsFixed(3)}');
      expect(mid, closeTo(kPhys.eRailBall + kPhys.boostK, .01));
      expect(hi, greaterThan(mid));
      expect(mid, greaterThan(lo));
      expect(hi, lessThan(kPhys.keepMax));
    });

    test('angled rail hit: tangential kept, normal reversed, angle out close to the mirror angle', () {
      for (final disc in [false, true]) {
        for (final deg in [15.0, 30.0, 45.0, 60.0]) {
          final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
          if (disc) _place(e.ball, e.Fr - 60, e.Fb - 60);
          final (pre, post) = _rail(e, b, deg, 1500);
          expect(post.$1, greaterThan(0));
          expect(post.$2 / pre.$2, inInclusiveRange(deg <= 45 ? .82 : .7, 1.0), reason: 'along-rail speed kept ($deg°): Coulomb rail friction');
          final aIn = math.atan2(-pre.$1, pre.$2) * 180 / math.pi, aOut = math.atan2(post.$1, post.$2) * 180 / math.pi;
          expect(aOut, inInclusiveRange(aIn * .6, aIn * 1.05), reason: '$deg°: out $aOut');
          expect(math.sqrt(post.$1 * post.$1 + post.$2 * post.$2), lessThan(1500));
        }
      }
    });

    test('repeated rebounds never gain energy (ball between the side rails)', () {
      final e = _lab(0), b = e.ball;
      b.pf = 1.3;
      _place(b, e.CX, e.CY, -kPhys.vCap, 0);
      var last = kPhys.vCap + 1;
      var bounces = 0;
      for (var i = 0; i < 4000 && _spd(b) > 0; i++) {
        final s0 = b.vx;
        e.update(1 / 480);
        if (s0.sign != b.vx.sign && b.vx != 0) {
          final s = _spd(b);
          expect(s, lessThan(last), reason: 'bounce $bounces');
          expect(s, lessThanOrEqualTo(kPhys.vCap));
          last = s;
          bounces++;
        }
      }
      expect(bounces, greaterThanOrEqualTo(2));
    });

    test('direct post hit: bounces back, never passes through', () {
      final e = _lab(0), b = e.ball, g = e.goals[1];
      _place(b, g.x1, g.y - 300, 0, 2500);
      var minD = 1e9;
      for (var i = 0; i < 300; i++) {
        e.update(1 / 60);
        minD = math.min(minD, math.sqrt(math.pow(b.x - g.x1, 2) + math.pow(b.y - g.y, 2)));
        if (b.vy < 0) break;
      }
      expect(b.vy, lessThan(0), reason: 'rebounded');
      expect(minD, greaterThan(b.r + kPhys.postR - .5));
    });

    test('corners: ball and disc into every corner at many angles: never stuck or resting in the corner, no jitter, fast shots leave quickly', () {
      var cases = 0, fastLeft = 0, fastCases = 0;
      var maxT = 0.0;
      for (final disc in [false, true]) {
        for (var corner = 0; corner < 4; corner++) {
          for (var deg = 10; deg <= 80; deg += 10) {
            for (final v in [900.0, 1800.0, 3200.0]) {
              final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
              if (disc) _place(e.ball, e.CX, e.CY);
              final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
              final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
              final a = deg * math.pi / 180, ux = math.sin(a) * sx, uy = math.cos(a) * sy;
              _place(b, cx - ux * 300, cy - uy * 300, ux * v, uy * v);
              var t = 0.0, tIn = -1.0, out = false, flips = 0;
              var lastVx = b.vx, lastVy = b.vy;
              for (var i = 0; i < 480 * 6; i++) {
                e.update(1 / 480);
                t += 1 / 480;
                final gx = (b.x - cx).abs() - b.r, gy = (b.y - cy).abs() - b.r;
                if (tIn < 0 && gx < 30 && gy < 30) tIn = t;
                if (tIn >= 0 && !out) {
                  if (b.vx.sign != lastVx.sign && b.vx != 0 && lastVx != 0) flips++;
                  if (b.vy.sign != lastVy.sign && b.vy != 0 && lastVy != 0) flips++;
                }
                lastVx = b.vx;
                lastVy = b.vy;
                if (tIn >= 0 && !out && math.max(gx, gy) > 200) {
                  out = true;
                  maxT = math.max(maxT, t - tIn);
                }
                if (b.vx == 0 && b.vy == 0) break;
              }
              if (tIn < 0) continue;
              cases++;
              final gx = (b.x - cx).abs() - b.r, gy = (b.y - cy).abs() - b.r;
              expect(gx < kPhys.bankZone && gy < kPhys.bankZone, isFalse,
                  reason: '${disc ? 'disc' : 'ball'} corner $corner $deg° $v: came to rest in the corner');
              expect(flips, lessThanOrEqualTo(4), reason: 'no vibration in the corner ($corner $deg° $v)');
              if (v >= 1800) {
                fastCases++;
                if (out) {
                  fastLeft++;
                } else {
                  // ignore: avoid_print
                  print('slow exit: ${disc ? 'disc' : 'ball'} corner $corner $deg° $v rest gaps ${gx.round()} / ${gy.round()}');
                }
              }
            }
          }
        }
      }
      // ignore: avoid_print
      print('corners: $cases reached, fast shots left $fastLeft / $fastCases, max time to clear ${(maxT * 1000).round()} ms');
      expect(fastLeft, fastCases);
      expect(maxT, lessThan(1.2));
    });

    test('a body placed resting in a corner pocket is eased out and comes to rest outside it', () {
      for (final disc in [false, true]) {
        for (var corner = 0; corner < 4; corner++) {
          final e = _lab(disc ? 1 : 0), b = disc ? e.bodies.first : e.ball;
          if (disc) _place(e.ball, e.CX, e.CY);
          final sx = corner.isEven ? -1.0 : 1.0, sy = corner < 2 ? -1.0 : 1.0;
          final cx = sx < 0 ? e.Fl : e.Fr, cy = sy < 0 ? e.Ft : e.Fb;
          final rr = kPhys.cornerR - b.r;
          final ax = cx - sx * kPhys.cornerR, ay = cy - sy * kPhys.cornerR;
          _place(b, ax + sx * rr * .7071, ay + sy * rr * .7071);
          for (var i = 0; i < 300; i++) {
            e.update(1 / 60); // starts asleep: the bank must wake it
          }
          final gx = (b.x - cx).abs() - b.r, gy = (b.y - cy).abs() - b.r;
          expect(gx < kPhys.bankZone && gy < kPhys.bankZone, isFalse);
          expect(_still(e), isTrue);
        }
      }
    });
  });

  group('aim preview', () {
    test('the preview predicts the real first contact exactly (same physics, copied state)', () {
      final e = Engine(_cfg(), rand: math.Random(5).nextDouble);
      final d = e.bodies.firstWhere((b) => b.team == 0);
      final dx = e.ball.x - d.x, dy = e.ball.y - d.y, l = math.sqrt(dx * dx + dy * dy);
      final pull = LMAX * .7;
      e.pick(d.x, d.y);
      e.move(d.x - dx / l * pull, d.y - dy / l * pull);
      final before = [for (final b in e.bodies) ...[b.x, b.y, b.vx, b.vy]];
      final p = e.aimPrediction()!;
      expect([for (final b in e.bodies) ...[b.x, b.y, b.vx, b.vy]], before, reason: 'live state untouched');
      expect(p.hit, isNot(0));
      e.release();
      // run the real shot step by step until the shooter's first contact (another body starts moving or the
      // shooter's direction changes); the predicted contact point must lie on the shooter's straight path inside
      // that very step
      var hit = false;
      double ax = 0, ay = 0;
      for (var i = 0; i < 2000 && !hit; i++) {
        ax = d.x;
        ay = d.y;
        final vx0 = d.vx, vy0 = d.vy;
        e.update(1 / 240);
        final turned = (vx0 * d.vy - vy0 * d.vx).abs() > 1e-6 * (vx0 * vx0 + vy0 * vy0);
        final other = e.bodies.any((b) => !identical(b, d) && (b.vx != 0 || b.vy != 0));
        hit = turned || other;
      }
      expect(hit, isTrue);
      final sx = d.x - ax, sy = d.y - ay;
      // distance of the predicted contact from the segment start along the incoming direction: within one step
      final ux = d.vx, uy = d.vy;
      expect(ux.isFinite && uy.isFinite, isTrue);
      final pdx = p.hx - ax, pdy = p.hy - ay;
      expect(math.sqrt(pdx * pdx + pdy * pdy), lessThan(math.sqrt(sx * sx + sy * sy) + 20), reason: 'predicted contact inside the contact step');
      if (p.hit == 1) expect(identical(p.target, e.ball) || p.target!.team != 2, isTrue);
    });
  });

  test('AI vs AI match: deterministic and NaN-free (3000 frames, mixed frame times)', () {
    List<double> run() {
      final e = Engine(_cfg(ai: true), rand: math.Random(42).nextDouble);
      e.aiTeams[0] = true;
      final out = <double>[];
      for (var f = 0; f < 3000; f++) {
        e.update(f % 3 == 0 ? 1 / 50 : 1 / 60);
        if (f % 25 == 0) {
          for (final b in e.bodies) {
            out
              ..add(b.x)
              ..add(b.y)
              ..add(b.vx)
              ..add(b.vy);
          }
          out
            ..add(e.score[0].toDouble())
            ..add(e.score[1].toDouble())
            ..add(e.shots.toDouble());
        }
      }
      return out;
    }

    final a = run(), b = run();
    expect(a, b);
    expect(a.any((v) => v.isNaN), isFalse);
  });
}
