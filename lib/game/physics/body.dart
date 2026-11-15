// Rigid disc / ball body shared by the physics world, the renderer and the netcode.
import 'dart:typed_data';

import '../fdlibm.dart';
import 'physics_config.dart';

class Goal {
  final int team;
  final double y, x1, x2;
  final int d;
  const Goal(this.team, this.y, this.x1, this.x2, this.d);
}

class Body {
  final int id;
  final int team; // 0 | 1 | 2 (ball)
  double x, y, px, py, vx = 0, vy = 0;
  final double r;

  /// inverse mass (1 / m); per piece from its mass attribute in the 'stars' profile
  double im;

  // ---- v0.6.4 piece attributes (stars profile) ----
  PieceAttrs attrs = PieceAttrs.neutral;

  /// power factor carried by the body for the rail impact boost (a disc: its own; the ball: last disc that struck it)
  double pf = 1;

  /// damping multiplier from the control attribute
  double dampMul = 1;

  /// rail friction multiplier from the rotational-inertia attribute
  double muMul = 1;

  double spin = 0, ang = 0;
  final Float64List R = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  double sq = 0, tvx = 0, tvy = 0, ramp = 0, boost = 0, vox = 0, voy = 0;
  double w = 0, wax = 0, way = 0; // visual roll: angular speed (rad/s) about the axis (wax, way, 0)
  Goal? gout;
  // per-disc motion trail: ring of at most 13 points (TS keeps <= 12 after shift)
  final Float64List trX = Float64List(16), trY = Float64List(16);
  int trStart = 0, trLen = 0;
  Body(this.x, this.y, this.team, this.r, double m, this.id)
      : px = x,
        py = y,
        im = 1 / m;

  bool get isBall => team == 2;

  /// at rest: exactly zero velocity (the world never moves a sleeping body on its own)
  bool get asleep => vx == 0 && vy == 0;

  void trPush(double x, double y) {
    final i = (trStart + trLen) & 15;
    trX[i] = x;
    trY[i] = y;
    trLen++;
  }

  void trShift() {
    if (trLen == 0) return;
    trStart = (trStart + 1) & 15;
    trLen--;
  }

  /// copy of the physical state only (trajectory preview); visuals and trails are not copied
  Body clonePhys() {
    final c = Body(x, y, team, r, 1, id)
      ..im = im
      ..vx = vx
      ..vy = vy
      ..attrs = attrs
      ..pf = pf
      ..dampMul = dampMul
      ..muMul = muMul
      ..gout = gout;
    return c;
  }
}

/// Rotate a row-major 3x3 matrix R by angle th about the unit axis (ax, ay, 0): R = Q * R, then renormalise row 0.
/// fdlibm sin / cos: bit-identical on every peer.
void rotateRoll(Float64List R, double ax, double ay, double th) {
  if (th < 1e-9) return;
  final c = fcos(th), s = fsin(th), t = 1 - c;
  final m0 = t * ax * ax + c, m1 = t * ax * ay, m2 = s * ay;
  final m3 = t * ax * ay, m4 = t * ay * ay + c, m5 = -s * ax;
  final m6 = -s * ay, m7 = s * ax, m8 = c;
  final r0 = R[0], r1 = R[1], r2 = R[2], r3 = R[3], r4 = R[4], r5 = R[5], r6 = R[6], r7 = R[7], r8 = R[8];
  R[0] = m0 * r0 + m1 * r3 + m2 * r6;
  R[1] = m0 * r1 + m1 * r4 + m2 * r7;
  R[2] = m0 * r2 + m1 * r5 + m2 * r8;
  R[3] = m3 * r0 + m4 * r3 + m5 * r6;
  R[4] = m3 * r1 + m4 * r4 + m5 * r7;
  R[5] = m3 * r2 + m4 * r5 + m5 * r8;
  R[6] = m6 * r0 + m7 * r3 + m8 * r6;
  R[7] = m6 * r1 + m7 * r4 + m8 * r7;
  R[8] = m6 * r2 + m7 * r5 + m8 * r8;
}
